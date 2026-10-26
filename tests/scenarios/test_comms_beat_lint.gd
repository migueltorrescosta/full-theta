extends GdUnitTestSuite
## The scenario lint (FT-MIS-041, FT-DAT-008): a hostile encounter without a Comms beat fails;
## the shipped scenarios pass; a travel leg carries a hazard, and that hazard is destructible
## debris the map puts on a leg for Weapons to shoot as point defence (D234).


func _run() -> RunDef:
	return load("res://content/runs/m3_run.tres") as RunDef


func _scenarios() -> Array[Scenario]:
	return ScenarioCatalogue.load_for(_run().scenarios)


# FT: FT-MIS-041
func test_a_hostile_meta_without_a_beat_fails() -> void:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"x"
	m.duration_s = 10.0
	m.tags = PackedStringArray(["hostile"])
	assert_array(m.errors()).is_not_empty()
	m.comms_beats = PackedStringArray(["taunt"])
	assert_array(m.errors()).is_empty()
	m.tags = PackedStringArray(["travel"])
	m.comms_beats = PackedStringArray()
	assert_array(m.errors()).is_not_empty()
	m.travel_hazard = &"debris"
	assert_array(m.errors()).is_empty()


# FT: FT-MIS-041
func test_every_listed_scenario_is_clean_and_every_hostile_one_has_a_beat() -> void:
	var run: RunDef = _run()
	var found: Array[Scenario] = _scenarios()
	assert_int(found.size()).is_equal(run.scenarios.size())
	for s: Scenario in found:
		var m: ScenarioMeta = s.meta()
		assert_array(m.errors()).is_empty()
		if m.tags.has("hostile"):
			assert_array(Array(m.comms_beats)).is_not_empty()


# FT: FT-MIS-041
# The travel scenario's hazard is the key of a destructible, unarmed debris EnemyDef that
# the map's legs name.
func test_the_travel_hazard_is_map_debris_that_weapons_can_destroy() -> void:
	var run: RunDef = _run()
	var travel: ScenarioMeta = null
	for s: Scenario in _scenarios():
		if s.meta().tags.has("travel"):
			travel = s.meta()
	assert_object(travel).is_not_null()
	var enemies: Dictionary[StringName, EnemyDef] = DefLibrary.new().enemies()
	assert_bool(enemies.has(travel.travel_hazard)).is_true()
	var debris: EnemyDef = enemies[travel.travel_hazard]
	assert_array(debris.ship.mounts).is_empty()
	assert_float(debris.ship.hull_max).is_less(5.0e6)
	var named: int = 0
	for leg: Dictionary in run.map.legs:
		assert_bool(enemies.has(StringName(leg["debris"]))).is_true()
		named += 1 if StringName(leg["debris"]) == travel.travel_hazard else 0
	assert_int(named).is_greater(0)
