extends GdUnitTestSuite
## The director's pacing (gp-05 to gp-08, D3): the strength ramp over a run, the finale that
## ends it (won: the run closes; fled or timed out: offered again, then the run closes), the
## quiet gap a Ready crew skips, and Easy's budget of 9. Worlds are ApiFixture's, scenarios
## TestScenario's.

const TICKS: int = 60 * 70
const FINALE: StringName = &"s_fin"


## A finale that ends PARTIAL (the time ran out) after `ticks` ticks.
class TimedOut:
	extends TestScenario

	func meta() -> ScenarioMeta:
		var m: ScenarioMeta = super.meta()
		m.id = FINALE
		return m

	func fresh() -> Scenario:
		return TimedOut.new()

	func finished(api: ScenarioApi) -> int:
		return Scenario.Result.ACTIVE if api.tick() - _started_at < 60 else Scenario.Result.PARTIAL


## Records the strength each encounter starts with.
class Recorder:
	extends TestScenario

	var seen: Array[float] = []

	func fresh() -> Scenario:
		var r: Recorder = Recorder.new()
		r._id = _id
		r._cost = _cost
		r.seen = seen
		return r

	func start(api: ScenarioApi, params: Dictionary) -> void:
		super.start(api, params)
		seen.append(float(params["strength"]))


func _def(fewest: int, most: int, gap: float = 1.0) -> RunDef:
	var run: RunDef = ApiFixture.run_def(
		PackedStringArray(["s_a", "s_b", String(FINALE)]), 10.0, gap, fewest, most
	)
	run.director.ramp_start = 0.7
	run.director.ramp_end = 1.3
	run.director.finale_scenario = FINALE
	run.director.finale_site = &"alpha"
	run.director.finale_tries = 2
	return run


func _run(catalogue: Array[Scenario], def: RunDef, ticks: int = TICKS) -> Array:
	var w: SimWorld = ApiFixture.world(1, def)
	var d: Director = Director.new(def.director, &"normal", catalogue, 3, Factions.CREW)
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in ticks:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	return [w, d]


static func _of_kind(d: Director, kind: DirectorDecision.Kind) -> Array[DirectorDecision]:
	return d.decisions().filter(func(x: DirectorDecision) -> bool: return x.kind == kind)


# FT: FT-MIS-028
# gp-05: linear from ramp_start at the first encounter to ramp_end at the last regular one.
func test_the_ramp_runs_from_start_to_end_over_the_regular_encounters() -> void:
	var def: DirectorDef = _def(4, 6).director
	# Six encounters with a finale: the regular ones are indexes 0 to 4.
	var want: Array[float] = [0.7, 0.85, 1.0, 1.15, 1.3, 1.3]
	for i: int in want.size():
		assert_float(Director.ramp(def, i, 4)).is_equal_approx(want[i], 1e-9)
	assert_float(Director.ramp(def, 0, 0)).is_equal(0.7)
	assert_float(Director.strength_for(def, &"normal", 1.3, 2)).is_equal_approx(1.3, 1e-9)


# FT: FT-MIS-028, FT-MIS-001
# gp-06: the regular picks take the run's limits less one, the finale is last (its site
# alpha, no budget spent, at ramp_end) and winning it closes the run; each pick logs its ramp.
func test_the_finale_is_last_and_winning_it_closes_the_run() -> void:
	var rec: Recorder = Recorder.new()
	rec._id = &"s_a"
	var fin: Recorder = Recorder.new()
	fin._id = FINALE
	fin.seen = rec.seen
	var out: Array = _run([rec, fin], _def(2, 3))
	var w: SimWorld = out[0]
	var d: Director = out[1]
	var picks: Array[DirectorDecision] = _of_kind(d, DirectorDecision.Kind.PICK_ENCOUNTER)
	assert_int(picks.size()).is_equal(3)
	assert_str(String(picks[2].scenario_id)).is_equal(String(FINALE))
	assert_str(picks[2].reason_key).is_equal("director.reason.finale")
	assert_int(picks[2].cost).is_equal(0)
	assert_int(picks[2].site).is_equal(1)
	assert_float(float(picks[0].reason_args["ramp"])).is_equal_approx(0.7, 1e-9)
	assert_float(float(picks[1].reason_args["ramp"])).is_equal_approx(1.3, 1e-9)
	assert_array(rec.seen).has_size(3)
	assert_float(rec.seen[2]).is_equal_approx(1.3, 1e-9)
	var ends: Array[DirectorDecision] = _of_kind(d, DirectorDecision.Kind.END_RUN)
	assert_int(ends.size()).is_equal(1)
	assert_str(ends[0].reason_key).is_equal("director.reason.finale_won")
	assert_int(w.ships.encounters_done[0]).is_equal(3)
	assert_int(w.ships.ship_outcome[0]).is_equal(ShipStateTable.ShipOutcome.WIN)


# FT: FT-MIS-028, FT-MIS-001
# gp-06: a finale whose time ran out is offered again after the gap, at most finale_tries
# times; then the run closes anyway.
func test_a_failed_finale_is_retried_then_the_run_closes() -> void:
	var out: Array = _run([TestScenario.make(&"s_a", 1), TimedOut.new()], _def(1, 2))
	var w: SimWorld = out[0]
	var d: Director = out[1]
	var picks: Array[DirectorDecision] = _of_kind(d, DirectorDecision.Kind.PICK_ENCOUNTER)
	var ids: Array[String] = []
	for p: DirectorDecision in picks:
		ids.append(String(p.scenario_id))
	assert_array(ids).is_equal(["s_a", String(FINALE), String(FINALE)])
	assert_int(int(picks[2].reason_args["try"])).is_equal(2)
	var ends: Array[DirectorDecision] = _of_kind(d, DirectorDecision.Kind.END_RUN)
	assert_int(ends.size()).is_equal(1)
	assert_str(ends[0].reason_key).is_equal("director.reason.finale_out")
	assert_int(w.ships.ship_outcome[0]).is_equal(ShipStateTable.ShipOutcome.WIN)


# FT: FT-MIS-001
# gp-06: a spent budget ends the regular picks at the fewest less one; the finale still comes.
func test_a_spent_budget_still_leads_to_the_finale() -> void:
	var def: RunDef = _def(2, 6)
	def.director.budget_per_ship[&"normal"] = 2
	var out: Array = _run([TestScenario.make(&"s_a", 2), TestScenario.make(FINALE, 5)], def)
	var picks: Array[DirectorDecision] = _of_kind(out[1], DirectorDecision.Kind.PICK_ENCOUNTER)
	assert_int(picks.size()).is_equal(2)
	assert_str(String(picks[1].scenario_id)).is_equal(String(FINALE))
	assert_int((out[1] as Director).budget_left()).is_equal(0)


# FT: FT-MIS-025
# gp-07: the gap is announced in its flag (the tick it ends); a skip flag set inside it makes
# the director pick at once, and the gap flag clears.
func test_a_ready_crew_skips_the_quiet_gap() -> void:
	var def: RunDef = _def(1, 2, 100.0)
	var w: SimWorld = ApiFixture.world(1, def)
	var d: Director = Director.new(
		def.director, &"normal", [TestScenario.make(&"s_a", 1)], 3, Factions.CREW
	)
	var host: ScenarioHost = ScenarioHost.new(w)
	for i: int in 30:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	var flag: StringName = Director.gap_flag(Factions.CREW)
	assert_int(w.story_flags.get_flag(flag)).is_equal(SimRate.ticks(100.0))
	assert_int(w.encounters.size()).is_equal(0)
	var skip: SetFlagCommand = SetFlagCommand.new()
	skip.flag_name = Director.skip_flag(Factions.CREW)
	skip.value = w.tick
	w.submit(skip)
	for i: int in 5:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	assert_int(w.encounters.size()).is_equal(1)
	assert_int(w.story_flags.get_flag(flag)).is_equal(0)
	# The next gap is not skipped by the old flag.
	for i: int in 60 * 20:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	assert_int(w.encounters.size()).is_equal(1)
	assert_int(w.story_flags.get_flag(flag)).is_greater(w.tick)


# FT: FT-MIS-029, FT-MIS-028
# gp-08, R17-18: Easy has Normal's budget of 9 at strength 0.5, so its runs are no longer
# mostly debris legs: with the run's real costs (enemy_wave 3, rescue 2, debris_leg 1) every
# seeded Easy run picks at least two hostile encounters before the finale.
func test_easy_has_a_budget_of_nine_and_hostile_picks() -> void:
	var m3: DirectorDef = (load("res://content/runs/m3_director.tres") as DirectorDef).duplicate()
	assert_int(m3.budget_per_ship[&"easy"]).is_equal(9)
	assert_float(m3.strength_per_preset[&"easy"]).is_equal(0.5)
	m3.gap = 1.0
	m3.arrival_timeout = 1.0
	var run: RunDef = ApiFixture.run_def(
		PackedStringArray(["enemy_wave", "rescue", "debris_leg", "finale"]), 1.0, 1.0, 4, 6
	)
	run.director = m3
	for seed_value: int in [1, 2, 3, 4, 5]:
		var w: SimWorld = ApiFixture.world(1, run)
		var catalogue: Array[Scenario] = [
			TestScenario.make(&"enemy_wave", 3, false, 30, true),
			TestScenario.make(&"rescue", 2, false, 30, true),
			TestScenario.make(&"debris_leg", 1, false, 30),
			TestScenario.make(&"finale", 1, false, 30, true),
		]
		var d: Director = Director.new(m3, &"easy", catalogue, seed_value, Factions.CREW)
		var host: ScenarioHost = ScenarioHost.new(w)
		for i: int in 60 * 40:
			host.advance(SimWorld.DT * 1.001, d.before_tick)
		var hostile: int = 0
		var picks: Array[DirectorDecision] = _of_kind(d, DirectorDecision.Kind.PICK_ENCOUNTER)
		for p: DirectorDecision in picks:
			if p.scenario_id in [&"enemy_wave", &"rescue"]:
				hostile += 1
		assert_int(hostile).override_failure_message("seed %d" % seed_value).is_greater_equal(2)
		assert_str(String(picks[-1].scenario_id)).is_equal("finale")


# FT: FT-MIS-032
# gp-06: a race plan ends with the finale too, at its site when the map has it.
func test_a_race_plan_ends_with_the_finale() -> void:
	var def: DirectorDef = _def(2, 4).director
	var catalogue: Array[Scenario] = [TestScenario.make(&"s_a", 1), TestScenario.make(FINALE, 1)]
	var d: Director = Director.new(def, &"normal", catalogue, 3, Factions.CREW)
	var plan: Array[Dictionary] = d.plan_race(Vector2i(2, 4), PackedStringArray(["alpha", "beta"]))
	assert_int(plan.size()).is_equal(4)
	assert_str(String(plan[-1]["scenario"])).is_equal(String(FINALE))
	assert_str(String(plan[-1]["site"])).is_equal("alpha")
	for i: int in 3:
		assert_str(String(plan[i]["scenario"])).is_equal("s_a")


# FT: FT-MIS-025
# A relaunch mid-gap (D259) restarts the fleet's plan: the gap's flag clears with it, so the
# Ready card never sits at 0:00, and the next encounter is picked.
func test_a_relaunch_in_a_gap_clears_the_gap_flag() -> void:
	var def: RunDef = _def(2, 3, 10.0)
	var w: SimWorld = ApiFixture.world(1, def)
	var d: Director = Director.new(
		def.director, &"normal", [TestScenario.make(&"s_a", 1)], 3, Factions.CREW
	)
	var host: ScenarioHost = ScenarioHost.new(w)
	var flag: StringName = Director.gap_flag(Factions.CREW)
	while w.encounters.size() < 1 or w.encounters.result[0] <= EncounterTable.Result.ACTIVE:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	for i: int in 60:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	assert_int(w.story_flags.get_flag(flag)).is_greater(w.tick)
	var relaunched: SimEvent = SimEvent.new()
	relaunched.kind = Director.RELAUNCHED
	relaunched.ship_id = 0
	w.step_events = [relaunched]
	d.before_tick(ScenarioApi.new(w))
	w.step()
	for i: int in 3:
		host.advance(SimWorld.DT * 1.001, d.before_tick)
	assert_int(w.story_flags.get_flag(flag)).is_equal(0)
	assert_int(w.encounters.size()).is_equal(2)
