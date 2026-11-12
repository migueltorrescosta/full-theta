extends GdUnitTestSuite
## The director's pick rules at their edges (A10, #38 D3, R10-5, R17-6): the low-hull swap, the
## run-length close, nothing fitting, and a budget the run's presets don't list. Worlds are
## ApiFixture's, scenarios TestScenario's.

const TICKS: int = 60 * 40


func _run(
	catalogue: Array[Scenario], difficulty: StringName = &"normal", def: RunDef = null
) -> Array:
	var w: SimWorld = ApiFixture.world(1, def if def != null else ApiFixture.run_def())
	var d: Director = Director.new(
		w.run_def.director, difficulty, catalogue, 3, M1Encounter.PLAYER_FACTION
	)
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in TICKS:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	return [w, d]


static func _of_kind(d: Director, kind: DirectorDecision.Kind) -> Array[DirectorDecision]:
	return d.decisions().filter(func(x: DirectorDecision) -> bool: return x.kind == kind)


# FT: FT-MIS-028
# A damaged ship (hull under half) is not sent into another hostile encounter while a calm one
# fits: the pick is the calm scenario and the log says low_hull.
func test_a_damaged_ship_gets_a_calm_scenario() -> void:
	var w: SimWorld = ApiFixture.world(1, ApiFixture.run_def(PackedStringArray(["s_h", "s_c"])))
	w.damage.health[w.damage.hull_row(0)] = w.defs[0].hull_max * 0.3
	var catalogue: Array[Scenario] = [
		TestScenario.make(&"s_h", 1, false, 60, true), TestScenario.make(&"s_c", 1)
	]
	var d: Director = Director.new(
		w.run_def.director, &"normal", catalogue, 3, M1Encounter.PLAYER_FACTION
	)
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in 600:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	var first: DirectorDecision = _of_kind(d, DirectorDecision.Kind.PICK_ENCOUNTER)[0]
	assert_str(String(first.scenario_id)).is_equal("s_c")
	assert_str(first.reason_key).is_equal("director.reason.low_hull")


# FT: FT-MIS-028
# At the most encounters a run allows, the director closes it with run_length, once.
func test_the_run_closes_at_the_most_encounters() -> void:
	var def: RunDef = ApiFixture.run_def(PackedStringArray(["s_a"]), 10.0, 1.0, 1, 1)
	var out: Array = _run([TestScenario.make(&"s_a", 1)], &"normal", def)
	var d: Director = out[1]
	assert_int(_of_kind(d, DirectorDecision.Kind.PICK_ENCOUNTER).size()).is_equal(1)
	var ends: Array[DirectorDecision] = _of_kind(d, DirectorDecision.Kind.END_RUN)
	assert_int(ends.size()).is_equal(1)
	assert_str(ends[0].reason_key).is_equal("director.reason.run_length")
	assert_int((out[0] as SimWorld).ships.ship_outcome[0]).is_equal(ShipStateTable.ShipOutcome.WIN)


# FT: FT-MIS-029
# An empty catalogue cannot play the fewest encounters: the director says so once (no_fit)
# and does not spin.
func test_nothing_to_play_is_logged_once() -> void:
	var out: Array = _run([])
	var skips: Array[DirectorDecision] = _of_kind(out[1], DirectorDecision.Kind.SKIP)
	assert_int(skips.size()).is_equal(1)
	assert_str(skips[0].reason_key).is_equal("director.reason.no_fit")


# FT: FT-MIS-029, FT-MIS-001
# R17-6: a preset the director's budget table lacks counts a budget of 0; the cheapest
# scenario still goes in below the fewest, so the run is played and won rather than stalled.
func test_a_preset_without_a_budget_still_finishes_the_run() -> void:
	var out: Array = _run([TestScenario.make(&"s_a", 3), TestScenario.make(&"s_b", 2)], &"extreme")
	var d: Director = out[1]
	var picks: Array[DirectorDecision] = _of_kind(d, DirectorDecision.Kind.PICK_ENCOUNTER)
	assert_int(picks.size()).is_equal(1)
	assert_str(String(picks[0].scenario_id)).is_equal("s_b")
	assert_int((out[0] as SimWorld).ships.ship_outcome[0]).is_equal(ShipStateTable.ShipOutcome.WIN)


# FT: FT-MIS-029
# R17-6: a run's director must list a budget for every preset the lobby offers.
func test_a_run_validates_that_every_preset_has_a_budget() -> void:
	var run: RunDef = ApiFixture.run_def()
	run.director.budget_per_ship.erase(&"hard")
	var errors: Array[String] = run.validate().filter(
		func(e: String) -> bool: return e.contains("hard")
	)
	assert_array(errors).has_size(1)
