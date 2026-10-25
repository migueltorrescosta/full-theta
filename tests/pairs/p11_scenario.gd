class_name P11Scenario
extends RefCounted
## P11 Engineering + Relay pair scenario (spec §7.4, FT-PAIR-015, FT-ENG-008): a hazard
## front (a radiation wave, the sim hazard content/hazards/p11_radiation_wave.tres, D208)
## travels straight at the M1 corvette, at rest at the origin, from 12 km out at 200 m/s,
## and the tick it reaches the ship it hits the sensors and shields for 8 MJ each (through
## DamageSystem.damage_subsystem, so pre-hardening applies, FT-ENG-008). It is the same in
## both variants.
## - Engineering (both variants): once a subsystem is damaged, sends one repair crew to
##   each damaged one.
## - Relay (co-op only): launches a probe at tick 0 to PROBE_AT; once the front's surface is
##   inside the probe's bubble (HazardSystem.known_to) the faction has the forecast
##   arrival (HazardSystem.eta, what Engineering's countdown shows); Engineering then
##   pre-hardens both subsystems once the forecast is within HARDEN_LEAD s, so the
##   30 s hardening covers the hit.
## - Solo: no probe, no forecast; Engineering reacts to the impact (FT-PAIR-004).
## Metrics: damage taken (J of subsystem health lost) and repair time (s from the hit)
## until both subsystems are whole again.

const SEED: int = 111
const PLAYER: int = 0
const SUBSYSTEMS: Array[StringName] = [&"sensors", &"shields"]
## Where Relay sends the probe: on the front's path, 6 km out (m, site frame).
const PROBE_AT: Vector3 = Vector3(0.0, 0.0, -6000.0)
## Engineering hardens once the forecast arrival is within this many seconds.
const HARDEN_LEAD: float = 15.0
const TICK_LIMIT: int = 240 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, PairHarness.no_environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p11")
	w.spawn_ship(TestDefs.corvette(), 1, 0)
	w.hazards = [load("res://content/hazards/p11_radiation_wave.tres") as HazardDef]
	return w


## The tick the front hit the ship, or -1 before.
static func hit_tick(w: SimWorld) -> int:
	for e: SimEvent in w.events:
		if e.kind == &"hazard_hit":
			return e.tick
	return -1


static func done(w: SimWorld) -> bool:
	return hit_tick(w) >= 0 and _lost(w) == 0.0


static func measure(w: SimWorld) -> Dictionary:
	# Damage is the deepest each subsystem fell: the lowest health fraction its
	# &"subsystem_damaged" events reported (value = fraction after the hit).
	var lowest: Dictionary[StringName, float] = {}
	var hit: int = hit_tick(w)
	for e: SimEvent in w.drain_events():
		if e.kind == &"subsystem_damaged":
			lowest[e.tag] = minf(lowest.get(e.tag, 1.0), e.value)
	var damage: float = 0.0
	for id: StringName in lowest:
		damage += (1.0 - lowest[id]) * w.defs[PLAYER].subsystems[_index(w, id)].health_max
	return {"damage": damage, "repair_time": (w.tick - hit) * SimWorld.DT}


static func solo(w: SimWorld) -> void:
	engineering(w)


static func coop(w: SimWorld) -> void:
	relay(w)
	engineering(w)


## Relay: probe out at tick 0; Engineering hardens once the forecast is within the lead.
static func relay(w: SimWorld) -> void:
	if w.tick == 0:
		var launch: LaunchProbeCommand = LaunchProbeCommand.new()
		launch.x = PROBE_AT.x
		launch.y = PROBE_AT.y
		launch.z = PROBE_AT.z
		PairHarness.send(w, launch)
	var eta: float = forecast(w)
	if eta <= HARDEN_LEAD:
		for id: StringName in SUBSYSTEMS:
			var harden: HardenCommand = HardenCommand.new()
			harden.subsystem_id = id
			PairHarness.send(w, harden)


## The forecast arrival of the front at the ship (s), INF until the faction knows of the
## front (a probe's bubble holds its surface) and after the hit.
static func forecast(w: SimWorld) -> float:
	if not HazardSystem.known_to(w, w.faction_of(PLAYER), 0):
		return INF
	var eta: float = HazardSystem.eta(w, PLAYER, 0)
	return eta if eta >= 0.0 else INF


## Engineering: one crew to each damaged subsystem that has none.
static func engineering(w: SimWorld) -> void:
	for crew: int in SUBSYSTEMS.size():
		var id: StringName = SUBSYSTEMS[crew]
		var row: int = w.damage.find_subsystem(PLAYER, id)
		var damaged: bool = (
			w.damage.health[row] < w.defs[PLAYER].subsystems[_index(w, id)].health_max
		)
		if damaged and w.damage.crews[row] == 0:
			var dispatch: DispatchRepairCommand = DispatchRepairCommand.new()
			dispatch.crew = crew
			dispatch.subsystem_id = id
			PairHarness.send(w, dispatch)


static func _lost(w: SimWorld) -> float:
	var lost: float = 0.0
	for id: StringName in SUBSYSTEMS:
		var row: int = w.damage.find_subsystem(PLAYER, id)
		lost += w.defs[PLAYER].subsystems[_index(w, id)].health_max - w.damage.health[row]
	return lost


static func _index(w: SimWorld, id: StringName) -> int:
	return w.damage.find_subsystem(PLAYER, id) - w.damage.hull_row(PLAYER) - 1
