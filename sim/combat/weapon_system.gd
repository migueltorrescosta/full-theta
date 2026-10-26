class_name WeaponSystem
extends RefCounted
## Mount slew and firing (T032). Each tick, per mount in row order: cooldown and heat
## fall, the barrel slews toward the aim point at MountDef.traverse_rate (scaled by the
## mount subsystem's effectiveness) without leaving the arc (FT-WPN-009, FT-SIM-011),
## and a requested shot fires or is blocked (FT-SIM-012). Shots are projectiles moved
## and swept by CollisionSystem in the same tick.

## Beams (FT-SIM-013) hit the first ship along the barrel at once, fill the mount with
## heat and lock it when it overheats (P6); missiles and torpedoes launch as projectiles
## that GuidanceSystem steers (FT-WPN-008). A mount may switch ammunition type
## (FT-WPN-006): weapon_of() is the type selected. Events added: &"mount_overheated" and
## &"mount_cooled" (mount index as value, on the shooter).

## Cooldown below this counts as done (s); absorbs float drift of repeated - DT.
const COOLDOWN_EPS: float = 1e-9


static func step(world: SimWorld) -> void:
	var mounts: MountTable = world.mounts
	var kin: Kinematics = world.kin
	var dt: float = SimWorld.DT
	var ship_ids: PackedInt32Array = mounts.ship_ids
	var mount_index: PackedInt32Array = mounts.mount_index
	var alive: PackedByteArray = kin.alive
	var fire_requested: PackedByteArray = mounts.fire_requested
	var cooldown: PackedFloat64Array = mounts.cooldown
	var heat: PackedFloat64Array = mounts.heat
	var barrel: PackedVector3Array = mounts.barrel
	var aim_set: PackedByteArray = mounts.aim_set
	var defs: Array[ShipDef] = world.defs
	for row: int in ship_ids.size():
		var ship: int = ship_ids[row]
		if alive[ship] != 1:
			fire_requested[row] = 0
			continue
		var def: MountDef = defs[ship].mounts[mount_index[row]]
		var weapon: WeaponDef = def.weapon
		if mounts.ammo_type[row] != 0:
			weapon = def.alt_weapons[mounts.ammo_type[row] - 1]
		cooldown[row] = maxf(0.0, cooldown[row] - dt)
		heat[row] *= exp(-weapon.heat_dissipation * dt)
		if mounts.locked[row] == 1 and heat[row] <= weapon.heat_limit * weapon.overheat_release:
			mounts.locked[row] = 0
			world.emit(&"mount_cooled", ship, -1, mount_index[row])
		var eff: float = DamageSystem.effectiveness(world, ship, def.subsystem_id)
		# aim_direction(), inlined.
		var aim: Vector3 = def.forward
		if aim_set[row] != 0:
			var to_aim: Vector3 = kin.relative_to_point(
				ship, mounts.aim_x[row], mounts.aim_y[row], mounts.aim_z[row]
			)
			var local: Vector3 = kin.rot[ship].inverse() * to_aim - def.position
			aim = barrel[row] if local.length_squared() < 1e-12 else local.normalized()
		var target: Vector3 = clamp_to_arc(def, aim)
		barrel[row] = turn_toward(
			barrel[row], target, def.traverse_rate * clampf(eff, 0.0, 1.0) * dt
		)
		if fire_requested[row] == 1:
			fire_requested[row] = 0
			_try_fire(world, row, def, eff, aim)
			mounts.guide_target[row] = -1


## The weapon of the mount row's selected ammunition type (read-only).
static func weapon_of(world: SimWorld, row: int) -> WeaponDef:
	var def: MountDef = mount_def(world, row)
	var t: int = world.mounts.ammo_type[row]
	return def.weapon if t == 0 else def.alt_weapons[t - 1]


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
	var weapon: WeaponDef = weapon_of(world, row)
	var muzzle: Vector3 = kin.to_world(ship_id, def.position)
	var beam: bool = weapon.kind == WeaponDef.Kind.BEAM
	var pv: Vector3 = (
		kin.vel[ship_id] + kin.to_world(ship_id, world.mounts.barrel[row]) * weapon.projectile_speed
	)
	var flight: float = 1.0 if beam else weapon.max_range / weapon.projectile_speed
	# A beam arrives at once: its reach is the barrel direction times the range.
	var beam_reach: Vector3 = kin.to_world(ship_id, world.mounts.barrel[row]) * weapon.max_range
	var faction: int = world.faction_of(ship_id)
	var best: int = -1
	var best_t: float = 2.0
	for j: int in kin.size():
		if j == ship_id or not kin.is_alive(j):
			continue
		if world.relation(faction, world.faction_of(j)) == SimWorld.Relation.HOSTILE:
			continue
		if not KnowledgeSystem.is_detected(world, faction, j):
			continue
		var axis: Vector3 = kin.to_world(j, Vector3(0.0, 0.0, kin.half_length[j]))
		var t: float = Sweep.capsule(
			muzzle - kin.relative(ship_id, j),
			beam_reach if beam else (pv - kin.vel[j]) * flight,
			axis,
			kin.radius[j] + weapon.projectile_radius
		)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = j
	return best


## Why a requested shot can't fire, or &"" if it can (energy is checked last, by
## drawing it). FT-SIM-011 arc, FT-SIM-012 condition, cooldown, ammunition, overheat lock
## (P6), heat. aim
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
	elif mounts.locked[row] == 1:
		reason = &"overheated"
	elif mounts.heat[row] >= weapon_of(world, row).heat_limit:
		reason = &"heat"
	return reason


static func _try_fire(world: SimWorld, row: int, def: MountDef, eff: float, aim: Vector3) -> void:
	var ship: int = world.mounts.ship_ids[row]
	var index: int = world.mounts.mount_index[row]
	var reason: StringName = block_reason(world, row, eff, aim)
	var weapon: WeaponDef = weapon_of(world, row)
	if reason == &"" and not PowerSystem.draw_energy(world, ship, weapon.energy_per_shot):
		reason = &"energy"
	if reason != &"":
		world.emit(&"fire_blocked", ship, -1, index, Vector3.ZERO, reason)
		return
	var friend: int = path_crosses(world, row)
	_fire(world, row, def, weapon)
	if friend >= 0:
		world.emit(&"friendly_fire_warning", ship, friend, index)


## Fires the selected weapon: a beam at once, anything else as a projectile spawned from
## the mount's hull position along the barrel, with the ship's velocity plus the muzzle
## velocity. It is placed where the muzzle was at the start of the tick, so
## CollisionSystem's full-tick sweep starts at the muzzle. Guided ordnance takes the
## target the fire request carried (FireGuidedCommand).
static func _fire(world: SimWorld, row: int, def: MountDef, weapon: WeaponDef) -> void:
	var mounts: MountTable = world.mounts
	var kin: Kinematics = world.kin
	var ship: int = mounts.ship_ids[row]
	if mounts.ammo[row] > 0:
		mounts.ammo[row] -= 1
	mounts.cooldown[row] = weapon.cooldown
	mounts.heat[row] += weapon.heat_per_shot
	var dir: Vector3 = kin.to_world(ship, mounts.barrel[row])
	if weapon.kind == WeaponDef.Kind.BEAM:
		_beam_hit(world, row, def, weapon, dir)
	else:
		var vs: Vector3 = kin.vel[ship]
		var back: Vector3 = kin.to_world(ship, def.position) - vs * SimWorld.DT
		var start: PackedFloat64Array = kin.point_at(ship, back)
		var k: int = world.projectiles.spawn(
			ship,
			world.faction_of(ship),
			start[0],
			start[1],
			start[2],
			vs + dir * weapon.projectile_speed,
			weapon.projectile_radius,
			weapon.damage,
			ceili(weapon.max_range / weapon.projectile_speed * SimWorld.HZ)
		)
		if weapon.damage_type != &"kinetic" or weapon.is_guided():
			world.projectiles.set_payload(
				k,
				weapon.damage_type,
				weapon.turn_rate if weapon.is_guided() else 0.0,
				mounts.guide_target[row],
				weapon.track_floor
			)
	if weapon.overheat_release > 0.0 and mounts.heat[row] >= weapon.heat_limit:
		mounts.locked[row] = 1
		world.emit(&"mount_overheated", ship, -1, mounts.mount_index[row])
	world.emit(&"fired", ship, -1, mounts.mount_index[row], dir, weapon.id)


## A beam shot: the first ship (not the shooter's) the barrel line crosses within
## max_range takes a hit of the weapon's damage at once (FT-SIM-013).
static func _beam_hit(
	world: SimWorld, row: int, def: MountDef, weapon: WeaponDef, dir: Vector3
) -> void:
	var kin: Kinematics = world.kin
	var shooter: int = world.mounts.ship_ids[row]
	var muzzle: Vector3 = kin.to_world(shooter, def.position)
	var reach: Vector3 = dir * weapon.max_range
	var best: int = -1
	var best_t: float = 2.0
	var best_start: Vector3 = Vector3.ZERO
	for j: int in kin.size():
		if j == shooter or not kin.is_alive(j):
			continue
		var start: Vector3 = muzzle - kin.relative(shooter, j)
		var axis: Vector3 = kin.to_world(j, Vector3(0.0, 0.0, kin.half_length[j]))
		var t: float = Sweep.capsule(start, reach, axis, kin.radius[j] + weapon.projectile_radius)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = j
			best_start = start
	if best < 0:
		return
	var hit: SimHit = SimHit.new()
	hit.target_id = best
	hit.source_id = shooter
	hit.kind = &"beam"
	hit.point_local = kin.to_local(best, best_start + reach * best_t)
	hit.from_local = kin.to_local(best, -dir).normalized()
	hit.energy = weapon.damage
	hit.damage_type = weapon.damage_type
	world.hits.append(hit)
