extends GdUnitTestSuite
## P8 Weapons + Relay pair test (spec §7.4): the engagement and scripts are in
## strike_scenario.gd. The raider starts at twice the corvette's own sensor range and
## closes; solo is Weapons firing guided missiles once its own sensors track the raider.
## Weapons holds fire below FIRE_QUALITY on the track-quality bar (D214); the friendly-lane
## warning (also §7.4's P8 test point) is covered in tests/sim/relay, the quality in
## tests/sim/combat/test_track_quality.gd.

const BETTER: Dictionary = {
	"time": PairHarness.Better.LOWER,
	"first_hit_s": PairHarness.Better.LOWER,
}


# FT: FT-PAIR-001, FT-PAIR-003, FT-PAIR-004, FT-PAIR-015, FT-TST-006, FT-WPN-007
# Co-op (Relay's probe tracks the raider beyond the sensors, Weapons fires guided at that
# track) beats solo (own sensors only) by P8's pair_min_gain on the time to the first hit
# and on the time to disable the raider's weapons, and fires its first missile on a better
# track (the quality bar); solo completes; the same seed gives the same run.
func test_coop_beats_solo() -> void:
	var p8: PairDef = load("res://content/pairs/p8.tres") as PairDef
	var harness: PairHarness = StrikeScenario.harness()
	var coop_shots: Array[float] = []
	var solo_shots: Array[float] = []
	var runs: Dictionary[String, PairHarness.Run] = harness.compare(
		StrikeScenario.crew(true, false, true, coop_shots),
		StrikeScenario.crew(false, false, true, solo_shots)
	)
	var failures: Array[String] = PairHarness.check(runs, BETTER, p8.pair_min_gain)
	(
		assert_array(failures)
		. override_failure_message("\n".join(failures) + "\n" + PairHarness.summary(runs))
		. is_empty()
	)
	# The probe's track is the better one: the first missile flies on a higher-quality track.
	var quality_gain: float = PairHarness.gain(
		coop_shots[0], solo_shots[0], PairHarness.Better.HIGHER
	)
	assert_float(quality_gain).is_greater_equal(p8.pair_min_gain)
	assert_float(solo_shots[0]).is_greater_equal(StrikeScenario.FIRE_QUALITY)
	var again: PairHarness.Run = harness.run(StrikeScenario.crew(true, false, true))
	assert_str(again.state_hash).is_equal(runs.coop.state_hash)
