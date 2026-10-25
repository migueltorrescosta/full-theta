extends GdUnitTestSuite
## The Hack alpha play (spec §7.4, S->H+E+W; P7, P2, P6): scenario and scripts in
## hack_alpha_scenario.gd. Metric: damage the raider takes in the hack window.

const S: int = HackAlphaScenario.Link.SCIENCE
const H: int = HackAlphaScenario.Link.HELM
const E: int = HackAlphaScenario.Link.ENGINEERING
const W: int = HackAlphaScenario.Link.WEAPONS


func _damage(removed: int) -> float:
	return HackAlphaScenario.harness().run(HackAlphaScenario.crew(removed)).metrics.damage


# FT: FT-PAIR-022
# The full chain (Science hacks the shields, Helm brings the mounts to bear, Engineering
# powers the weapons, Weapons fires) does strictly more damage in the window than the
# chain with any one link removed, on the same seed (D201); without Helm or Weapons
# nothing lands at all.
func test_full_chain_beats_every_chain_with_one_link_removed() -> void:
	var full: float = _damage(-1)
	var removed: Dictionary[String, float] = {
		"Science": _damage(S), "Helm": _damage(H), "Engineering": _damage(E), "Weapons": _damage(W)
	}
	assert_float(full).is_greater(0.0)
	for link: String in removed:
		(
			assert_float(removed[link])
			. override_failure_message(
				"without %s: %.1f MJ, full chain %.1f MJ" % [link, removed[link] / 1e6, full / 1e6]
			)
			. is_less(full)
		)
	assert_float(removed.Helm).is_equal(0.0)
	assert_float(removed.Weapons).is_equal(0.0)


# FT: FT-PAIR-022
# The window the damage is counted in is the one the full chain's hack opens: WINDOW_START
# is the tick of its hack_done, and the hack_done event comes at the same tick on every
# run. If this fails, the Science script's timing or the sim changed: set WINDOW_START to
# the tick reported.
func test_window_starts_where_the_plan_says() -> void:
	var run: PairHarness.Run = HackAlphaScenario.harness().run(HackAlphaScenario.crew(-1))
	assert_float(run.metrics.hack_done_tick).is_equal(float(HackAlphaScenario.WINDOW_START))
	var again: PairHarness.Run = HackAlphaScenario.harness().run(HackAlphaScenario.crew(-1))
	assert_str(again.state_hash).is_equal(run.state_hash)
