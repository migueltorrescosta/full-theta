extends GdUnitTestSuite
## P11 Engineering + Relay pair test (spec §7.4): scenario and scripts in
## p11_scenario.gd. §7.4's other P11 test point, that fabricating a probe consumes the
## specified parts and adds one probe, is covered in
## tests/sim/relay/test_probes.gd, test_fabrication_takes_parts_and_adds_one_probe.

const BETTER: Dictionary = {
	"damage": PairHarness.Better.LOWER, "repair_time": PairHarness.Better.LOWER
}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# With Relay's probe forecast Engineering hardens before the front arrives, and takes
# less damage and repairs sooner than reacting on impact by P11's pair_min_gain; the
# solo crew still gets both subsystems whole again.
func test_coop_beats_solo() -> void:
	var p11: PairDef = load("res://content/pairs/p11.tres") as PairDef
	var harness: PairHarness = P11Scenario.harness()
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		P11Scenario.coop, P11Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p11.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)


# FT: FT-PAIR-015
# The same seed and scripts give the same end state.
func test_runs_are_deterministic() -> void:
	var harness: PairHarness = P11Scenario.harness()
	assert_str(harness.run(P11Scenario.coop).state_hash).is_equal(
		harness.run(P11Scenario.coop).state_hash
	)
