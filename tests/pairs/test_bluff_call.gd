extends GdUnitTestSuite
## The Bluff call play (spec §7.4, FT-PAIR-022, D201): scenario and scripts in
## bluff_scenario.gd. Metrics: reputation with the trader's faction and credits earned.

const L = BluffScenario.Link


func _run(removed: int) -> Dictionary:
	return BluffScenario.harness().run(BluffScenario.crew(removed)).metrics


# FT: FT-PAIR-022
# The full chain (Comms hears the claim, Science scans the cargo, Comms calls the bluff,
# Weapons acts on the new intent) is strictly better on reputation and on reward than the
# chain with any one link removed, on the same seed (D201).
func test_full_chain_beats_every_chain_with_one_link_removed() -> void:
	var full: Dictionary = _run(-1)
	assert_float(full.reward).is_equal(float(BluffScenario.REWARD))
	var removed: Dictionary[String, Dictionary] = {
		"Comms hears the claim": _run(L.HEAR_CLAIM),
		"Science scans": _run(L.SCAN),
		"Comms calls the bluff": _run(L.CALL_BLUFF),
		"Weapons acts": _run(L.ACT),
	}
	for link: String in removed:
		var m: Dictionary = removed[link]
		(
			assert_float(m.reputation)
			. override_failure_message(
				"without %s: reputation %s, full chain %s" % [link, m.reputation, full.reputation]
			)
			. is_less(full.reputation)
		)
		(
			assert_float(m.reward)
			. override_failure_message(
				"without %s: reward %s, full chain %s" % [link, m.reward, full.reward]
			)
			. is_less(full.reward)
		)


# FT: FT-PAIR-022
# The same seed and scripts give the same end state.
func test_runs_are_deterministic() -> void:
	var harness: PairHarness = BluffScenario.harness()
	assert_str(harness.run(BluffScenario.crew()).state_hash).is_equal(
		harness.run(BluffScenario.crew()).state_hash
	)
