extends GdUnitTestSuite
## The Over-horizon strike play (spec §7.4 Plays, FT-PAIR-022): scenario and scripted
## crews in strike_scenario.gd.


# FT: FT-PAIR-022
# The full chain (Relay probe, Science scan through it, Weapons guided fire) disables the
# target strictly sooner than every chain with one link removed, on the same seed
# (D201). A removed link that cannot disable the target at all counts as the tick limit.
func test_full_chain_beats_every_chain_with_a_link_removed() -> void:
	var harness: PairHarness = StrikeScenario.harness()
	var full: PairHarness.Run = harness.run(StrikeScenario.crew(StrikeScenario.FULL))
	assert_bool(full.completed).is_true()
	var lines: PackedStringArray = PackedStringArray(["full: %s" % full.metrics])
	var failures: Array[String] = []
	for link: int in [StrikeScenario.R, StrikeScenario.S, StrikeScenario.W]:
		var cut: PairHarness.Run = harness.run(StrikeScenario.crew(StrikeScenario.FULL & ~link))
		lines.append("without link %d: completed %s, %s" % [link, cut.completed, cut.metrics])
		if not full.metrics.time < cut.metrics.time:
			failures.append("without link %d: %s" % [link, cut.metrics])
	(
		assert_array(failures)
		. override_failure_message("\n".join(lines) + "\nnot strictly slower:\n" + "\n".join(failures))
		. is_empty()
	)


# FT: FT-PAIR-022
# The scenario really is beyond the corvette's sensors: with no probe the target is
# not detected at the start, and the probe's bubble detects it.
# (Without Relay, Helm's slow approach to the sensor range is the cost: the "without
# link 1" chain above.)
func test_target_is_over_the_horizon_until_probed() -> void:
	var w: SimWorld = StrikeScenario.build()
	assert_bool(KnowledgeSystem.is_detected(w, 1, StrikeScenario.FOE)).is_false()
	var crew: Callable = StrikeScenario.crew(StrikeScenario.R)
	while w.tick < 15 * SimWorld.HZ:
		crew.call(w)
		w.step()
	assert_bool(KnowledgeSystem.is_detected(w, 1, StrikeScenario.FOE)).is_true()
