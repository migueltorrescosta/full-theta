class_name WeaponSystem
extends RefCounted
## Mount slew and firing (T032). Each tick, per mount in row order: cooldown and heat
## fall, the barrel slews toward the aim point at MountDef.traverse_rate (scaled by the
## mount subsystem's effectiveness) without leaving the arc (FT-WPN-009, FT-SIM-011),
## and a requested shot fires or is blocked (FT-SIM-012). Shots are projectiles moved
## and swept by CollisionSystem in the same tick.

## Cooldown below this counts as done (s); absorbs float drift of repeated - DT.
const COOLDOWN_EPS: float = 1e-9


static func step(world: SimWorld) -> void:
	var mounts: MountTable = world.mounts
	var dt: float = SimWorld.DT
	for row: int in mounts.size():
		var ship: int = mounts.ship_ids[row]
		if not world.kin.is_alive(ship):
			mounts.fire_requested[row] = 0
			continue
		var def: MountDef = mount_def(world, row)
		mounts.cooldown[row] = maxf(0.0, mounts.cooldown[row] - dt)
		mounts.heat[row] *= exp(-def.weapon.heat_dissipation * dt)
		var eff: float = DamageSystem.effectiveness(world, ship, def.subsystem_id)
		var aim: Vector3 = aim_direction(world, row)
		var target: Vector3 = clamp_to_arc(def, aim)
		mounts.barrel[row] = turn_toward(
			mounts.barrel[row], target, def.traverse_rate * clampf(eff, 0.0, 1.0) * dt
		)
		if mounts.fire_requested[row] == 1:
			mounts.fire_requested[row] = 0
			_try_fire(world, row, def, eff, aim)


## The read-only definition of a mount row.
static func mount_def(world: SimWorld, row: int) -> MountDef:
	return world.defs[world.mounts.ship_ids[row]].mounts[world.mounts.mount_index[row]]


## Direction from the mount to its aim point in the ship frame (unit); the rest
## direction (MountDef.forward) while no aim point is set.
static func aim_direction(world: SimWorld, row: int) -> Vector3:
	var mounts: MountTable = world.mounts
	var def: MountDef = mount_def(world, row)
	if mounts.aim_set[row] == 0:
		return def.forward
	var ship: int = mounts.ship_ids[row]
	var kin: Kinematics = world.kin
	var to_aim: Vector3 = kin.relative_to_point(
		ship, mounts.aim_x[row], mounts.aim_y[row], mounts.aim_z[row]
	)
	var local: Vector3 = kin.to_local(ship, to_aim) - def.position
	if local.length_squared() < 1e-12:
		return mounts.barrel[row]
	return local.normalized()


## FT-SIM-011: a direction (ship frame) is inside the arc when its angle to the rest
## direction is at most arc_half_angle.
static func in_arc(def: MountDef, dir: Vector3) -> bool:
	return def.forward.angle_to(dir) <= def.arc_half_angle


## The direction itself when inside the arc, else the nearest direction on its edge.
static func clamp_to_arc(def: MountDef, dir: Vector3) -> Vector3:
	if in_arc(def, dir):
		return dir
	return turn_toward(def.forward, dir, def.arc_half_angle)


## Turns from toward to by at most max_angle (rad); both unit vectors.
static func turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle: float = from.angle_to(to)
	if angle <= max_angle:
		return to
	var axis: Vector3 = from.cross(to)
	if axis.length_squared() < 1e-12:
		axis = from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_angle).normalized()


## FT-SIM-016: the first friendly or neutral ship (world.relation not HOSTILE) the
## mount row's next shot would cross within the weapon's range, with every ship keeping
## its velocity, or -1. Only ships the shooter's faction detects count (FT-ARC-013; its
## own ships always do). A warning only: friendly fire still happens.
static func path_crosses(world: SimWorld, row: int) -> int:
	var ship_id: int = world.mounts.ship_ids[row]
	var kin: Kinematics = world.kin
	var def: MountDef = mount_def(world, row)
	var weapon: WeaponDef = def.weapon
	var muzzle: Vector3 = kin.to_world(ship_id, def.position)
	var pv: Vector3 = (
		kin.vel[ship_id] + kin.to_world(ship_id, world.mounts.barrel[row]) * weapon.projectile_speed
	)
	var flight: float = weapon.max_range / weapon.projectile_speed
	var faction: int = world.faction_of(ship_id)
	var best: int = -1
	var best_t: float = 2.0
	for j: int in kin.size():
		if j == ship_id or not kin.is_alive(j) or kin.site[ship_id] != kin.site[j]:
			continue
		if world.relation(faction, world.faction_of(j)) == SimWorld.Relation.HOSTILE:
			continue
		if not KnowledgeSystem.is_detected(world, faction, j):
			continue
		var axis: Vector3 = kin.to_world(j, Vector3(0.0, 0.0, kin.half_length[j]))
		var t: float = Sweep.capsule(
			muzzle - kin.relative(ship_id, j),
			(pv - kin.vel[j]) * flight,
			axis,
			kin.radius[j] + weapon.projectile_radius
		)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = j
	return best


## Why a requested shot can't fire, or &"" if it can (energy is checked last, by
## drawing it). FT-SIM-011 arc, FT-SIM-012 condition, cooldown, ammunition, heat. aim
## is the mount's aim_direction this tick.
static func block_reason(world: SimWorld, row: int, eff: float, aim: Vector3) -> StringName:
	var mounts: MountTable = world.mounts
	var def: MountDef = mount_def(world, row)
	var reason: StringName = &""
	if eff <= 0.0:
		reason = &"subsystem"
	elif not in_arc(def, aim):
		reason = &"arc"
	elif mounts.cooldown[row] > COOLDOWN_EPS:
		reason = &"cooldown"
	elif mounts.ammo[row] == 0:
		reason = &"ammo"
	elif mounts.heat[row] >= def.weapon.heat_limit:
		reason = &"heat"
	return reason


static func _try_fire(world: SimWorld, row: int, def: MountDef, eff: float, aim: Vector3) -> void:
	var ship: int = world.mounts.ship_ids[row]
	var index: int = world.mounts.mount_index[row]
	var reason: StringName = block_reason(world, row, eff, aim)
	if reason == &"" and not PowerSystem.draw_energy(world, ship, def.weapon.energy_per_shot):
		reason = &"energy"
	if reason != &"":
		world.emit(&"fire_blocked", ship, -1, index, Vector3.ZERO, reason)
		return
	var friend: int = path_crosses(world, row)
	_fire(world, row, def)
	if friend >= 0:
		world.emit(&"friendly_fire_warning", ship, friend, index)


## Spawns the projectile from the mount's hull position along the barrel, with the
## ship's velocity plus the muzzle velocity. It is placed where the muzzle was at the
## start of the tick, so CollisionSystem's full-tick sweep starts at the muzzle.
static func _fire(world: SimWorld, row: int, def: MountDef) -> void:
	var mounts: MountTable = world.mounts
	var kin: Kinematics = world.kin
	var ship: int = mounts.ship_ids[row]
	var weapon: WeaponDef = def.weapon
	if mounts.ammo[row] > 0:
		mounts.ammo[row] -= 1
	mounts.cooldown[row] = weapon.cooldown
	mounts.heat[row] += weapon.heat_per_shot
	var dir: Vector3 = kin.to_world(ship, mounts.barrel[row])
	var vs: Vector3 = kin.vel[ship]
	var back: Vector3 = kin.to_world(ship, def.position) - vs * SimWorld.DT
	var start: PackedFloat64Array = kin.point_at(ship, back)
	world.projectiles.spawn(
		ship,
		world.faction_of(ship),
		kin.site[ship],
		start[0],
		start[1],
		start[2],
		vs + dir * weapon.projectile_speed,
		weapon.projectile_radius,
		weapon.damage,
		ceili(weapon.max_range / weapon.projectile_speed * SimWorld.HZ)
	)
	world.emit(&"fired", ship, -1, mounts.mount_index[row], dir, weapon.id)
