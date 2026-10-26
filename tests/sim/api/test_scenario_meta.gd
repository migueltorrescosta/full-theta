extends GdUnitTestSuite
## ScenarioMeta declarations and the Scenario base (E07, FT-DAT-006, FT-DAT-008, FT-MIS-041).


func _valid() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"raid"
	m.tags = PackedStringArray(["hostile"])
	m.threat_cost = 3
	m.duration_s = 240.0
	m.stations = PackedStringArray(["helm", "weapons", "comms"])
	m.pairs = PackedStringArray(["p5"])
	m.branches = [{"id": "win", "outcome": "raiders destroyed"}]
	m.comms_beats = PackedStringArray(["hail", "taunt"])
	return m


# FT: FT-DAT-008
func test_a_complete_declaration_has_no_errors() -> void:
	assert_array(_valid().errors()).is_empty()


# FT: FT-DAT-008
func test_each_wrong_field_is_reported() -> void:
	var cases: Dictionary = {
		"id is empty": func(m: ScenarioMeta) -> void: m.id = &"",
		"unknown tag":
		func(m: ScenarioMeta) -> void: m.tags = PackedStringArray(["hostile", "wat"]),
		"threat_cost": func(m: ScenarioMeta) -> void: m.threat_cost = -1,
		"duration_s": func(m: ScenarioMeta) -> void: m.duration_s = 0.0,
		"unknown station":
		func(m: ScenarioMeta) -> void: m.stations = PackedStringArray(["bridge"]),
		"not pN": func(m: ScenarioMeta) -> void: m.pairs = PackedStringArray(["q5"]),
		"needs an id and an outcome": func(m: ScenarioMeta) -> void: m.branches = [{"id": "win"}],
		"unknown comms beat":
		func(m: ScenarioMeta) -> void: m.comms_beats = PackedStringArray(["wave"]),
		"training and the training tag": func(m: ScenarioMeta) -> void: m.training = true,
	}
	for needle: String in cases:
		var m: ScenarioMeta = _valid()
		(cases[needle] as Callable).call(m)
		var errors: Array[String] = m.errors()
		var found: Array[String] = errors.filter(func(e: String) -> bool: return e.contains(needle))
		(
			assert_bool(not found.is_empty())
			. override_failure_message("%s not reported in %s" % [needle, errors])
			. is_true()
		)


# FT: FT-MIS-041, FT-DAT-008
func test_a_hostile_scenario_needs_a_comms_beat() -> void:
	var m: ScenarioMeta = _valid()
	m.comms_beats = PackedStringArray()
	assert_array(m.errors()).has_size(1)
	assert_str(m.errors()[0]).contains("Comms beat")
	m.tags = PackedStringArray(["rescue"])
	assert_array(m.errors()).is_empty()


# FT: FT-MIS-041, FT-DAT-008
func test_a_travel_scenario_names_its_hazard() -> void:
	var m: ScenarioMeta = _valid()
	m.tags = PackedStringArray(["travel"])
	assert_array(m.errors()).has_size(1)
	m.travel_hazard = &"debris_belt"
	assert_array(m.errors()).is_empty()


# FT: FT-DAT-008
func test_a_training_scenario_costs_no_threat() -> void:
	var m: ScenarioMeta = _valid()
	m.tags = PackedStringArray(["training"])
	m.training = true
	m.comms_beats = PackedStringArray()
	assert_bool(m.errors().any(func(e: String) -> bool: return e.contains("no threat"))).is_true()
	m.threat_cost = 0
	assert_array(m.errors()).is_empty()


# FT: FT-DAT-006
func test_scenario_results_match_the_encounter_table() -> void:
	for name: String in EncounterTable.Result.keys():
		assert_int(Scenario.Result[name]).is_equal(EncounterTable.Result[name])
	assert_int(Scenario.Result.keys().size()).is_equal(EncounterTable.Result.keys().size())


# FT: FT-DAT-006
func test_the_base_scenario_is_inert() -> void:
	var s: Scenario = Scenario.new()
	var api: ScenarioApi = ScenarioApi.new(ApiFixture.world())
	s.start(api, {})
	s.step(api)
	assert_int(s.finished(api)).is_equal(Scenario.Result.ACTIVE)
	assert_object(s.meta()).is_null()
