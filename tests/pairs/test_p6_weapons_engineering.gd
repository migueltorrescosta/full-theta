extends GdUnitTestSuite
## P6 Weapons + Engineering pair test (spec §7.4): scenario and scripts in
## p6_scenario.gd. §7.4's other P6 test points are covered in tests/sim: damage with
## weapon pips 3 > 1 (the energy store recharges with the weapons' pips,
## tests/sim/power/test_power.gd) and the overheat lock and its cooldown
## (tests/sim/combat/test_ordnance.gd). Zero Engineering input completing is the solo run.

const BETTER: Dictionary = {"time": PairHarness.Better.LOWER}


# FT: FT-PAIR-001, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Co-op (Engineering puts the spare pips on the weapons) beats solo (nominal pips) by P6's
# pair_min_gain on time to damage; solo completes and the co-op's heat guard keeps it
# fault-free.
func test_coop_beats_solo() -> void:
	var p6: PairDef = load("res://content/pairs/p6.tres") as PairDef
	var runs: Dictionary[String, PairHarness.Run] = P6Scenario.harness().compare(
		P6Scenario.coop, P6Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p6.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	assert_float(runs.coop.metrics.heat_faults).is_equal(0.0)


# FT: FT-PAIR-015
# The same seed gives the same run (the state hash matches).
func test_runs_are_deterministic() -> void:
	var a: PairHarness.Run = P6Scenario.harness().run(P6Scenario.coop)
	var b: PairHarness.Run = P6Scenario.harness().run(P6Scenario.coop)
	assert_str(a.state_hash).is_equal(b.state_hash)
