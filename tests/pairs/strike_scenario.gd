class_name StrikeScenario
extends RefCounted
## The Over-horizon strike play (spec §7.4 Plays, FT-PAIR-022): Relay probes a contact
## beyond sensor range (R), Science scans it through the probe and reveals its weak point
## (S, P13, P7), Weapons fires guided missiles at it (W, P8). The metric is the time to
## disable it: the target's engines, its weak point, destroyed.
##
## The corvette (the M1 hull with a missile mount and a 5 km sensor range) sits at the
## origin facing -Z. The target, a raider with a weak point on its engines, flies across
## its bow 7 km out at 20 m/s with its shields down, so the corvette cannot see it without
## the probe and unguided missiles (11.7 s of flight) miss it. Every crew acts only on what
## its own station knows:
## - Relay (R): launches a probe to PROBE_AT at tick 0. Without Relay Helm closes the
##   distance on the briefed position until the sensors detect the target (a rough 100 m/s
##   approach), and Science and Weapons wait for that.
## - Science (S): scans the target as soon as it is detected and submits the exact match
##   after SCAN_TICKS (the scripted average player). Weapons holds fire until the weak
##   point is revealed (the mark on it); without Science it fires at once, with no
##   weak-point share.
## - Weapons (W): fires guided at the target whenever the mount is ready. Without the
##   guided link it fires the same missile straight along the bow (FireCommand).
## - Helm (always): faces the target, as a briefed point until it is detected.
## A "chain" is a bitmask of the links present: R, S, W; one removed is FULL minus a bit.

const SEED: int = 221
const ME: int = 0
const FOE: int = 1
const R: int = 1
const S: int = 2
const W: int = 4
const FULL: int = 7
const TARGET_AT: Vector3 = Vector3(0.0, 0.0, -7000.0)
const TARGET_VEL: Vector3 = Vector3(20.0, 0.0, 0.0)
const PROBE_AT: Vector3 = Vector3(0.0, 0.0, -6000.0)
const SENSOR_RANGE: float = 3000.0
## The weak point takes this share of a hit (dimensionless; subsystem_damage_share is 0.5).
const WEAK_SHARE: float = 0.9
## Seconds a scan takes the scripted Science, from start to submit (s, ticks).
const SCAN_TICKS: int = 6 * SimWorld.HZ
## Helm's approach speed without a probe (m/s).
const CRUISE: float = 100.0
const TICK_LIMIT: int = 120 * SimWorld.HZ
const ENGINES: StringName = &"engines"


static func harness() -> PairHarness:
	return PairHarness.new(build, no_environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var shooter: ShipDef = TestDefs.corvette().duplicate()
	var mount: MountDef = shooter.mounts[0].duplicate()
	mount.weapon = load("res://content/weapons/m2_missile.tres") as WeaponDef
	var mounts: Array[MountDef] = [mount]
	shooter.mounts = mounts
	shooter.sensor_range = SENSOR_RANGE
	var target: ShipDef = TestDefs.raider().duplicate()
	var shields: ShieldDef = target.shields.duplicate()
	shields.regen_rate = 0.0
	target.shields = shields
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in target.subsystems:
		var copy: SubsystemDef = s.duplicate()
		if copy.id == ENGINES:
			copy.weak_point = true
			copy.weak_point_share = WEAK_SHARE
		subs.append(copy)
	target.subsystems = subs
	var w: SimWorld = SimWorld.new(SEED, "strike")
	w.science_def = ScienceFixture.science()
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(shooter, 1, 0)
	w.spawn_ship(target, 2, 0, TARGET_AT, Quaternion.IDENTITY, TARGET_VEL)
	w.shields.strength[FOE] = 0.0
	# Decoupled, nobody holds its velocity, so it coasts across the bow.
	w.helm.decoupled[FOE] = 1
	return w


static func no_environment(_w: SimWorld) -> void:
	pass


static func done(w: SimWorld) -> bool:
	return w.damage.health[w.damage.find_subsystem(FOE, ENGINES)] <= 0.0


static func measure(w: SimWorld) -> Dictionary:
	return {"time": w.tick * SimWorld.DT}


## The crew of a chain: a Callable(world) for PairHarness.run.
static func crew(links: int) -> Callable:
	return chain.bind(links)


static func chain(w: SimWorld, links: int) -> void:
	helm(w, links)
	if links & R != 0:
		relay(w)
	if links & S != 0:
		science(w)
	weapons(w, links)


static func helm(w: SimWorld, links: int) -> void:
	var seen: bool = KnowledgeSystem.is_detected(w, w.faction_of(ME), FOE)
	var selected_ship: bool = (
		w.helm.target_kind[ME] == HelmTable.Target.SHIP and w.helm.target_ship[ME] == FOE
	)
	# Without a probe Helm closes at CRUISE until the target is detected, then stops.
	var throttle: float = 0.0
	if links & R == 0 and w.tick > 0:
		if not seen and w.helm.throttle_setpoint[ME] < CRUISE:
			throttle = 1.0
		elif seen and w.helm.throttle_setpoint[ME] > 0.0:
			throttle = -1.0
	if seen and not selected_ship:
		var pick: SelectTargetCommand = SelectTargetCommand.new()
		pick.target_ship = FOE
		_submit(w, pick)
	elif not seen and w.tick == 0:
		var point: SelectTargetCommand = SelectTargetCommand.new()
		point.site = 0
		point.x = TARGET_AT.x
		point.y = TARGET_AT.y
		point.z = TARGET_AT.z
		_submit(w, point)
	if w.tick == 0 or throttle != w.helm.input_translation[ME].z:
		var input: HelmInputCommand = HelmInputCommand.new()
		input.face = true
		input.throttle = throttle
		_submit(w, input)


static func relay(w: SimWorld) -> void:
	if w.tick == 0:
		var launch: LaunchProbeCommand = LaunchProbeCommand.new()
		launch.x = PROBE_AT.x
		launch.y = PROBE_AT.y
		launch.z = PROBE_AT.z
		_submit(w, launch)


static func science(w: SimWorld) -> void:
	var faction: int = w.faction_of(ME)
	var t: ScienceTable = w.science
	if t.kind[ME] == ScienceTable.Session.SCAN:
		if w.tick - t.start_tick[ME] == SCAN_TICKS:
			var angles: Vector3 = ScienceFixture.solution(w, ME)
			_submit(w, ScienceFixture.submit_cmd(angles))
	elif (
		t.kind[ME] == ScienceTable.Session.NONE
		and KnowledgeSystem.is_detected(w, faction, FOE)
		and not ScienceKnowledge.weak_points_known(w, faction, FOE)
	):
		_submit(w, ScienceFixture.scan_cmd(FOE))


static func weapons(w: SimWorld, links: int) -> void:
	var faction: int = w.faction_of(ME)
	if not GuidanceSystem.is_tracked(w, faction, FOE):
		return
	if links & S != 0 and not ScienceKnowledge.weak_points_known(w, faction, FOE):
		return
	if w.mounts.cooldown[w.mounts.row_for(ME, 0)] > 0.0:
		return
	if links & W != 0:
		var guided: FireGuidedCommand = FireGuidedCommand.new()
		guided.target = FOE
		_submit(w, guided)
	else:
		_submit(w, FireCommand.new())


static func _submit(w: SimWorld, c: SimCommand) -> void:
	c.ship_id = ME
	w.submit(c)
