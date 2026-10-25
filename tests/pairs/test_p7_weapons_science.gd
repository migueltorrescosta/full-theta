extends GdUnitTestSuite
## P7 Weapons + Science pair test (spec §7.4): scenario and scripts in p7_scenario.gd.
## The sim-level P7 rules are tested in tests/sim/damage/test_damage_types.gd (weak-point
## share, knowing the weak point shortens time to disable, resisted ammunition does
## less) and tests/sim/science/test_reveals.gd (what a scan reveals); here the crews play.

const BETTER: Dictionary = {"time": PairHarness.Better.LOWER}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Co-op (Science scans, Weapons aims at the revealed weak point with the unresisted
# ammunition) beats solo (nearest-subsystem hits with the default, resisted ammunition)
# by P7's pair_min_gain on time to disable, scan time included; solo completes; only
# co-op lands weak-point hits.
func test_coop_beats_solo() -> void:
	var p7: PairDef = load("res://content/pairs/p7.tres") as PairDef
	var runs: Dictionary[String, PairHarness.Run] = P7Scenario.harness().compare(
		P7Scenario.coop_crew(), P7Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p7.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	assert_float(runs.coop.metrics.weak_hits).is_greater(0.0)
	assert_float(runs.solo.metrics.weak_hits).is_equal(0.0)


# FT: FT-PAIR-015
# The same seed gives the same run (the state hash matches).
func test_runs_are_deterministic() -> void:
	var a: PairHarness.Run = P7Scenario.harness().run(P7Scenario.coop_crew())
	var b: PairHarness.Run = P7Scenario.harness().run(P7Scenario.coop_crew())
	assert_str(a.state_hash).is_equal(b.state_hash)
