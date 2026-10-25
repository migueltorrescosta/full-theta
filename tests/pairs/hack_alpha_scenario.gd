class_name HackAlphaScenario
extends RefCounted
## The Hack alpha play (spec §7.4, FT-PAIR-022): S->H+E+W, pairs P7, P2 and P6. A gunship
## (the M1 corvette with eight mass drivers on the bow) faces a raider at rest 1.8 km
## away, 70 degrees to port, behind a deep shield (SHIELD_J, which absorbs a large share
## of every shot while its power is up) and a hull (HULL_J) that outlasts the window.
## The crew's plan:
## - Science scans the raider and hacks its shields (ScienceScript, the average
##   player's timing): the hack drops the shields for the data-defined window (8 s).
## - Helm selects the raider and holds Face, bringing the mounts to bear (P2).
## - Engineering puts the reactor's 2 spare pips on the weapons ENGINEER_LEAD_S before
##   the window opens (P6); the weapons run hot only for that long, under the fault
##   threshold.
## - Weapons holds fire until the window's planned start (WINDOW_START, the callout
##   "shields down"; the plan, not the hack, sets it, so a chain without Science fires on
##   the same tick), then fires every mount that is ready with the raider in arc
##   (Gunnery.gun).
## A chain with a link removed leaves that station's script out (crew()). Metric: damage (J,
## energy that got through the shields) the raider takes in the window, the fixed span
## of ticks [WINDOW_START, WINDOW_START + WINDOW_TICKS) in which the full chain's hack
## is open; the run ends with it. The chain's hack_done tick is a second metric, to check
## it opens where WINDOW_START says (-1 without Science).

enum Link { SCIENCE, HELM, ENGINEERING, WEAPONS }

const SEED: int = 53
const PLAYER: int = 0
const RAIDER: int = 1
const MOUNTS: int = 8
## 70 degrees to port of the bow, 1.8 km.
const RAIDER_AT: Vector3 = Vector3(-1691.4, 0.0, -615.6)
const SHIELD_J: float = 1.0e9
const HULL_J: float = 1.0e10
## The tick the full chain's hack window opens (the hack_done event), set by
## ScienceScript's timing and the world seed.
const WINDOW_START: int = 682
const WINDOW_TICKS: int = 8 * SimWorld.HZ
## Engineering powers the weapons this long before the window (s).
const ENGINEER_LEAD_S: float = 2.0
const SCAN_AT: int = 2
const WPN: int = SubsystemDef.Kind.WEAPONS


static func harness() -> PairHarness:
	return PairHarness.new(build, no_environment, done, measure, WINDOW_START + WINDOW_TICKS)


## The raider as a copy with a deep shield and a hull that outlasts the window.
static func target_def() -> ShipDef:
	var def: ShipDef = Gunnery.raider_with_shields(SHIELD_J)
	def.hull_max = HULL_J
	return def


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "hack_alpha")
	w.science_def = ScienceFixture.science()
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(Gunnery.gunship(MOUNTS), 1, 0)
	w.spawn_ship(target_def(), 2, 0, RAIDER_AT)
	return w


static func no_environment(_w: SimWorld) -> void:
	pass


static func done(w: SimWorld) -> bool:
	return w.tick >= WINDOW_START + WINDOW_TICKS


static func measure(w: SimWorld) -> Dictionary:
	var damage: float = 0.0
	var opened: float = -1.0
	for e: SimEvent in w.drain_events():
		if e.kind == &"hit" and e.ship_id == RAIDER:
			if e.tick >= WINDOW_START and e.tick < WINDOW_START + WINDOW_TICKS:
				damage += e.value
		elif e.kind == &"hack_done" and opened < 0.0:
			opened = e.tick
	return {"damage": damage, "hack_done_tick": opened}


## The crew without one link (a Link; -1 keeps all), a fresh one per run.
static func crew(removed: int = -1) -> Callable:
	var science: ScienceScript = ScienceScript.new(PLAYER, RAIDER, SCAN_AT, &"shields")
	return func(w: SimWorld) -> void:
		if removed != Link.SCIENCE:
			science.act(w)
		if removed != Link.HELM:
			helm(w)
		if removed != Link.ENGINEERING:
			engineering(w)
		if removed != Link.WEAPONS and w.tick >= WINDOW_START:
			Gunnery.gun(w, PLAYER, Gunnery.site_point(w, RAIDER, Vector3.ZERO))


## Helm: select the raider (a contact after the first tick's sweep) and hold Face.
static func helm(w: SimWorld) -> void:
	if w.tick == 1:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.ship_id = PLAYER
		select.target_ship = RAIDER
		w.submit(select)
		var input: HelmInputCommand = HelmInputCommand.new()
		input.ship_id = PLAYER
		input.face = true
		w.submit(input)


## Engineering: the spare pips to the weapons shortly before the window.
static func engineering(w: SimWorld) -> void:
	if w.tick == WINDOW_START - roundi(ENGINEER_LEAD_S * SimWorld.HZ):
		var c: SetPipsCommand = SetPipsCommand.new()
		c.ship_id = PLAYER
		c.subsystem_kind = WPN
		c.pips = w.defs[PLAYER].power.max_pips_per_subsystem
		w.submit(c)
