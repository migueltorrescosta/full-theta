extends GdUnitTestSuite
## The director writes nothing itself (E07, FT-SIM-029, FT-MIS-005, FT-MIS-008, FT-TST-012):
## before_tick with a world but no step() leaves the state alone, every command it queues
## is a SERVER kind on the allow-list, no definition changes, and it holds no world.

const ALLOWED: Array[StringName] = [
	&"spawn_ship",
	&"open_site",
	&"post_card",
	&"say",
	&"set_flag",
	&"begin_encounter",
	&"end_encounter",
	&"set_relation",
	&"set_contract_flag"
]


func _ready_world() -> SimWorld:
	var w: SimWorld = ApiFixture.world(2)
	ApiFixture.step(w, 70)
	return w


func _director() -> Director:
	var catalogue: Array[Scenario] = [
		TestScenario.make(&"s_a", 2, true), TestScenario.make(&"s_b", 3)
	]
	return Director.new(ApiFixture.run_def().director, &"normal", catalogue, 5)


# FT: FT-SIM-029, FT-MIS-005, FT-TST-012
func test_before_tick_changes_no_state_and_queues_only_allowed_server_commands() -> void:
	var defs: Dictionary[String, Resource] = TestDefs.all_defs()
	var def_hashes: Dictionary[String, String] = TestDefs.hashes(defs)
	var w: SimWorld = _ready_world()
	var hash_before: String = ApiFixture.tables_hash(w)
	var d: Director = _director()
	d.before_tick(ScenarioApi.new(w))
	assert_str(ApiFixture.tables_hash(w)).is_equal(hash_before)
	var queued: Array[SimCommand] = w.queued_commands()
	assert_int(queued.size()).is_greater_equal(2)
	for c: SimCommand in queued:
		assert_int(c.source).is_equal(SimCommand.Source.SERVER)
		(
			assert_bool(ALLOWED.has(c.kind()))
			. override_failure_message("%s not allowed" % c.kind())
			. is_true()
		)
	# Over a whole run the director only ever queues allowed kinds, and defs stay as loaded.
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in 900:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	for c: SimCommand in w.command_log:
		if c.source == SimCommand.Source.SERVER:
			assert_bool(ALLOWED.has(c.kind()) or c.kind() == &"reset_ship").is_true()
	assert_dict(TestDefs.hashes(defs)).is_equal(def_hashes)


# FT: FT-SIM-029, FT-TST-012
func test_the_director_holds_no_world_or_table() -> void:
	var d: Director = _director()
	d.before_tick(ScenarioApi.new(_ready_world()))
	var stack: Array = [d]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var v: Variant = stack.pop_back()
		if v is Object:
			var o: Object = v
			if seen.has(o.get_instance_id()):
				continue
			seen[o.get_instance_id()] = true
			assert_bool(o is SimWorld or o is SimTable).is_false()
			if o is ScenarioApi:
				continue  # the API's own world is its business; the director only calls it
			for p: Dictionary in o.get_property_list():
				if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
					stack.append(o.get(p["name"]))
		elif v is Array:
			stack.append_array(v)
		elif v is Dictionary:
			stack.append_array(v.keys())
			stack.append_array(v.values())


# FT: FT-MIS-006
func test_every_decision_is_logged_with_a_reason() -> void:
	var w: SimWorld = _ready_world()
	var d: Director = _director()
	d.before_tick(ScenarioApi.new(w))
	assert_int(d.decisions().size()).is_greater_equal(1)
	for dec: DirectorDecision in d.decisions():
		assert_str(dec.reason_key).starts_with("director.reason.")
		var dict: Dictionary = dec.to_dict()
		for key: String in [
			"tick",
			"ship",
			"kind",
			"scenario_id",
			"site",
			"cost",
			"budget_before",
			"budget_after",
			"reason_key",
			"reason_args"
		]:
			assert_bool(dict.has(key)).is_true()
