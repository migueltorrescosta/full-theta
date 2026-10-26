extends GdUnitTestSuite
## The director's threat budget (E07, FT-MIS-028, FT-MIS-029, FT-MIS-008, D81, D92): one
## budget per crewed ship, sized by the difficulty preset and kept by a custom toggle set;
## encounters are paced by the quiet gap (D231).

const TICKS: int = 4000


func _catalogue() -> Array[Scenario]:
	return [
		TestScenario.make(&"s_a", 4), TestScenario.make(&"s_b", 3), TestScenario.make(&"s_c", 5)
	]


func _def() -> RunDef:
	return ApiFixture.run_def(PackedStringArray(["s_a", "s_b", "s_c"]), 1.0, 1.0)


func _run(difficulty: StringName, crew: int = 1, per_run: int = 9) -> Array:
	var w: SimWorld = ApiFixture.world(crew, _def())
	var d: Director = Director.new(w.run_def.director, difficulty, _catalogue(), 3)
	d.encounters_per_run = per_run
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in TICKS:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	return [w, d]


func _picks(d: Director, ship: int) -> Array[DirectorDecision]:
	var out: Array[DirectorDecision] = []
	for dec: DirectorDecision in d.decisions():
		if dec.ship == ship and dec.kind == DirectorDecision.Kind.PICK_ENCOUNTER:
			out.append(dec)
	return out


# FT: FT-MIS-028, FT-MIS-029
func test_the_budget_follows_the_preset_and_a_custom_set_keeps_it() -> void:
	var def: DirectorDef = _def().director
	var catalogue: Array[Scenario] = _catalogue()
	assert_int(Director.new(def, &"easy", catalogue, 1).budget_left(0)).is_equal(6)
	assert_int(Director.new(def, &"normal", catalogue, 1).budget_left(0)).is_equal(9)
	assert_int(Director.new(def, &"hard", catalogue, 1).budget_left(0)).is_equal(12)
	# "Normal (custom)": the toggles code "normal:1011000" keeps Normal's budget (D92).
	assert_int(Director.new(def, &"normal:1011000", catalogue, 1).budget_left(0)).is_equal(9)
	assert_int(Director.new(def, &"Hard:0101", catalogue, 1).budget_left(0)).is_equal(12)
	assert_str(String(Director.preset_of("easy:101"))).is_equal("easy")


# FT: FT-MIS-029, FT-MIS-008
func test_spending_never_passes_the_budget_and_a_bigger_budget_buys_more() -> void:
	var results: Dictionary[StringName, int] = {}
	for preset: StringName in [&"easy", &"hard"]:
		var out: Array = _run(preset)
		var d: Director = out[1]
		var spent: int = 0
		var left: int = _def().director.budget_per_ship[preset]
		for dec: DirectorDecision in _picks(d, 0):
			assert_int(dec.budget_before).is_equal(left)
			assert_int(dec.budget_after).is_equal(left - dec.cost)
			assert_int(dec.budget_after).is_greater_equal(0)
			left = dec.budget_after
			spent += dec.cost
		assert_int(d.budget_left(0)).is_equal(left)
		assert_int(spent).is_less_equal(_def().director.budget_per_ship[preset])
		results[preset] = spent
	assert_int(results[&"hard"]).is_greater(results[&"easy"])


# FT: FT-MIS-029
func test_a_spent_budget_logs_one_skip() -> void:
	var out: Array = _run(&"easy")
	var d: Director = out[1]
	var skips: Array[DirectorDecision] = d.decisions().filter(
		func(x: DirectorDecision) -> bool: return x.kind == DirectorDecision.Kind.SKIP
	)
	assert_int(skips.size()).is_equal(1)
	assert_str(skips[0].reason_key).is_equal("director.reason.no_fit")


# FT: FT-MIS-029, FT-MIS-028
func test_each_ship_has_its_own_budget() -> void:
	var out: Array = _run(&"normal", 2)
	var d: Director = out[1]
	for ship: int in 2:
		var picks: Array[DirectorDecision] = _picks(d, ship)
		assert_int(picks.size()).is_greater_equal(1)
		assert_int(picks[0].budget_before).is_equal(9)
		var cost: int = 0
		for p: DirectorDecision in picks:
			cost += p.cost
		assert_int(d.budget_left(ship)).is_equal(9 - cost)


# FT: FT-MIS-008
func test_the_same_seed_picks_the_same_runs() -> void:
	var a: Array[Dictionary] = []
	var b: Array[Dictionary] = []
	for dec: DirectorDecision in (_run(&"normal")[1] as Director).decisions():
		a.append(dec.to_dict())
	for dec: DirectorDecision in (_run(&"normal")[1] as Director).decisions():
		b.append(dec.to_dict())
	assert_array(a).is_equal(b)


# FT: FT-MIS-025, FT-MIS-027
func test_the_next_encounter_waits_a_quiet_gap_and_opens_a_site() -> void:
	var out: Array = _run(&"hard", 1, 3)
	var w: SimWorld = out[0]
	var d: Director = out[1]
	var gap_ticks: int = ceili(_def().director.gap_s * SimWorld.HZ)
	assert_int(w.encounters.size()).is_greater_equal(2)
	for id: int in range(1, w.encounters.size()):
		assert_int(w.encounters.open_tick[id] - w.encounters.end_tick[id - 1]).is_greater_equal(
			gap_ticks
		)
	for id: int in w.encounters.size():
		assert_bool(w.encounters.site[id] != 0).override_failure_message("home site used").is_true()
	# Beta was closed at the start, so a second encounter at once needs it opened (logged).
	var opens: Array[DirectorDecision] = d.decisions().filter(
		func(x: DirectorDecision) -> bool: return x.kind == DirectorDecision.Kind.OPEN_SITE
	)
	assert_bool(not opens.is_empty() or w.sites.size() == 2).is_true()
	# The run ends after its encounters: logged once.
	var ends: Array[DirectorDecision] = d.decisions().filter(
		func(x: DirectorDecision) -> bool: return x.kind == DirectorDecision.Kind.END_RUN
	)
	assert_int(ends.size()).is_equal(1)
	assert_int(w.run.encounters_done[0]).is_equal(3)
