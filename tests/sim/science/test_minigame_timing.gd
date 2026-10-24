extends GdUnitTestSuite
## E01: both minigames take 5 to 20 s for a scripted average player at nominal noise
## (FT-SCI-012, D192). The first-time player's 45 s is checked in the #13 playtest.

const ME: int = 0
const FOE: int = 1
const SEEDS: int = 24
## Range at which a broadside scan has about the nominal noise (0.33).
const NOMINAL_RANGE: float = 12400.0


# FT: FT-SCI-012, FT-SCI-004
# The silhouette-alignment scan at nominal noise: every seed's run is within 5 to 20 s
# and the average player's match locks.
func test_scan_takes_5_to_20_seconds_at_nominal_noise() -> void:
	var total: float = 0.0
	for s: int in SEEDS:
		var w: SimWorld = ScienceFixture.world(NOMINAL_RANGE, true, null, 100 + s)
		ScienceFixture.do(w, ScienceFixture.scan_cmd())
		assert_float(w.science.noise[ME]).is_equal_approx(w.science_def.nominal_noise, 0.05)
		var secs: float = ScriptedPlayer.new(s).play_scan(w)
		assert_float(secs).is_between(5.0, 20.0)
		total += secs
		assert_float(ScienceKnowledge.confidence(w, 1, FOE)).is_greater(0.8)
	assert_float(total / SEEDS).is_between(5.0, 20.0)


# FT: FT-SCI-012
# At the cleanest (1 axis) and the noisiest (3 axes) the average player stays under 20 s.
func test_scan_stays_under_20_seconds_at_any_noise() -> void:
	for s: int in SEEDS:
		for spec: Array in [[2000.0, true], [18000.0, false]]:
			var w: SimWorld = ScienceFixture.world(spec[0], spec[1], null, 200 + s)
			ScienceFixture.do(w, ScienceFixture.scan_cmd())
			assert_float(ScriptedPlayer.new(s).play_scan(w)).is_less(20.0)


# FT: FT-SCI-012, FT-SCI-006
# The node-route hack at nominal noise: within 5 to 20 s, and the trace bar does not
# fill for the average player, who ends with a hack window open.
func test_hack_takes_5_to_20_seconds_at_nominal_noise() -> void:
	var total: float = 0.0
	for s: int in SEEDS:
		var w: SimWorld = ScienceFixture.world(NOMINAL_RANGE, true, null, 300 + s)
		ScienceFixture.do(w, ScienceFixture.scan_cmd())
		ScienceFixture.do(w, ScienceFixture.submit_cmd(ScienceFixture.solution(w)))
		ScienceFixture.do(w, ScienceFixture.hack_cmd(&"weapons"))
		var secs: float = ScriptedPlayer.new(s).play_hack(w)
		assert_float(secs).is_between(5.0, 20.0)
		total += secs
		assert_int(w.hacks.size()).is_equal(1)
	assert_float(total / SEEDS).is_between(5.0, 20.0)
