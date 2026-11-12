extends GdUnitTestSuite
## The shared sim helpers of the DRY review (G1, G2, G8, R04): tick conversion, ship and
## relation predicates, sensor reach, minimum-image delta, the faction table.


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(7, "test")
	w.spawn_ship(TestDefs.corvette(), 1, CubePoint.make(0, 0, 0))
	w.spawn_ship(TestDefs.corvette(), 2, CubePoint.make(500, 0, 0))
	return w


func test_ticks_round_up() -> void:
	assert_int(SimRate.ticks(1.0)).is_equal(SimRate.HZ)
	assert_int(SimRate.ticks(0.001)).is_equal(1)
	assert_int(SimRate.ticks(0.0)).is_equal(0)
	assert_int(SimRate.ticks(2.5)).is_equal(ceili(2.5 * SimRate.HZ))


func test_has_ship_bounds() -> void:
	var w: SimWorld = _world()
	assert_bool(w.has_ship(-1)).is_false()
	assert_bool(w.has_ship(0)).is_true()
	assert_bool(w.has_ship(1)).is_true()
	assert_bool(w.has_ship(2)).is_false()


func test_hostility_predicates() -> void:
	var w: SimWorld = _world()
	assert_bool(w.is_hostile(1, 2)).is_true()
	assert_bool(w.is_hostile(1, 1)).is_false()
	w.set_relation(1, 2, SimWorld.Relation.NEUTRAL)
	assert_bool(w.is_hostile(2, 1)).is_false()


func test_crew_predicates() -> void:
	var w: SimWorld = _world()
	assert_bool(w.is_crew_in_play(0)).is_true()
	w.ships.status[0] = ShipStateTable.Status.DESTROYED
	assert_bool(w.is_crew(0)).is_true()
	assert_bool(w.is_crew_in_play(0)).is_false()


func test_sensor_reach_zero_for_dead_ship() -> void:
	var w: SimWorld = _world()
	var full: float = w.defs[0].sensor_range
	assert_float(KnowledgeSystem.sensor_reach(w, 0)).is_equal(full)
	w.kin.alive[0] = 0
	assert_float(KnowledgeSystem.sensor_reach(w, 0)).is_equal(0.0)


func test_delta_is_minimum_image() -> void:
	var w: SimWorld = _world()
	var p: float = w.kin.period
	var d: Vector3 = w.kin.delta(
		CubePoint.make(0.9 * p / 2.0, 0.0, 0.0), CubePoint.make(-0.9 * p / 2.0, 0.0, 0.0)
	)
	assert_float(d.x).is_equal_approx(-0.2 * p / 2.0, 1e-6)


func test_faction_table_keeps_crew_factions_clear_of_npcs() -> void:
	for f: int in GameRules.CREW_FACTIONS:
		assert_bool(Factions.NPC.has(f)).is_false()


func test_clock_slot_wraps_to_the_bow() -> void:
	assert_int(Scenario.clock_slot(0)).is_equal(1)
	assert_int(Scenario.clock_slot(11)).is_equal(12)
	assert_int(Scenario.clock_slot(12)).is_equal(1)
