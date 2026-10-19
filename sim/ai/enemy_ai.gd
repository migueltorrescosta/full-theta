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
## - ATTACK / KEEP_RANGE: face the target and drive the forward speed setpoint toward the
##   middle of [engage_range_min, engage_range_max] (closing beyond it, backing off
##   inside it), on the assist's own approach braking curve; the mode is ATTACK while
##   farther than engage_range_max. Each mount aims at the lead intercept point
##   (shared/lead.gd) and fires when the target is within engage_range_max and the
##   weapon's range, the intercept is within fire_cone of the bow and the mount's arc,
##   and the barrel is on the aim.
## - RETREAT: hull below retreat_hull_fraction: face a point straight away from the
##   threat and run at full throttle; with no threat detected, keep running.
## Mode changes emit &"ai_mode": ship_id the AI ship, other_id its target (or -1),
## value the AiTable.Mode, tag its name in AiTable.MODE_NAMES.

## Barrel-to-aim angle within which a mount fires (rad); 5 m at 1 km.
const AIM_TOLERANCE: float = 0.005
## KEEP_RANGE turns back to ATTACK only this far beyond engage_range_max (m), so a
## target near the edge doesn't flip the mode every tick.
const MODE_HYSTERESIS: float = 100.0
## Distance of the point a retreating ship faces and runs toward (m).
const RETREAT_POINT_DISTANCE: float = 20000.0
## The retreat point is renewed once its bearing is this far off "away" (rad).
const RETREAT_REAIM: float = 0.1
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
			if target >= 0:
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


## ATTACK and KEEP_RANGE: face the target, hold the middle of the engage band, shoot.
static func _engage(world: SimWorld, id: int, target: int) -> void:
	var helm: HelmTable = world.helm
	if helm.target_kind[id] != HelmTable.Target.SHIP or helm.target_ship[id] != target:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.target_ship = target
		_submit(world, id, select)
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


## Closing speed (m/s, negative backs off) for a distance gap (m) to the hold distance,
## on the assist's approach curve (FT-SIM-037 tuning): a braking curve on the retro
## thrust share far out, an exponential settle near, capped.
static func closing_speed(world: SimWorld, id: int, gap: float) -> float:
	var tuning: AssistDef = world.defs[id].assist
	var kin: Kinematics = world.kin
	var brake: float = kin.thrust_limit_pos(id).z / kin.mass[id] * tuning.approach_braking
	var g: float = absf(gap)
	var speed: float = minf(sqrt(2.0 * brake * g), g / tuning.approach_final_time_constant)
	return signf(gap) * minf(speed, tuning.approach_speed_cap)


## RETREAT: face a point straight away from the threat and run at full throttle.
static func _retreat(world: SimWorld, id: int, threat: int) -> void:
	var kin: Kinematics = world.kin
	var helm: HelmTable = world.helm
	var away: Vector3 = -kin.relative(id, threat).normalized()
	var current: bool = (
		helm.target_kind[id] == HelmTable.Target.POINT and helm.target_site[id] == kin.site[id]
	)
	if current:
		var to_point: Vector3 = kin.relative_to_point(
			id, helm.target_x[id], helm.target_y[id], helm.target_z[id]
		)
		current = (
			to_point.length() > 0.5 * RETREAT_POINT_DISTANCE
			and to_point.angle_to(away) <= RETREAT_REAIM
		)
	if not current:
		var limit: float = Kinematics.MAX_OFFSET
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.site = kin.site[id]
		select.x = clampf(kin.px[id] + away.x * RETREAT_POINT_DISTANCE, -limit, limit)
		select.y = clampf(kin.py[id] + away.y * RETREAT_POINT_DISTANCE, -limit, limit)
		select.z = clampf(kin.pz[id] + away.z * RETREAT_POINT_DISTANCE, -limit, limit)
		_submit(world, id, select)
	_helm_input_raw(world, id, true, 1.0)


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


## Aims the mount at the lead intercept point, predicted one tick ahead because the
## command applies next tick, and fires when the shot is good.
static func _aim_and_fire(world: SimWorld, id: int, m: int, target: int, dist: float) -> void:
	var kin: Kinematics = world.kin
	var mount: MountDef = world.defs[id].mounts[m]
	var muzzle: Vector3 = kin.to_world(id, mount.position)
	var rel_vel: Vector3 = kin.vel[target] - kin.vel[id]
	var rel: Vector3 = kin.relative(id, target) - muzzle + rel_vel * SimWorld.DT
	var t: float = Lead.intercept_time(rel, rel_vel, mount.weapon.projectile_speed)
	if t < 0.0:
		return
	var aim: Vector3 = muzzle + Lead.aim_point(rel, rel_vel, t)
	var c: AimMountCommand = AimMountCommand.new()
	c.mount_index = m
	c.aim_x = kin.px[id] + aim.x
	c.aim_y = kin.py[id] + aim.y
	c.aim_z = kin.pz[id] + aim.z
	_submit(world, id, c)
	var reach: float = t * mount.weapon.projectile_speed
	if _shot_good(world, id, m, target, dist, aim - muzzle, reach):
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
