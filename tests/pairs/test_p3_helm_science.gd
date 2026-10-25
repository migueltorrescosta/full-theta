extends GdUnitTestSuite
## P3 Helm + Science pair test (spec §7.4): scenario and scripts in p3_scenario.gd. The
## off-aspect scan is the solo run: Science scans the bow-on raider from where the ship
## is, and it completes well inside the scan cap.

const BETTER: Dictionary = {"noise": PairHarness.Better.LOWER, "scan_s": PairHarness.Better.LOWER}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Co-op (Science's scan-position mark, Helm flies to it) beats solo (scan from where the
# ship is) by P3's pair_min_gain on the noise of the scan (the cloud's density) and on the
# seconds the scan takes; the confidence at the mark is no lower; solo completes inside
# the scan cap; the same seed gives the same run.
func test_coop_beats_solo() -> void:
	var p3: PairDef = load("res://content/pairs/p3.tres") as PairDef
	var harness: PairHarness = P3Scenario.harness()
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		P3Scenario.coop_crew(), P3Scenario.solo_crew()
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p3.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	assert_float(runs.coop.metrics.confidence).is_greater_equal(runs.solo.metrics.confidence)
	var cap: float = ScienceFixture.science().scan_cap_s
	assert_float(runs.solo.metrics.scan_s).is_less(cap)
	var again: PairHarness.Run = harness.run(P3Scenario.coop_crew())
	assert_str(again.state_hash).is_equal(runs.coop.state_hash)
