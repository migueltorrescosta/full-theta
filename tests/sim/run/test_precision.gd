extends GdUnitTestSuite
## R16 (FT-SIM-035, D98, D104): the M1 intercept, with the scripted crew firing, behaves
## the same far from the world origin. Positions are site-local (a site id plus an
## offset), so the site a fight happens at changes nothing; within a site, 64-bit
## offsets keep slow motion near the 200 km limit.

const TICKS: int = 600
## Stands for a site whose origin is 10^8 m from the world origin.
const FAR_SITE: int = 7
## Columns that hold a site id, the only state allowed to differ between sites.
const SITE_COLUMNS: Array[String] = ["site", "target_site"]


func _encounter() -> M1Encounter:
	return M1Encounter.new(21, "test", TestDefs.corvette(), TestDefs.raider_enemy())


## Runs the crew script for TICKS ticks; returns every event as text, in order.
func _fight(world: SimWorld) -> PackedStringArray:
	var crew: ScriptedCrew = ScriptedCrew.new()
	var events: PackedStringArray = PackedStringArray()
	for i: int in TICKS:
		crew.act(world)
		world.step()
		for e: SimEvent in world.drain_events():
			events.append(str(e))
	return events


## Every column of every table except the site columns, as [table, name, value] rows.
func _non_site_columns(world: SimWorld) -> Array:
	var out: Array = []
	for t: SimTable in world.tables():
		for column: Array in t.columns():
			if not SITE_COLUMNS.has(column[0]):
				out.append([t.get_script().get_global_name(), column[0], column[1]])
	return out


# FT: FT-SIM-035, FT-M1-020
# The same scripted intercept (600 ticks, shots fired) at site 0 and at FAR_SITE, which
# stands for a site 10^8 m from the world origin. The sim stores no site origins, only
# site ids and 64-bit site-local offsets (D98, D104), so nothing but the site columns
# may differ: every other column and the event stream must be identical. This does not
# place anything at 10^8 m; it checks that no state depends on where a site is.
func test_intercept_far_from_world_origin_matches() -> void:
	var near: SimWorld = _encounter().build()
	var far: SimWorld = _encounter().build()
	for id: int in far.ship_count():
		far.kin.place(id, FAR_SITE, far.kin.px[id], far.kin.py[id], far.kin.pz[id])
	var near_events: PackedStringArray = _fight(near)
	var far_events: PackedStringArray = _fight(far)
	var fired: int = (
		Array(near_events).filter(func(e: String) -> bool: return " fired " in e).size()
	)
	assert_int(fired).is_greater(5)
	assert_array(Array(far.kin.site)).is_equal([FAR_SITE, FAR_SITE])
	assert_array(Array(far.projectiles.site)).is_not_empty()
	assert_bool(Array(far.projectiles.site).all(func(s: int) -> bool: return s == FAR_SITE))
	assert_array(Array(far_events)).is_equal(Array(near_events))
	assert_array(_non_site_columns(far)).is_equal(_non_site_columns(near))


# FT: FT-SIM-035, FT-M1-020
# The same intercept moved to +199 km on X within the site, the corvette coasting
# decoupled at 0.2 m/s (float32 offsets freeze under 0.47 m/s there, D104): after 600
# ticks the corvette has moved 2 m, and both ships' positions relative to the start
# and to each other match the run at the origin within 1 mm (they differ only by the
# 64-bit rounding of the offsets, about 3e-11 m at 199 km).
func test_slow_drift_near_offset_limit() -> void:
	var worlds: Array[SimWorld] = []
	for shift: float in [0.0, 199000.0]:
		var w: SimWorld = _encounter().build()
		for id: int in w.ship_count():
			w.kin.place(id, M1Encounter.SITE, w.kin.px[id] + shift, w.kin.py[id], w.kin.pz[id])
		var coast: DecoupledCommand = DecoupledCommand.new()
		coast.ship_id = M1Encounter.PLAYER_SHIP
		w.submit(coast)
		w.kin.vel[M1Encounter.PLAYER_SHIP] = Vector3(0.2, 0.0, 0.0)
		_fight(w)
		worlds.append(w)
	var at_origin: SimWorld = worlds[0]
	var far: SimWorld = worlds[1]
	var player: int = M1Encounter.PLAYER_SHIP
	assert_float(far.kin.px[player] - 199000.0).is_equal_approx(2.0, 1e-3)
	assert_float(far.kin.px[player] - 199000.0).is_equal_approx(at_origin.kin.px[player], 1e-3)
	for id: int in far.ship_count():
		var moved: Vector3 = Vector3(
			far.kin.px[id] - 199000.0 - at_origin.kin.px[id],
			far.kin.py[id] - at_origin.kin.py[id],
			far.kin.pz[id] - at_origin.kin.pz[id]
		)
		assert_float(moved.length()).is_less(1e-3)
	var rel_far: Vector3 = far.kin.relative(player, M1Encounter.ENEMY_SHIP)
	var rel_origin: Vector3 = at_origin.kin.relative(player, M1Encounter.ENEMY_SHIP)
	assert_float(rel_far.distance_to(rel_origin)).is_less(1e-3)
