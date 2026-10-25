extends GdUnitTestSuite
## The Hack alpha play (spec §7.4 Plays, FT-PAIR-022): scenario and scripted crews in
## hack_alpha_scenario.gd.


# FT: FT-PAIR-022
# The full chain (Science hack, Helm to bear, Engineering weapons power, Weapons fire)
# deals strictly more damage inside the hack window than every chain with one link
# removed, on the same seed (D201).
func test_full_chain_beats_every_chain_with_a_link_removed() -> void:
	var harness: PairHarness = HackAlphaScenario.harness()
	var full: PairHarness.Run = harness.run(HackAlphaScenario.crew(HackAlphaScenario.FULL))
	var lines: PackedStringArray = PackedStringArray(["full: %s" % full.metrics])
	var failures: Array[String] = []
	for link: int in [
		HackAlphaScenario.S, HackAlphaScenario.H, HackAlphaScenario.E, HackAlphaScenario.W
	]:
		var chain: int = HackAlphaScenario.FULL & ~link
		var cut: PairHarness.Run = harness.run(HackAlphaScenario.crew(chain))
		lines.append("without link %d: %s" % [link, cut.metrics])
		if not full.metrics.damage > cut.metrics.damage:
			failures.append("without link %d: %s" % [link, cut.metrics])
	(
		assert_array(failures)
		. override_failure_message(
			"\n".join(lines) + "\nnot strictly less:\n" + "\n".join(failures)
		)
		. is_empty()
	)


# FT: FT-PAIR-022, FT-PAIR-023
# The scenario's timing holds: Science's hack lands by the tick the crews agreed to open
# fire on, and the window it opens lasts at least 8 s.
func test_hack_lands_in_time_and_the_window_is_long_enough() -> void:
	var w: SimWorld = HackAlphaScenario.build()
	var crew: Callable = HackAlphaScenario.crew(HackAlphaScenario.FULL)
	var landed: int = -1
	var window: float = 0.0
	while not HackAlphaScenario.done(w):
		crew.call(w)
		w.step()
		for e: SimEvent in w.drain_events():
			if e.kind == &"hack_done" and landed < 0:
				landed = e.tick
				window = e.value
	assert_int(landed).is_greater(0)
	assert_int(landed).is_less_equal(HackAlphaScenario.OPEN_TICK)
	assert_float(window).is_greater_equal(8.0)
