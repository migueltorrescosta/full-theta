extends GdUnitTestSuite
## P4 Helm + Relay pair test (spec §7.4): scenario and scripts in p4_scenario.gd. The
## route costs time (a longer path); the pair is measured on damage and propellant.

const BETTER: Dictionary = {
	"hull_lost": PairHarness.Better.LOWER, "propellant": PairHarness.Better.LOWER
}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Helm flying Relay's route around the hazard takes less hull damage and uses less
# propellant than the straight line by P4's pair_min_gain; the straight line still
# arrives.
func test_coop_beats_solo() -> void:
	var p4: PairDef = load("res://content/pairs/p4.tres") as PairDef
	var harness: PairHarness = P4Scenario.harness()
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		P4Scenario.coop, P4Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p4.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)


# FT: FT-PAIR-015
# The same seed and scripts give the same end state.
func test_runs_are_deterministic() -> void:
	var harness: PairHarness = P4Scenario.harness()
	assert_str(harness.run(P4Scenario.coop).state_hash).is_equal(
		harness.run(P4Scenario.coop).state_hash
	)
