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
##   bearing. Sites wrap (FT-SIM-035, D124), so there is no edge: the ship runs straight
##   on across the seams until hostiles no longer detect it (D120).
## Mode changes emit &"ai_mode": ship_id the AI ship, other_id its target (or -1),
## value the AiTable.Mode, tag its name in AiTable.MODE_NAMES.

## Barrel-to-aim angle within which a mount fires (rad); 5 m at 1 km.
const AIM_TOLERANCE: float = 0.005
## KEEP_RANGE turns back to ATTACK only this far beyond engage_range_max (m), so a
## target near the edge doesn't flip the mode every tick.
const MODE_HYSTERESIS: float = 100.0
## Distance of the point a retreating ship faces and runs toward (m), at most a quarter
## of the site period: a point at or beyond P/2 would be the minimum image on the
## threat's side (FT-SIM-035).
const RETREAT_POINT_DISTANCE: float = 20000.0
## The retreat point is renewed once its bearing is this far off the wanted one (rad)
## or it is nearer than half that distance; a point within
## RETREAT_POINT_TOLERANCE (m) counts as reached.
const RETREAT_REAIM: float = 0.1
const RETREAT_POINT_TOLERANCE: float = 10.0
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
		if not kin.is_alive(c) or kin.site[id] != kin.site[c]:
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
## where the shots must go; else (no mount, no solution) the target ship.
static func _select_face_point(world: SimWorld, id: int, target: int) -> void:
	var kin: Kinematics = world.kin
	var helm: HelmTable = world.helm
	var aim: Vector3 = Vector3.INF
	if not world.defs[id].mounts.is_empty():
		aim = lead_aim(world, id, 0, target, 1)
	var select: SelectTargetCommand = SelectTargetCommand.new()
	if aim.is_finite():
		_set_point(select, kin, id, aim)
	elif helm.target_kind[id] == HelmTable.Target.SHIP and helm.target_ship[id] == target:
		return
	else:
		select.target_ship = target
	_submit(world, id, select)


## Closing speed (m/s, negative backs off) for a distance gap (m) to the hold distance,
## on the assist's approach curve (FT-SIM-037 tuning): a braking curve on the retro
## thrust share far out, an exponential settle near, capped.
static func closing_speed(world: SimWorld, id: int, gap: float) -> float:
	var tuning: AssistDef = world.defs[id].assist
	return signf(gap) * AssistSystem.closing_speed(world.kin, id, tuning, absf(gap))


## RETREAT: face a point RETREAT_POINT_DISTANCE straight away from the threat (on along
## the current retreat point's bearing when no threat is detected; nothing without one)
## and run at full throttle. Sites wrap, so the ship crosses the seams and keeps going
## (FT-SIM-035, D124) until hostiles lose it (D120).
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
	if away == Vector3.ZERO:
		_helm_input(world, id, false, 0.0)
		return
	var reach: float = minf(RETREAT_POINT_DISTANCE, 0.25 * kin.period)
	var wanted: Vector3 = away * reach
	var keep: bool = (
		current and to_point.length() > 0.5 * reach and to_point.angle_to(wanted) <= RETREAT_REAIM
	)
	if not keep:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		_set_point(select, kin, id, wanted)
		_submit(world, id, select)
	_helm_input_raw(world, id, true, 1.0)


## Points a selection at the site-local point `offset` (m, site frame) from the ship,
## wrapped onto the site's cube (FT-SIM-035).
static func _set_point(
	select: SelectTargetCommand, kin: Kinematics, id: int, offset: Vector3
) -> void:
	var p: PackedFloat64Array = kin.point_at(id, offset)
	select.site = kin.site[id]
	select.x = p[0]
	select.y = p[1]
	select.z = p[2]


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
	var p: PackedFloat64Array = kin.point_at(id, point)
	c.aim_x = p[0]
	c.aim_y = p[1]
	c.aim_z = p[2]
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
