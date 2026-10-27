class_name ScenarioFixture
extends RefCounted
## Worlds for the real scenarios (E07): the server's own RunSetup on m3_run (the
## M3 map, the enemy catalogue, conversations and reputation), one crewed ship at the yard,
## and a small driver that plays one scenario the way the Director does.

static var _defs: DefLibrary = DefLibrary.new()

var world: SimWorld
var scenario: Scenario
var api: ScenarioApi
var encounter: int = -1
var site: int = -1
var _started: bool = false
var _begin: ApiHandle


## A world at tick 0 with the ship waiting at the yard.
static func make(seed_value: int = 1) -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.new()
	var main: ServerMain = ServerMain.new()
	main.seed_value = seed_value
	f.world = main.run_setup(_defs).build()
	f.api = ScenarioApi.new(f.world)
	return f


## Opens `site_key`, puts the ship at its point and begins the scenario's encounter there.
func begin(scenario_id: StringName, site_key: StringName) -> void:
	scenario = ScenarioCatalogue.load_for(PackedStringArray([String(scenario_id)]))[0].fresh()
	site = world.sites.open(world, site_key)
	var p: Vector3 = world.sites.point3(site)
	world.kin.place(0, p.x, p.y, p.z)
	_begin = api.begin_encounter(scenario_id, site, PackedInt32Array([0]), 0)
	world.step()
	encounter = _begin.id()


## One tick, then the scenario's start, step and finish as the Director does.
func tick() -> void:
	world.step()
	world.drain_events()
	var view: EncounterView = api.encounter(encounter)
	if view.result == Scenario.Result.ACTIVE:
		if not _started:
			_started = true
			scenario.start(api, {"site": site, "ships": view.ships})
		scenario.step(api)
		var result: int = scenario.finished(api)
		if result != Scenario.Result.ACTIVE:
			api.end_encounter(encounter, result)


## Ticks until the encounter has ended or `limit` ticks passed; returns its result.
func run_until_end(limit: int) -> int:
	for i: int in limit:
		tick()
		if api.encounter(encounter).result > Scenario.Result.ACTIVE:
			break
	return api.encounter(encounter).result


## Ticks `n` times.
func run(n: int) -> void:
	for i: int in n:
		tick()


## Ships of a faction other than the crewed ship's, by enemy key (a def's id).
func ships_of(def_id: StringName) -> Array[int]:
	var out: Array[int] = []
	for id: int in world.ship_count():
		if world.defs[id].id == def_id:
			out.append(id)
	return out


## Destroys a ship the way the sim would have: not alive, so the next tick takes it out.
func kill(id: int) -> void:
	world.kin.alive[id] = 0


func card_state(card: int) -> int:
	return world.story.state[card]


## Submits a crew command for the ship and steps one tick.
func send(c: SimCommand) -> bool:
	c.ship_id = 0
	world.submit(c)
	tick()
	return c.accepted
