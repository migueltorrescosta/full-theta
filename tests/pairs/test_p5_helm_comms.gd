extends GdUnitTestSuite
## P5 Helm + Comms pair test (spec §7.4): scenario and scripts in p5_scenario.gd. A cleared
## approach docks and keeps reputation; an uncleared one loses reputation within the
## distribution's range; both runs survive.


# FT: FT-PAIR-001, FT-MIS-019
# The cleared run docks inside the window and its reputation is unchanged; the uncleared one
# is hit by a draw inside rep.uncleared_approach's range, and the card fails.
func test_cleared_keeps_reputation_and_uncleared_loses_within_range() -> void:
	var runs: Dictionary[String, PairHarness.Run] = P5Scenario.harness().compare(
		P5Scenario.coop_crew(), P5Scenario.solo
	)
	var dist: RepDistDef = load("res://content/economy/rep/uncleared_approach.tres") as RepDistDef
	assert_float(runs.coop.metrics.cleared).is_equal(1.0)
	assert_float(runs.coop.metrics.rep_lost).is_equal(0.0)
	assert_float(runs.solo.metrics.cleared).is_equal(0.0)
	assert_float(runs.solo.metrics.rep_lost).is_between(-dist.hi, -dist.lo)
	# The solo run docked before the window opened, the co-op run inside it.
	assert_float(runs.solo.metrics.seconds).is_less(P5Scenario.LANE_OPEN_S)
	assert_float(runs.coop.metrics.seconds).is_between(
		P5Scenario.LANE_OPEN_S, P5Scenario.LANE_OPEN_S + P5Scenario.LANE_S
	)


# FT: FT-PAIR-001
# The lane is a window that exists only once the clearance is accepted, opens
# lane_delay later and lasts lane_length; a late dock loses reputation too.
func test_the_window_and_a_late_dock() -> void:
	var w: SimWorld = P5Scenario.build()
	P5Scenario.environment(w)
	w.step()
	assert_array(StoryRules.lane_window(w, 0)).is_empty()
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = 0
	assert_bool(StoryFixture.run(w, 0, accept)).is_true()
	var window: Array[int] = StoryRules.lane_window(w, 0)
	assert_int(window[1] - window[0]).is_equal(roundi(P5Scenario.LANE_S * SimWorld.HZ))
	assert_int(window[0] - w.tick + 1).is_equal(roundi(P5Scenario.LANE_OPEN_S * SimWorld.HZ))
	while w.tick <= window[1]:
		w.step()
	StoryFixture.dock(w, 0, w.story.site[0])
	w.step()
	assert_int(w.story.state[0]).is_equal(StoryTable.State.FAILED)
	assert_float(w.reputation.value_of(P5Scenario.BLUE, P5Scenario.YARD_FACTION)).is_less(0.0)
