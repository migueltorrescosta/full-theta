extends GdUnitTestSuite
## R16 (FT-SIM-035, D98, D104): the M1 intercept, with the scripted crew firing, behaves
## the same far from the world origin. Positions are site-local, so a site whose origin
## is 10^8 m away changes nothing; within a site, 64-bit offsets keep slow motion near
## the 200 km limit.

const TICKS: int = 600


func _encounter(origin: PackedFloat64Array) -> M1Encounter:
	return M1Encounter.new(21, "test", TestDefs.corvette(), TestDefs.raider_enemy(), origin)


## Runs the crew script for TICKS ticks; returns the number of shots fired.
func _fight(world: SimWorld) -> int:
	var crew: ScriptedCrew = ScriptedCrew.new()
	var fired: int = 0
	for i: int in TICKS:
		crew.act(world)
		world.step()
		for e: SimEvent in world.drain_events():
			if e.kind == &"fired":
				fired += 1
	return fired


# FT: FT-SIM-035, FT-M1-020
# The same scripted intercept (600 ticks, shots fired) at a site whose origin is 10^8 m
# from the world origin and at a site at the origin ends in the same state hash.
func test_intercept_far_from_world_origin_matches() -> void:
	var near: SimWorld = _encounter(PackedFloat64Array([0.0, 0.0, 0.0])).build()
	var far: SimWorld = _encounter(PackedFloat64Array([1e8, 0.0, 0.0])).build()
	assert_array(Array(far.site_origins[M1Encounter.SITE])).is_equal([1e8, 0.0, 0.0])
	var fired: int = _fight(near)
	_fight(far)
	assert_int(fired).is_greater(5)
	assert_str(far.state_hash()).is_equal(near.state_hash())


# FT: FT-SIM-035, FT-M1-020
# The same intercept moved to +199 km on X within the site, the corvette coasting
# decoupled at 0.2 m/s (float32 offsets freeze under 0.47 m/s there, D104): after 600
# ticks the corvette has moved 2 m, and both ships' positions relative to the start
# and to each other match the run at the origin within 1 mm (they differ only by the
# 64-bit rounding of the offsets, about 3e-11 m at 199 km).
func test_slow_drift_near_offset_limit() -> void:
	var worlds: Array[SimWorld] = []
	for shift: float in [0.0, 199000.0]:
		var w: SimWorld = _encounter(PackedFloat64Array([0.0, 0.0, 0.0])).build()
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
