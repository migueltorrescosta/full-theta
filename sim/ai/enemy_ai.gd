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
	var kin: Kinematics = world.kin
	# Target candidates per faction: knowledge, liveness and relations don't change
	# while the AI thinks (it only submits commands), so once per faction and tick.
	var candidates: Dictionary[int, PackedInt32Array] = {}
	for id: int in ai.size():
		if ai.enabled[id] == 1 and kin.alive[id] == 1:
			var faction: int = kin.factions[id]
			if not candidates.has(faction):
				candidates[faction] = _candidates(world, faction)
			_think(world, id, candidates[faction])


## Target candidates: the live contacts the faction detects and either has identified as
## hostile or not identified yet (unknowns are closed on, never fired at), at any site,
## in id order. Each AI ship targets the nearest of them at its own site
## (Kinematics.nearest: ties go to the lower id).
static func _candidates(world: SimWorld, faction: int) -> PackedInt32Array:
	var kin: Kinematics = world.kin
	var knowledge: KnowledgeTable = world.knowledge
	var alive: PackedByteArray = kin.alive
	var factions: PackedInt32Array = kin.factions
	var contact_ids: PackedInt32Array = knowledge.ship_ids
	var identified: PackedByteArray = knowledge.identified
	var out: PackedInt32Array = PackedInt32Array()
	# Skips the contacts known not to be hostile: identified, and not hostile by
	# relation (looked up once per faction).
	var hostile: Dictionary[int, bool] = {}
	for r: int in knowledge.detected_rows(faction, factions):
		var c: int = contact_ids[r]
		if alive[c] != 1:
			continue
		if identified[r] == 1:
			var f: int = factions[c]
			if not hostile.has(f):
				hostile[f] = world.relation(faction, f) == SimWorld.Relation.HOSTILE
			if not hostile[f]:
				continue
		out.append(c)
	return out


## The mode the ship should be in this tick, for its target (or -1) at offset rel (m).
static func _choose_mode(world: SimWorld, id: int, target: int, rel: Vector3) -> AiTable.Mode:
	var ai: AiTable = world.ai
	if DamageSystem.hull_fraction(world, id) < ai.retreat_hull_fraction[id]:
		return AiTable.Mode.RETREAT
	if target < 0:
		return AiTable.Mode.HOLD
	var limit: float = ai.engage_range_max[id]
	if ai.mode[id] == AiTable.Mode.KEEP_RANGE:
		limit += MODE_HYSTERESIS
	var dist: float = rel.length()
	return AiTable.Mode.ATTACK if dist > limit else AiTable.Mode.KEEP_RANGE


static func _think(world: SimWorld, id: int, candidates: PackedInt32Array) -> void:
	var target: int = world.kin.nearest(id, candidates)
	# The target's offset once per tick (the AI changes no positions while it thinks).
	var rel: Vector3 = world.kin.relative(id, target) if target >= 0 else Vector3.ZERO
	var mode: AiTable.Mode = _choose_mode(world, id, target, rel)
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
			_engage(world, id, target, rel)


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
## rel is the target's offset (m, kin.relative). Each mount's muzzle and lead point are
## computed once per tick, the first mount's shared by the face point and its aim.
static func _engage(world: SimWorld, id: int, target: int, rel: Vector3) -> void:
	var kin: Kinematics = world.kin
	var ai: AiTable = world.ai
	var def: ShipDef = world.defs[id]
	var mounts: Array[MountDef] = def.mounts
	var q: Quaternion = kin.rot[id]
	var own_vel: Vector3 = kin.vel[id]
	var target_vel: Vector3 = kin.vel[target]
	var rel_vel: Vector3 = target_vel - own_vel
	# Each mount's muzzle (site frame, from the centre) and lead point one tick ahead
	# (lead_aim), Vector3.INF without a solution.
	var muzzles: PackedVector3Array = PackedVector3Array()
	var aims: PackedVector3Array = PackedVector3Array()
	for mount: MountDef in mounts:
		var muzzle: Vector3 = q * mount.position
		muzzles.append(muzzle)
		aims.append(_lead_point(muzzle, rel, rel_vel, 1, mount.weapon.projectile_speed))
	_select_face_point(world, id, target, Vector3.INF if mounts.is_empty() else aims[0])
	var dist: float = rel.length()
	var forward: Vector3 = q * Vector3.FORWARD
	var los: Vector3 = rel / dist if dist > 0.0 else forward
	var gap: float = dist - 0.5 * (ai.engage_range_min[id] + ai.engage_range_max[id])
	# Wanted own velocity along the line of sight: the target's plus a closing speed.
	# The closing speed is on the assist's approach curve (FT-SIM-037 tuning), negative
	# to back off inside the hold distance.
	var closing: float = signf(gap) * AssistSystem.closing_speed(kin, id, def.assist, absf(gap))
	var along: float = closing + target_vel.dot(los)
	_helm_input(world, id, true, along * forward.dot(los))
	for m: int in mounts.size():
		var aim: Vector3 = aims[m]
		if not aim.is_finite():
			continue
		# The ship moves two ticks before WeaponSystem reads the point (it applies next
		# tick, and the weapons run after the integrator), so the point moves with it.
		var c: AimMountCommand = AimMountCommand.new()
		c.mount_index = m
		var p: PackedFloat64Array = kin.point_at(id, aim + own_vel * (2.0 * SimWorld.DT))
		c.aim_x = p[0]
		c.aim_y = p[1]
		c.aim_z = p[2]
		_submit(world, id, c)
		var shot: Vector3 = aim - muzzles[m]
		if _shot_good(world, id, m, target, dist, shot, shot.length()):
			var fire: FireCommand = FireCommand.new()
			fire.mount_index = m
			_submit(world, id, fire)


## Selects the first mount's lead aim point (aim, Vector3.INF for none) as Helm's point
## target, so the bow faces where the shots must go; else (no mount, no solution) the
## target ship.
static func _select_face_point(world: SimWorld, id: int, target: int, aim: Vector3) -> void:
	var kin: Kinematics = world.kin
	var helm: HelmTable = world.helm
	var select: SelectTargetCommand = SelectTargetCommand.new()
	if aim.is_finite():
		_set_point(select, kin, id, aim)
	elif helm.target_kind[id] == HelmTable.Target.SHIP and helm.target_ship[id] == target:
		return
	else:
		select.target_ship = target
	_submit(world, id, select)


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


## Sends a HelmInputCommand with that throttle and face, unless it is already latched.
static func _helm_input_raw(world: SimWorld, id: int, face: bool, throttle: float) -> void:
	var helm: HelmTable = world.helm
	var latched: Vector3 = helm.input_translation[id]
	var same: bool = (
		helm.input_rotation[id] == Vector3.ZERO
		and latched.x == 0.0
		and latched.y == 0.0
		and absf(latched.z - throttle) < INPUT_EPS
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
	return _lead_point(
		kin.to_world(id, mount.position),
		kin.relative(id, target),
		kin.vel[target] - kin.vel[id],
		ticks_ahead,
		mount.weapon.projectile_speed
	)


## lead_aim from the muzzle and the target's offset rel and velocity rel_vel relative to
## the ship (site frame) and the shot's muzzle speed.
static func _lead_point(
	muzzle: Vector3, rel: Vector3, rel_vel: Vector3, ticks_ahead: int, speed: float
) -> Vector3:
	var r: Vector3 = rel - muzzle + rel_vel * (ticks_ahead * SimWorld.DT)
	var t: float = Lead.intercept_time(r, rel_vel, speed)
	if t < 0.0:
		return Vector3.INF
	return muzzle + Lead.aim_point(r, rel_vel, t)


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
	# Cheapest checks first; every one is pure, so the order doesn't change the result.
	# Each rejects unless its condition holds (not (x <= y)), so a NaN never fires.
	if (
		row < 0
		or mounts.fire_requested[row] != 0
		or not (mounts.cooldown[row] <= 2.0 * SimWorld.DT + WeaponSystem.COOLDOWN_EPS)
		or mounts.ammo[row] == 0
		or not (mounts.heat[row] < mount.weapon.heat_limit)
		or not (dist <= world.ai.engage_range_max[id])
		or not (reach <= mount.weapon.max_range)
	):
		return false
	var faction: int = world.faction_of(id)
	var local: Vector3 = kin.to_local(id, aim_dir).normalized()
	return (
		KnowledgeSystem.is_identified(world, faction, target)
		and world.relation(faction, world.faction_of(target)) == SimWorld.Relation.HOSTILE
		and kin.forward(id).angle_to(aim_dir) <= world.ai.fire_cone[id]
		and WeaponSystem.in_arc(mount, local)
		and mounts.barrel[row].angle_to(local) <= AIM_TOLERANCE
		and DamageSystem.effectiveness(world, id, mount.subsystem_id) > 0.0
	)


static func _submit(world: SimWorld, id: int, command: SimCommand) -> void:
	command.ship_id = id
	command.source = SimCommand.Source.AI
	world.submit(command)
