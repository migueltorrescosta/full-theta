extends GdUnitTestSuite
## P13 Science + Relay pair test (spec §7.4): scenario and scripts in p13_scenario.gd.
## Solo is Science waiting for the raider to come into the ship's own sensor range.

const BETTER: Dictionary = {
	"time": PairHarness.Better.LOWER, "trace_peak": PairHarness.Better.LOWER
}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Co-op (Relay's probe over the closing raider) beats solo (own sensors only) by P13's
# pair_min_gain on the time to an open hack window and on the peak of the hack's trace
# bar; a contact beyond the sensors is scanned only through the probe; solo completes;
# the same seed gives the same run.
func test_coop_beats_solo() -> void:
	var p13: PairDef = load("res://content/pairs/p13.tres") as PairDef
	var harness: PairHarness = P13Scenario.harness()
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		P13Scenario.coop_crew(), P13Scenario.solo_crew()
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p13.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	var sensors: float = TestDefs.corvette().sensor_range
	assert_float(runs.coop.metrics.scan_range).is_greater(sensors)
	assert_float(runs.coop.metrics.scan_on_probe).is_equal(1.0)
	assert_float(runs.solo.metrics.scan_range).is_less_equal(sensors)
	assert_float(runs.solo.metrics.scan_on_probe).is_equal(0.0)
	var again: PairHarness.Run = harness.run(P13Scenario.coop_crew())
	assert_str(again.state_hash).is_equal(runs.coop.state_hash)
