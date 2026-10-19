class_name EnemyAi
extends RefCounted
## M1 enemy AI (T035, FT-SIM-027, FT-M1-007): attack, keep range and retreat at low hull.
## Runs each tick right after KnowledgeSystem, for every AI ship in id order, and acts
## only on its faction's knowledge (FT-SIM-028): it picks targets from
## KnowledgeSystem.contacts and fires only on contacts its faction has identified as
## hostile. It reads a detected contact's position and velocity, the same sensor track a
## crew's radar shows. It flies and fights only by submitting the command classes the
## stations use (HelmInputCommand, SelectTargetCommand, AllStopCommand, AimMountCommand,
## FireCommand) with Source.AI, so they apply next tick through the same assist, power
## and weapon rules, and it never writes another table (FT-SIM-029). The AI is
## deterministic, so replays regenerate its commands and the log omits them (FT-ARC-008).
##
## Behaviour, from the EnemyDef numbers in AiTable:
## - HOLD: no hostile or unknown contact detected: all-stop, then nothing.
## - ATTACK / KEEP_RANGE: face the first mount's lead intercept point (selected as a
##   point each tick, so crossing targets stay inside fire_cone; the target ship when
##   there is no solution) and drive the forward speed setpoint toward the
##   middle of [engage_range_min, engage_range_max] (closing beyond it, backing off
##   inside it), on the assist's own approach braking curve; the mode is ATTACK while
##   farther than engage_range_max. Each mount aims at the lead intercept point
##   (shared/lead.gd) and fires when the target is within engage_range_max and the
##   weapon's range, the intercept is within fire_cone of the bow and the mount's arc,
##   and the barrel is on the aim.
## - RETREAT: hull below retreat_hull_fraction: face a point straight away from the
##   threat and run at full throttle; with no threat detected, keep running on the same
##   bearing. Near the site edge the point stays inside it: the ship runs along the edge,
##   or brakes onto the edge when it can't, and never leaves the site grid (FT-SIM-035).
## Mode changes emit &"ai_mode": ship_id the AI ship, other_id its target (or -1),
## value the AiTable.Mode, tag its name in AiTable.MODE_NAMES.

## Barrel-to-aim angle within which a mount fires (rad); 5 m at 1 km.
const AIM_TOLERANCE: float = 0.005
## KEEP_RANGE turns back to ATTACK only this far beyond engage_range_max (m), so a
## target near the edge doesn't flip the mode every tick.
const MODE_HYSTERESIS: float = 100.0
## Distance of the point a retreating ship faces and runs toward (m).
const RETREAT_POINT_DISTANCE: float = 20000.0
## The retreat point is renewed once its bearing is this far off the wanted one (rad)
## and it is no nearer than half RETREAT_POINT_DISTANCE, or once it is farther than
## RETREAT_POINT_TOLERANCE (m) from the wanted point (braking onto it at the edge).
const RETREAT_REAIM: float = 0.1
const RETREAT_POINT_TOLERANCE: float = 10.0
## A retreat point stays this far inside Kinematics.MAX_OFFSET on every axis (m): room
## for the drift while the ship turns along the edge (FT-SIM-035).
const RETREAT_EDGE_MARGIN: float = 2000.0
## Smallest share of "away" along the edge (sine of its angle off straight out, about
## 3 deg) worth running along it; below it the ship brakes onto the edge, so drift of a
## few metres doesn't pick a direction.
const RETREAT_SLIDE_MIN: float = 0.05
## Throttle input differences below this are not worth a new HelmInputCommand.
const INPUT_EPS: float = 1e-4


static func step(world: SimWorld) -> void:
	var ai: AiTable = world.ai
	for id: int in ai.size():
		if ai.is_enabled(id) and world.kin.is_alive(id):
			_think(world, id)


## Nearest live contact at the ship's site that its faction detects and either has
## identified as hostile or not identified yet (unknowns are closed on, never fired at),
## or -1. Ties go to the lower id.
static func pick_target(world: SimWorld, id: int) -> int:
	var kin: Kinematics = world.kin
	var faction: int = world.faction_of(id)
	var best: int = -1
	var best_dist: float = INF
	for c: int in KnowledgeSystem.contacts(world, faction):
		if not kin.is_alive(c) or not kin.same_site(id, c):
			continue
		if _known_not_hostile(world, faction, c):
			continue
		var dist: float = kin.relative(id, c).length()
		if dist < best_dist:
			best_dist = dist
			best = c
	return best


## The mode the ship should be in this tick.
static func choose_mode(world: SimWorld, id: int, target: int) -> AiTable.Mode:
	var ai: AiTable = world.ai
	if DamageSystem.hull_fraction(world, id) < ai.retreat_hull_fraction[id]:
		return AiTable.Mode.RETREAT
	if target < 0:
		return AiTable.Mode.HOLD
	var limit: float = ai.engage_range_max[id]
	if ai.mode[id] == AiTable.Mode.KEEP_RANGE:
		limit += MODE_HYSTERESIS
	var dist: float = world.kin.relative(id, target).length()
	return AiTable.Mode.ATTACK if dist > limit else AiTable.Mode.KEEP_RANGE


static func _think(world: SimWorld, id: int) -> void:
	var target: int = pick_target(world, id)
	var mode: AiTable.Mode = choose_mode(world, id, target)
	var ai: AiTable = world.ai
	if mode != ai.mode[id]:
		ai.mode[id] = mode
		world.emit(&"ai_mode", id, target, mode, Vector3.ZERO, AiTable.MODE_NAMES[mode])
	ai.target[id] = target
	match mode:
		AiTable.Mode.HOLD:
			_hold(world, id)
		AiTable.Mode.RETREAT:
			_retreat(world, id, target)
		_:
			_engage(world, id, target)


static func _known_not_hostile(world: SimWorld, faction: int, contact: int) -> bool:
	return (
		KnowledgeSystem.is_identified(world, faction, contact)
		and world.relation(faction, world.faction_of(contact)) != SimWorld.Relation.HOSTILE
	)


## No target: drop the selection and the inputs, and all-stop if moving.
static func _hold(world: SimWorld, id: int) -> void:
	var helm: HelmTable = world.helm
	if helm.target_kind[id] != HelmTable.Target.NONE:
		_submit(world, id, SelectTargetCommand.new())
	_helm_input_raw(world, id, false, 0.0)
	var kin: Kinematics = world.kin
	var moving: bool = (
		kin.vel[id].length() >= AssistSystem.STOP_SPEED
		or kin.ang_vel[id].length() >= AssistSystem.STOP_RATE
	)
	if moving and helm.all_stop[id] == 0:
		_submit(world, id, AllStopCommand.new())


## ATTACK and KEEP_RANGE: face the lead point, hold the middle of the engage band, shoot.
static func _engage(world: SimWorld, id: int, target: int) -> void:
	_select_face_point(world, id, target)
	var kin: Kinematics = world.kin
	var ai: AiTable = world.ai
	var rel: Vector3 = kin.relative(id, target)
	var dist: float = rel.length()
	var los: Vector3 = rel / dist if dist > 0.0 else kin.forward(id)
	var gap: float = dist - 0.5 * (ai.engage_range_min[id] + ai.engage_range_max[id])
	# Wanted own velocity along the line of sight: the target's plus a closing speed.
	var along: float = closing_speed(world, id, gap) + kin.vel[target].dot(los)
	_helm_input(world, id, true, along * kin.forward(id).dot(los))
	for m: int in world.defs[id].mounts.size():
		_aim_and_fire(world, id, m, target, dist)


## Selects the first mount's lead aim point as Helm's point target, so the bow faces
## where the shots must go; else (no mount, no solution, off the grid) the target ship.
static func _select_face_point(world: SimWorld, id: int, target: int) -> void:
	var kin: Kinematics = world.kin
	var helm: HelmTable = world.helm
	var aim: Vector3 = Vector3.INF
	if not world.defs[id].mounts.is_empty():
		aim = lead_aim(world, id, 0, target, 1)
	var select: SelectTargetCommand = SelectTargetCommand.new()
	if aim.is_finite():
		select.site = kin.site[id]
		select.x = kin.px[id] + aim.x
		select.y = kin.py[id] + aim.y
		select.z = kin.pz[id] + aim.z
	if not (aim.is_finite() and Kinematics.in_bounds(select.x, select.y, select.z)):
		if helm.target_kind[id] == HelmTable.Target.SHIP and helm.target_ship[id] == target:
			return
		select = SelectTargetCommand.new()
		select.target_ship = target
	_submit(world, id, select)


## Closing speed (m/s, negative backs off) for a distance gap (m) to the hold distance,
## on the assist's approach curve (FT-SIM-037 tuning): a braking curve on the retro
## thrust share far out, an exponential settle near, capped.
static func closing_speed(world: SimWorld, id: int, gap: float) -> float:
	var tuning: AssistDef = world.defs[id].assist
	return signf(gap) * AssistSystem.closing_speed(world.kin, id, tuning, absf(gap))


## RETREAT: face a point RETREAT_POINT_DISTANCE away from the threat (on along the
## current retreat point's bearing when no threat is detected; nothing without one) and
## run at full throttle. Near the site edge the point is
## kept inside it (retreat_offset), so the ship runs along the edge, and once the point
## is closer than half that distance the ship brakes onto it on the approach curve and
## stops there: a retreating ship never leaves the site grid (FT-SIM-035).
static func _retreat(world: SimWorld, id: int, threat: int) -> void:
	var kin: Kinematics = world.kin
	var helm: HelmTable = world.helm
	var current: bool = (
		helm.target_kind[id] == HelmTable.Target.POINT and helm.target_site[id] == kin.site[id]
	)
	var to_point: Vector3 = Vector3.ZERO
	if current:
		to_point = kin.relative_to_point(
			id, helm.target_x[id], helm.target_y[id], helm.target_z[id]
		)
	# Unit vector to run along; zero holds the current point (reached, threat lost).
	var away: Vector3 = Vector3.ZERO
	if threat >= 0:
		away = -kin.relative(id, threat).normalized()
	elif not current:
		return
	elif to_point.length() > RETREAT_POINT_TOLERANCE:
		away = to_point.normalized()
	var wanted: Vector3 = retreat_offset(kin, id, away)
	if current:
		current = (
			(
				to_point.length() > 0.5 * RETREAT_POINT_DISTANCE
				and to_point.angle_to(wanted) <= RETREAT_REAIM
			)
			or to_point.distance_to(wanted) <= RETREAT_POINT_TOLERANCE
		)
	if not current:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.site = kin.site[id]
		select.x = kin.px[id] + wanted.x
		select.y = kin.py[id] + wanted.y
		select.z = kin.pz[id] + wanted.z
		_submit(world, id, select)
	var gap: float = wanted.length()
	if gap >= 0.5 * RETREAT_POINT_DISTANCE:
		_helm_input_raw(world, id, true, 1.0)
	else:
		# On the point, stop facing it: an overshoot of a metre would turn the ship around.
		var face: bool = gap > RETREAT_POINT_TOLERANCE
		_helm_input(world, id, face, closing_speed(world, id, gap) if face else 0.0)


## Offset (m, site frame) from the ship to the point a retreat runs toward:
## RETREAT_POINT_DISTANCE along `away` (a unit vector) while that stays within
## MAX_OFFSET - RETREAT_EDGE_MARGIN of the site on every axis. On an axis where it would
## cross, the point stops at that limit and the rest of the distance goes along the
## other axes, in away's direction projected onto them, so a ship at the edge runs
## along it; with no such direction left (away within RETREAT_SLIDE_MIN of straight out
## of a face or a corner) the point is on the limit straight ahead and the ship brakes
## onto it (FT-SIM-035).
static func retreat_offset(kin: Kinematics, id: int, away: Vector3) -> Vector3:
	var limit: float = Kinematics.MAX_OFFSET - RETREAT_EDGE_MARGIN
	var pos: PackedFloat64Array = PackedFloat64Array([kin.px[id], kin.py[id], kin.pz[id]])
	var blocked: Array[bool] = [false, false, false]
	var out: Vector3 = away * RETREAT_POINT_DISTANCE
	# Each pass blocks at least one more axis or ends, so four passes always end.
	for _pass: int in 4:
		var crossed: bool = false
		for a: int in 3:
			if not blocked[a] and absf(pos[a] + out[a]) > limit:
				blocked[a] = true
				crossed = true
		if not crossed:
			break
		var fixed: Vector3 = Vector3.ZERO
		var free: Vector3 = Vector3.ZERO
		for a: int in 3:
			if blocked[a]:
				var end: float = pos[a] + away[a] * RETREAT_POINT_DISTANCE
				fixed[a] = clampf(end, -limit, limit) - pos[a]
			else:
				free[a] = away[a]
		out = fixed
		if free.length() >= RETREAT_SLIDE_MIN:
			var rest2: float = RETREAT_POINT_DISTANCE ** 2 - fixed.length_squared()
			out += free.normalized() * sqrt(maxf(0.0, rest2))
	return out


## Sends the Helm input that faces (or not) and moves the speed setpoint to the wanted
## forward speed (m/s), unless it is already latched. The latched throttle still ramps
## the setpoint this tick, and the new input applies next tick.
static func _helm_input(world: SimWorld, id: int, face: bool, forward_speed: float) -> void:
	var tuning: AssistDef = world.defs[id].assist
	var helm: HelmTable = world.helm
	var ramp: float = tuning.speed_ramp * SimWorld.DT
	var latched: float = helm.input_translation[id].z
	var next_setpoint: float = clampf(
		helm.throttle_setpoint[id] + latched * ramp, tuning.speed_min, tuning.speed_max
	)
	var wanted: float = clampf(forward_speed, tuning.speed_min, tuning.speed_max)
	var throttle: float = clampf((wanted - next_setpoint) / ramp, -1.0, 1.0)
	if absf(throttle) <= AssistSystem.INPUT_DEAD_ZONE:
		throttle = 0.0
	_helm_input_raw(world, id, face, throttle)


static func _helm_input_raw(world: SimWorld, id: int, face: bool, throttle: float) -> void:
	var helm: HelmTable = world.helm
	var same: bool = (
		helm.input_rotation[id] == Vector3.ZERO
		and helm.input_translation[id].x == 0.0
		and helm.input_translation[id].y == 0.0
		and absf(helm.input_translation[id].z - throttle) < INPUT_EPS
		and helm.face_held[id] == (1 if face else 0)
		and helm.approach_held[id] == 0
	)
	if same:
		return
	var c: HelmInputCommand = HelmInputCommand.new()
	c.throttle = throttle
	c.face = face
	_submit(world, id, c)


## The mount's lead intercept point relative to the ship's centre (m, site frame),
## predicted ticks_ahead ticks ahead (the AI uses 1 because its command applies next
## tick), or Vector3.INF when no shot can reach the target. The shot's reach is its
## distance from the muzzle.
static func lead_aim(world: SimWorld, id: int, m: int, target: int, ticks_ahead: int) -> Vector3:
	var kin: Kinematics = world.kin
	var mount: MountDef = world.defs[id].mounts[m]
	var muzzle: Vector3 = kin.to_world(id, mount.position)
	var rel_vel: Vector3 = kin.vel[target] - kin.vel[id]
	var rel: Vector3 = kin.relative(id, target) - muzzle + rel_vel * (ticks_ahead * SimWorld.DT)
	var t: float = Lead.intercept_time(rel, rel_vel, mount.weapon.projectile_speed)
	if t < 0.0:
		return Vector3.INF
	return muzzle + Lead.aim_point(rel, rel_vel, t)


## Aims the mount at the lead intercept point and fires when the shot is good.
static func _aim_and_fire(world: SimWorld, id: int, m: int, target: int, dist: float) -> void:
	var kin: Kinematics = world.kin
	var aim: Vector3 = lead_aim(world, id, m, target, 1)
	if not aim.is_finite():
		return
	# The ship moves two ticks before WeaponSystem reads the point (it applies next tick,
	# and the weapons run after the integrator), so the point moves with it.
	var point: Vector3 = aim + kin.vel[id] * (2.0 * SimWorld.DT)
	var c: AimMountCommand = AimMountCommand.new()
	c.mount_index = m
	c.aim_x = kin.px[id] + point.x
	c.aim_y = kin.py[id] + point.y
	c.aim_z = kin.pz[id] + point.z
	_submit(world, id, c)
	var shot: Vector3 = aim - kin.to_world(id, world.defs[id].mounts[m].position)
	if _shot_good(world, id, m, target, dist, shot, shot.length()):
		var fire: FireCommand = FireCommand.new()
		fire.mount_index = m
		_submit(world, id, fire)


## The fire rule: an identified hostile within engage_range_max and the weapon's
## reach, the intercept inside fire_cone and the mount's arc, the barrel on the aim,
## and the mount ready next tick (no shot pending, cooldown, ammunition, heat,
## subsystem). The cooldown
## falls once more this tick and once next tick before the shot is tried.
static func _shot_good(
	world: SimWorld, id: int, m: int, target: int, dist: float, aim_dir: Vector3, reach: float
) -> bool:
	var kin: Kinematics = world.kin
	var mounts: MountTable = world.mounts
	var row: int = mounts.row_for(id, m)
	var mount: MountDef = world.defs[id].mounts[m]
	var faction: int = world.faction_of(id)
	var local: Vector3 = kin.to_local(id, aim_dir).normalized()
	return (
		row >= 0
		and KnowledgeSystem.is_identified(world, faction, target)
		and world.relation(faction, world.faction_of(target)) == SimWorld.Relation.HOSTILE
		and dist <= world.ai.engage_range_max[id]
		and reach <= mount.weapon.max_range
		and kin.forward(id).angle_to(aim_dir) <= world.ai.fire_cone[id]
		and WeaponSystem.in_arc(mount, local)
		and mounts.barrel[row].angle_to(local) <= AIM_TOLERANCE
		and mounts.fire_requested[row] == 0
		and mounts.cooldown[row] <= 2.0 * SimWorld.DT + WeaponSystem.COOLDOWN_EPS
		and mounts.ammo[row] != 0
		and mounts.heat[row] < mount.weapon.heat_limit
		and DamageSystem.effectiveness(world, id, mount.subsystem_id) > 0.0
	)


static func _submit(world: SimWorld, id: int, command: SimCommand) -> void:
	command.ship_id = id
	command.source = SimCommand.Source.AI
	world.submit(command)
