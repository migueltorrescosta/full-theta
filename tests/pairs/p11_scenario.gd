class_name P11Scenario
extends RefCounted
## P11 Engineering + Relay pair scenario (spec §7.4, FT-PAIR-015, FT-ENG-008): a hazard
## front (a radiation wave) travels straight at the M1 corvette, at rest at the origin,
## along -Z from FRONT_START m out at FRONT_SPEED, and the tick it reaches the ship
## it hits the sensors and shields for HIT_J each. The sim has no hazard physics; the
## environment plays the front (the same in both variants) and the damage goes through
## DamageSystem.damage_subsystem, so pre-hardening applies (FT-ENG-008).
## - Engineering (both variants): once a subsystem is damaged, sends one repair crew to
##   each damaged one.
## - Relay (co-op only): launches a probe at tick 0 to PROBE_AT; when the front's leading
##   edge is inside the probe's bubble (ProbeSystem.coverage_at) at two sightings one
##   second apart, Relay has its speed and forecasts the arrival; Engineering then
##   pre-hardens both subsystems once the forecast is within HARDEN_LEAD s, so the
##   30 s hardening covers the hit.
## - Solo: no probe, no forecast; Engineering reacts to the impact (FT-PAIR-004).
## Metrics: damage taken (J of subsystem health lost) and repair time (s from the hit)
## until both subsystems are whole again.

const SEED: int = 111
const PLAYER: int = 0
## The front's leading edge starts this far out on -Z (m) and travels at this speed (m/s).
const FRONT_START: float = 12000.0
const FRONT_SPEED: float = 200.0
## Energy the front deals to each of its two subsystems (J).
const HIT_J: float = 8e6
const SUBSYSTEMS: Array[StringName] = [&"sensors", &"shields"]
## Where Relay sends the probe: on the front's path, 6 km out (m, site frame).
const PROBE_AT: Vector3 = Vector3(0.0, 0.0, -6000.0)
## Engineering hardens once the forecast arrival is within this many seconds.
const HARDEN_LEAD: float = 15.0
const TICK_LIMIT: int = 240 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, front, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p11")
	w.spawn_ship(TestDefs.corvette(), 1, 0)
	return w


## The tick the front reaches the ship.
static func hit_tick() -> int:
	return roundi(FRONT_START / FRONT_SPEED * SimWorld.HZ)


## The front's leading edge at a tick (m, site frame).
static func edge_at(tick: int) -> Vector3:
	return Vector3(0.0, 0.0, -(FRONT_START - FRONT_SPEED * tick * SimWorld.DT))


## The environment: the front hits both subsystems on its arrival tick.
static func front(w: SimWorld) -> void:
	if w.tick != hit_tick():
		return
	for id: StringName in SUBSYSTEMS:
		DamageSystem.damage_subsystem(w, PLAYER, _index(w, id), HIT_J)


static func done(w: SimWorld) -> bool:
	return w.tick > hit_tick() and _lost(w) == 0.0


static func measure(w: SimWorld) -> Dictionary:
	# Damage is the deepest each subsystem fell: the lowest health fraction its
	# &"subsystem_damaged" events reported (value = fraction after the hit).
	var lowest: Dictionary[StringName, float] = {}
	for e: SimEvent in w.drain_events():
		if e.kind == &"subsystem_damaged":
			lowest[e.tag] = minf(lowest.get(e.tag, 1.0), e.value)
	var damage: float = 0.0
	for id: StringName in lowest:
		damage += (1.0 - lowest[id]) * w.defs[PLAYER].subsystems[_index(w, id)].health_max
	return {"damage": damage, "repair_time": (w.tick - hit_tick()) * SimWorld.DT}


static func solo(w: SimWorld) -> void:
	engineering(w)


static func coop(w: SimWorld) -> void:
	relay(w)
	engineering(w)


## Relay: probe out at tick 0; Engineering hardens once the forecast is within the lead.
## The forecast needs the front's edge covered now and one
## second ago.
static func relay(w: SimWorld) -> void:
	if w.tick == 0:
		var launch: LaunchProbeCommand = LaunchProbeCommand.new()
		launch.x = PROBE_AT.x
		launch.y = PROBE_AT.y
		launch.z = PROBE_AT.z
		_submit(w, launch)
	var eta: float = forecast(w)
	if eta <= HARDEN_LEAD:
		for id: StringName in SUBSYSTEMS:
			var harden: HardenCommand = HardenCommand.new()
			harden.subsystem_id = id
			_submit(w, harden)


## The forecast arrival of the front at the ship (s), INF until the probe's bubble held
## the front's edge at two sightings one second apart, and after the hit.
static func forecast(w: SimWorld) -> float:
	var earlier: int = w.tick - SimWorld.HZ
	if earlier < 0 or w.tick >= hit_tick():
		return INF
	var faction: int = w.faction_of(PLAYER)
	if not (
		ProbeSystem.coverage_at(w, faction, edge_at(w.tick))
		and ProbeSystem.coverage_at(w, faction, edge_at(earlier))
	):
		return INF
	var speed: float = (edge_at(w.tick) - edge_at(earlier)).length() / 1.0
	return -edge_at(w.tick).z / speed


## Engineering: one crew to each damaged subsystem that has none.
static func engineering(w: SimWorld) -> void:
	for crew: int in SUBSYSTEMS.size():
		var id: StringName = SUBSYSTEMS[crew]
		var row: int = w.damage.find_subsystem(PLAYER, id)
		var damaged: bool = w.damage.health[row] < w.defs[PLAYER].subsystems[_index(w, id)].health_max
		if damaged and w.damage.crews[row] == 0:
			var dispatch: DispatchRepairCommand = DispatchRepairCommand.new()
			dispatch.crew = crew
			dispatch.subsystem_id = id
			_submit(w, dispatch)


static func _lost(w: SimWorld) -> float:
	var lost: float = 0.0
	for id: StringName in SUBSYSTEMS:
		var row: int = w.damage.find_subsystem(PLAYER, id)
		lost += w.defs[PLAYER].subsystems[_index(w, id)].health_max - w.damage.health[row]
	return lost


static func _index(w: SimWorld, id: StringName) -> int:
	return w.damage.find_subsystem(PLAYER, id) - w.damage.hull_row(PLAYER) - 1


static func _submit(w: SimWorld, c: SimCommand) -> void:
	c.ship_id = PLAYER
	w.submit(c)
