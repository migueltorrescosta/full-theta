extends GdUnitTestSuite
## P2 Helm + Weapons pair test (spec §7.4): scenario and scripts in p2_scenario.gd.
## The sim-level arc rules (a bring-to-bear turn takes a mount from 0 to 1 in arc) are
## tested in tests/sim/combat/test_weapons.gd; here the whole crew plays.

const BETTER: Dictionary = {"time": PairHarness.Better.LOWER}


# FT: FT-PAIR-001, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Co-op (Helm holds Face on the raider, Weapons fires) beats solo (Weapons alone, the
# raider in arc only while it crosses the bow) by P2's pair_min_gain on time to damage;
# solo completes.
func test_coop_beats_solo() -> void:
	var p2: PairDef = load("res://content/pairs/p2.tres") as PairDef
	var runs: Dictionary[String, PairHarness.Run] = P2Scenario.harness().compare(
		P2Scenario.coop, P2Scenario.solo
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p2.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)


# FT: FT-PAIR-015, FT-SIM-002
# The same seed gives the same run (the state hash matches).
func test_runs_are_deterministic() -> void:
	var a: PairHarness.Run = P2Scenario.harness().run(P2Scenario.coop)
	var b: PairHarness.Run = P2Scenario.harness().run(P2Scenario.coop)
	assert_str(a.state_hash).is_equal(b.state_hash)
