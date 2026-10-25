extends GdUnitTestSuite
## The Over-horizon strike play (spec §7.4, Plays): Relay probes a contact beyond the
## sensors (P13), Science scans it through the probe and reveals the weak point (P7),
## Weapons fires guided at the tracked contact (P8). Scenario and scripts in
## strike_scenario.gd; the metric is the time to disable the raider's weapons.


func _run(
	harness: PairHarness, use_probe: bool, use_scan: bool, use_track: bool
) -> PairHarness.Run:
	return harness.run(StrikeScenario.crew(use_probe, use_scan, use_track))


# FT: FT-PAIR-022
# The full chain (probe, scan, guided fire at the probe's track) disables the raider
# strictly sooner (D201) than each chain with one link removed, on the same seed: no
# probe (nothing is tracked or scanned before 5 km), no scan (the weak point stays hidden,
# hits take the ordinary share), and Weapons ignoring the probe's track (it waits for its
# own sensors, though Science already revealed the weak point). All of them complete.
func test_full_chain_beats_every_chain_with_a_link_removed() -> void:
	var harness: PairHarness = StrikeScenario.harness()
	var full: PairHarness.Run = _run(harness, true, true, true)
	assert_bool(full.completed).is_true()
	assert_float(full.metrics.weak_point_hits).is_greater(0.0)
	var cut: Dictionary[String, PairHarness.Run] = {
		"no Relay": _run(harness, false, true, true),
		"no Science": _run(harness, true, false, true),
		"Weapons not using the probe's track": _run(harness, true, true, false),
	}
	for name: String in cut:
		var run: PairHarness.Run = cut[name]
		assert_bool(run.completed).override_failure_message("%s did not complete" % name).is_true()
		(
			assert_float(full.metrics.time)
			. override_failure_message(
				(
					"full chain %.2f s is not strictly under %s: %.2f s"
					% [full.metrics.time, name, run.metrics.time]
				)
			)
			. is_less(run.metrics.time)
		)
	# The same seed twice gives the same run.
	assert_str(_run(harness, true, true, true).state_hash).is_equal(full.state_hash)
