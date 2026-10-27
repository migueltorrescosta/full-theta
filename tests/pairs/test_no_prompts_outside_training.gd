extends GdUnitTestSuite
## Cooperation prompts exist only in the Shakedown (FT-PAIR-012): outside a training run the
## game never says a "talk to X" line and the Next command that drives the training is
## refused. The pair lines live in the Shakedown's dialogue file, said by its driver alone.

const TICKS: int = 6000


func _catalogue() -> Array[Scenario]:
	return [
		TestScenario.make(&"s_a", 2, true), TestScenario.make(&"s_b", 2), ShakedownScenario.new()
	]


# FT: FT-PAIR-012
func test_a_directed_run_says_no_shakedown_line() -> void:
	var def: RunDef = ApiFixture.run_def(PackedStringArray(["s_a", "s_b"]), 1.0, 1.0)
	var w: SimWorld = ApiFixture.world(1, def)
	var d: Director = Director.new(def.director, &"normal", _catalogue(), 3)
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in TICKS:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	assert_array(d.decisions()).is_not_empty()
	for e: SimEvent in w.events:
		assert_bool(e.kind == &"say" and String(e.tag).begins_with("shakedown.")).is_false()
	# The director skipped the training scenario: it never began an encounter of it.
	for id: int in w.encounters.size():
		assert_str(String(host.api().encounter(id).scenario_id)).is_not_equal("shakedown")


# FT: FT-PAIR-012
func test_next_is_refused_outside_a_training_run() -> void:
	var w: SimWorld = ApiFixture.world()
	var cmd: TrainingNextCommand = TrainingNextCommand.new()
	cmd.ship_id = 0
	cmd.station = &"helm"
	w.submit(cmd)
	w.step()
	assert_bool(cmd.accepted).is_false()
	assert_int(w.story_flags.get_flag(&"train.helm.next")).is_equal(0)
	# The M1 encounter has no run at all.
	var m1: SimWorld = (
		M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()
	)
	var other: TrainingNextCommand = TrainingNextCommand.new()
	other.station = &"helm"
	m1.submit(other)
	m1.step()
	assert_bool(other.accepted).is_false()


# FT: FT-PAIR-012
func test_the_director_runs_never_list_the_shakedown() -> void:
	var defs: DefLibrary = DefLibrary.new()
	for run: StringName in [&"m3_run"]:
		assert_bool(defs.run(run).training).is_false()
		assert_bool(defs.run(run).scenarios.has("shakedown")).is_false()
	assert_bool(defs.run(&"shakedown").training).is_true()


# FT: FT-PAIR-012
func test_pair_prompts_are_only_shakedown_lines() -> void:
	# A cooperation prompt names two stations; every such line is in shakedown.json, and no
	# other dialogue file has a line under the shakedown. prefix or says "pair" steps.
	var lines: DialogueLines = DialogueLines.load_dir()
	var pair_lines: Array = lines.lines.keys().filter(
		func(id: String) -> bool: return id.begins_with("shakedown.pair_")
	)
	assert_int(pair_lines.size()).is_equal(15)
	for id: String in lines.lines:
		if id.begins_with("shakedown."):
			continue
		var line: Dictionary = lines.line(id)
		assert_bool(String(id).contains("pair")).override_failure_message(id).is_false()
		assert_str(str(line["text"]["en"]).to_lower()).override_failure_message(id).not_contains(
			"press next"
		)
