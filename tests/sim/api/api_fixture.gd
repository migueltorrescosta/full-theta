class_name ApiFixture
extends RefCounted
## Worlds for the Scenario API, director and run tests (E07): a RunSetup world holding crewed
## ships at the yard, a raider in the catalogue, and three sites registered in the SiteTable
## stub (tests/stubs, until strand B's table lands): "yard" (home, site 0), "alpha" 30 km
## along +X and "beta" 60 km along +Y, 3 km radius each.

const RAIDER: StringName = &"raider"
const FACTION_ENEMY: int = 2
const ALPHA: Vector3 = Vector3(30000.0, 0.0, 0.0)
const BETA: Vector3 = Vector3(0.0, 60000.0, 0.0)


## A RunDef built in code: a director with the given timeout and gap, a flee cost, the
## corvette, and the scenario ids.
static func run_def(
	scenario_ids: PackedStringArray = PackedStringArray(["s_a", "s_b"]),
	timeout_s: float = 10.0,
	gap_s: float = 1.0
) -> RunDef:
	var d: DirectorDef = DirectorDef.new()
	d.id = &"test_director"
	d.budget_per_ship = {&"easy": 6, &"normal": 9, &"hard": 12}
	d.gap_s = gap_s
	d.arrival_timeout_s = timeout_s
	d.spawn_site_every_s = 0.0
	var f: FleeCostDef = FleeCostDef.new()
	f.id = &"test_flee"
	f.credits = 150
	f.rep_dist = &"flee"
	var r: RunDef = RunDef.new()
	r.id = &"test_run"
	r.encounters = 2
	r.scenarios = scenario_ids
	r.director = d
	r.flee_cost = f
	r.player_ship = TestDefs.corvette()
	r.start_credits = 100
	return r


static func world(crew: int = 1, def: RunDef = null) -> SimWorld:
	var run: RunDef = def if def != null else run_def()
	var catalog: Dictionary[StringName, EnemyDef] = {RAIDER: TestDefs.raider_enemy()}
	var setup: RunSetup = RunSetup.new(7, "test", run, catalog, crew)
	var w: SimWorld = setup.build()
	w.sites.register(&"yard", Vector3.ZERO, 2000.0, &"station")
	w.sites.register(&"alpha", ALPHA, 3000.0, &"nav")
	w.sites.register(&"beta", BETA, 3000.0, &"field")
	w.sites.open(w, &"yard")
	w.sites.open(w, &"alpha")
	return w


## Steps the world n ticks.
static func step(w: SimWorld, n: int = 1) -> void:
	for i: int in n:
		w.step()


## SHA-256 over the state tables, tick, RNG and relations but not the pending queue
## (what state_hash() adds), to show a write changes nothing before the next step.
static func tables_hash(w: SimWorld) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([w.tick, w.rng.states(), w.get("_relations")]))
	for t: SimTable in w.tables():
		for column: Array in t.columns():
			ctx.update(var_to_bytes(column))
	return ctx.finish().hex_encode()


## Moves a ship to a point (m) in the cube.
static func place(w: SimWorld, ship: int, p: Vector3) -> void:
	w.kin.place(ship, p.x, p.y, p.z)
