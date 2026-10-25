extends GdUnitTestSuite
## P8 Weapons + Relay pair test (spec §7.4): the engagement and scripts are in
## strike_scenario.gd. The raider starts at twice the corvette's own sensor range and
## closes; solo is Weapons firing guided missiles once its own sensors track the raider.
## The track-quality bar and the friendly-lane warning (also §7.4's P8 test points) are
## covered elsewhere: the lane warning in tests/sim/relay, the track quality is not
## modelled (the track is covered or not, FT-WPN-008).

const BETTER: Dictionary = {
	"time": PairHarness.Better.LOWER,
	"first_hit_s": PairHarness.Better.LOWER,
}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006
# Co-op (Relay's probe tracks the raider beyond the sensors, Weapons fires guided at that
# track) beats solo (own sensors only) by P8's pair_min_gain on the time to the first hit
# and on the time to disable the raider's weapons; solo completes; the same seed gives
# the same run.
func test_coop_beats_solo() -> void:
	var p8: PairDef = load("res://content/pairs/p8.tres") as PairDef
	var harness: PairHarness = StrikeScenario.harness()
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		StrikeScenario.crew(true, false, true), StrikeScenario.crew(false, false, true)
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p8.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	var again: PairHarness.Run = harness.run(StrikeScenario.crew(true, false, true))
	assert_str(again.state_hash).is_equal(runs.coop.state_hash)
