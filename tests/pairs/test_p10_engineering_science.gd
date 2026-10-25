extends GdUnitTestSuite
## P10 Engineering + Science pair test (spec §7.4): scenario and scripts in
## p10_scenario.gd. The noise side of the pair (sensor pips 3 < pips 1) is covered in
## tests/sim/science/test_science_noise.gd, test_sensor_pips_set_noise_in_the_world.

const BETTER: Dictionary = {"time": PairHarness.Better.LOWER}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Repair time with the cause Science named is shorter than the brute-force repair by
# P10's pair_min_gain; the brute-force repair (no Science) still repairs the fault.
func test_coop_beats_solo() -> void:
	var p10: PairDef = load("res://content/pairs/p10.tres") as PairDef
	var harness: PairHarness = P10Scenario.harness()
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		P10Scenario.coop, P10Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p10.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)


# FT: FT-PAIR-015
# The same seed and scripts give the same end state (the harness's determinism check).
func test_runs_are_deterministic() -> void:
	var harness: PairHarness = P10Scenario.harness()
	assert_str(harness.run(P10Scenario.coop).state_hash).is_equal(
		harness.run(P10Scenario.coop).state_hash
	)
