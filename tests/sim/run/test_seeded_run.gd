extends GdUnitTestSuite
## The seeded run (L2, FT-MIS-001, FT-MIS-024 to FT-MIS-027): a bot crew plays the director's
## run on the M3 map: four to six encounters (Q4) at named sites of the one cube, reached by
## impulse flight and by the jump drive, the same run for the same seed.

## Seed 1 wins this run (measured 2026-11-08; the earlier search over seeds 1 to 8 stopped there).
const WINNING_SEED: int = 1


# FT: FT-MIS-001, FT-MIS-024, FT-MIS-025, FT-MIS-026, FT-MIS-027
func test_four_to_six_encounters_at_named_sites_by_impulse_and_jump() -> void:
	var defs: DefLibrary = DefLibrary.new()
	var r: Dictionary = BotRun.play(defs, "average", "easy", WINNING_SEED, 3600.0, 0.5)
	(
		assert_str(r["outcome"])
		. override_failure_message("seed %d no longer wins" % WINNING_SEED)
		. is_equal("win")
	)
	var rows: Array = r["encounters"]
	# Q4, owner 2026-10-26: the director picks 4 to 6 encounters by pacing and budget.
	assert_int(rows.size()).is_between(4, 6)
	for e: Dictionary in rows:
		assert_str(e["site_name_key"]).starts_with("site.")
		assert_bool(e["lost"]).is_false()
	# Both ways of getting about happened: the jump drive, and flight under impulse.
	assert_int(r["jumps"]).is_greater(0)
	assert_float(r["top_speed"]).is_greater(20.0)
	# The director's decisions are all there, with reasons (FT-MIS-006, FT-MIS-027).
	var strings: Dictionary = (
		JSON.parse_string(FileAccess.get_file_as_string(I18n.STRINGS))["strings"]
	)
	var picks: int = 0
	for d: Dictionary in r["decisions"]:
		picks += 1 if d["kind"] == "PICK_ENCOUNTER" else 0
		assert_str(d["reason_key"]).starts_with("director.reason.")
		# Each reason has a string, with no placeholder left unfilled (FT-MIS-006).
		assert_bool(strings.has(d["reason_key"])).is_true()
		var text: String = str(strings[d["reason_key"]]["en"]).format(d["reason_args"])
		assert_bool(text.contains("{")).is_false()
	assert_int(picks).is_equal(rows.size())


# FT: FT-ARC-008
func test_the_same_seed_plays_the_same_run() -> void:
	var defs: DefLibrary = DefLibrary.new()
	# 600 s of sim still covers two encounters, in two thirds of the time of 900 s (#27).
	Determinism.assert_deterministic(
		self,
		func() -> String: return JSON.stringify(BotRun.play(defs, "average", "easy", 3, 600.0))
	)
