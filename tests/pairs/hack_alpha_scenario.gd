class_name HackAlphaScenario
extends RefCounted
## The Hack alpha play (spec §7.4 Plays, FT-PAIR-022): Science hacks the target's shields
## (S); inside the hack window Helm has brought the mount to bear (H), Engineering has put
## the pips on the weapons bus (E) and Weapons fires (W, P7, P2, P6). The metric is the
## damage dealt inside the hack window: the health the target lost by the window's close.
##
## The corvette (the M1 hull, its cannon drawing 4 MJ a shot so the weapons bus matters)
## sits at the origin facing -Z. The target, a raider with its shields up, floats 3 km
## away 60 degrees to port, outside the 15 degree mount arc. The crews agree to open fire
## at OPEN_TICK, the tick Science's hack lands (a test asserts it does), and the window is
## the target's shields hack, effect.window_s long (8 s, FT-PAIR-023). Every crew acts only
## through commands:
## - Science (S): scans, then hacks the shields along the shortest route, a move a second.
## - Helm (H): faces the target (the bow, and the mount, come onto it).
## - Engineering (E): at OPEN_TICK puts 4 pips on the weapons (nominal is 2): the bus
##   refills twice as fast, so the cannon can fire at its full rate through the window.
## - Weapons (W): from OPEN_TICK until the last shot that lands before the window closes
##   (flight time before the end), fires whenever the mount is ready and on the target.
## A "chain" is a bitmask of the links present: S, H, E, W; one removed is FULL minus a bit.

const SEED: int = 222
const ME: int = 0
const FOE: int = 1
const S: int = 1
const H: int = 2
const E: int = 4
const W: int = 8
const FULL: int = 15
## The target, 3 km out and 60 degrees to port of the bow (m, site frame).
const TARGET_AT: Vector3 = Vector3(-2598.0, 0.0, -1500.0)
## Energy of a cannon shot (J): the default bus (2 pips) cannot sustain the 2 shots/s.
const SHOT_J: float = 4e6
const WEAPON_PIPS: int = 4
## The agreed tick the hack lands and fire opens, and the cannon flight time (ticks).
const OPEN_TICK: int = 723
const FLIGHT_TICKS: int = 2 * SimWorld.HZ + 6
## Scripted Science: seconds to scan (submit after), to read the hack, per route move.
const SCAN_TICKS: int = 6 * SimWorld.HZ
const READ_TICKS: int = 2 * SimWorld.HZ
const MOVE_TICKS: int = SimWorld.HZ
const TICK_LIMIT: int = 60 * SimWorld.HZ
const SHIELDS: StringName = &"shields"


static func harness() -> PairHarness:
	return PairHarness.new(build, no_environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var shooter: ShipDef = TestDefs.corvette().duplicate()
	var mount: MountDef = shooter.mounts[0].duplicate()
	var cannon: WeaponDef = mount.weapon.duplicate()
	cannon.energy_per_shot = SHOT_J
	mount.weapon = cannon
	var mounts: Array[MountDef] = [mount]
	shooter.mounts = mounts
	var w: SimWorld = SimWorld.new(SEED, "hack_alpha")
	w.science_def = ScienceFixture.science()
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(shooter, 1, 0)
	w.spawn_ship(TestDefs.raider(), 2, 0, TARGET_AT)
	return w


static func no_environment(_w: SimWorld) -> void:
	pass


## Seconds the hack's shield window lasts (s).
static func window_s(w: SimWorld) -> float:
	return w.science_def.effect_for(SubsystemDef.Kind.SHIELDS).window_s


## The run ends as the window closes.
static func close_tick(w: SimWorld) -> int:
	return OPEN_TICK + ceili(window_s(w) * SimWorld.HZ)


static func done(w: SimWorld) -> bool:
	return w.tick >= close_tick(w)


## Damage dealt: the health lost by the target's hull and subsystems (J).
static func measure(w: SimWorld) -> Dictionary:
	var def: ShipDef = w.defs[FOE]
	var h: int = w.damage.hull_row(FOE)
	var lost: float = def.hull_max - w.damage.health[h]
	for i: int in def.subsystems.size():
		lost += def.subsystems[i].health_max - w.damage.health[h + 1 + i]
	return {"damage": lost}


## The crew of a chain: a Callable(world) for PairHarness.run.
static func crew(links: int) -> Callable:
	return chain.bind(links)


static func chain(w: SimWorld, links: int) -> void:
	if links & S != 0:
		science(w)
	if links & H != 0:
		helm(w)
	if links & E != 0:
		engineering(w)
	if links & W != 0:
		weapons(w)


static func science(w: SimWorld) -> void:
	var faction: int = w.faction_of(ME)
	var t: ScienceTable = w.science
	if w.tick >= OPEN_TICK or not KnowledgeSystem.is_detected(w, faction, FOE):
		return
	var def: ScienceDef = w.science_def
	if t.kind[ME] == ScienceTable.Session.SCAN:
		if w.tick - t.start_tick[ME] == SCAN_TICKS:
			_submit(w, ScienceFixture.submit_cmd(ScienceFixture.solution(w, ME)))
	elif t.kind[ME] == ScienceTable.Session.HACK:
		var since: int = w.tick - t.start_tick[ME] - READ_TICKS
		if since >= 0 and since % MOVE_TICKS == 0:
			var path: Array[int] = ScienceFixture.route(w, ME)
			path.push_front(HackPuzzle.entry(def))
			var at: int = path.find(t.node[ME])
			if at >= 0 and at + 1 < path.size():
				_submit(w, ScienceFixture.move_cmd(path[at + 1]))
	elif not ScienceKnowledge.revealed(w, faction, FOE, ScienceKnowledge.HACK):
		_submit(w, ScienceFixture.scan_cmd(FOE))
	else:
		_submit(w, ScienceFixture.hack_cmd(SHIELDS, FOE))


static func helm(w: SimWorld) -> void:
	if not KnowledgeSystem.is_detected(w, w.faction_of(ME), FOE):
		return
	if w.helm.target_kind[ME] != HelmTable.Target.SHIP:
		var pick: SelectTargetCommand = SelectTargetCommand.new()
		pick.target_ship = FOE
		_submit(w, pick)
		var input: HelmInputCommand = HelmInputCommand.new()
		input.face = true
		_submit(w, input)


static func engineering(w: SimWorld) -> void:
	if w.tick == OPEN_TICK:
		var pips: SetPipsCommand = SetPipsCommand.new()
		pips.subsystem_kind = SubsystemDef.Kind.WEAPONS
		pips.pips = WEAPON_PIPS
		_submit(w, pips)


static func weapons(w: SimWorld) -> void:
	if w.tick < OPEN_TICK or w.tick >= close_tick(w) - FLIGHT_TICKS:
		return
	if w.mounts.cooldown[w.mounts.row_for(ME, 0)] > 0.0:
		return
	_submit(w, FireCommand.new())


static func _submit(w: SimWorld, c: SimCommand) -> void:
	c.ship_id = ME
	w.submit(c)
