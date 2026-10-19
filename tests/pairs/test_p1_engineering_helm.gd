extends GdUnitTestSuite
## P1 Engineering + Helm pair test (T039, spec §7.4): scenario and scripts in
## p1_scenario.gd. §7.4's other P1 test points are covered elsewhere: heat past the
## threshold creates a fault (tests/sim/power/test_power.gd,
## test_overcharge_heat_creates_one_fault and test_back_to_back_boosts_fault); hull
## damage orders correct-tight < spread < wrong-tight (tests/sim/shields/test_shields.gd,
## test_tight_focus_orders_damage). Zero Engineering input completing is the solo run.

const BETTER: Dictionary = {"time": PairHarness.Better.LOWER, "hull_lost": PairHarness.Better.LOWER}


# FT: FT-PAIR-004, FT-PAIR-015, FT-TST-006, FT-M1-010
# Co-op (boost, overcharge and a tight shield focus Helm points at the raider) beats
# solo (Helm alone) by P1's pair_min_gain on time-to-intercept and hull lost; solo
# completes, and the co-op's heat guard keeps it fault-free.
func test_coop_beats_solo() -> void:
	var p1: PairDef = load("res://content/pairs/p1.tres") as PairDef
	var harness: PairHarness = P1Scenario.harness()
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		P1Scenario.coop, P1Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p1.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	assert_float(runs.coop.metrics.heat_faults).is_equal(0.0)
	assert_str(harness.run(P1Scenario.coop).state_hash).is_equal(runs.coop.state_hash)
