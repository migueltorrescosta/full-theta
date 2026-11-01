extends GdUnitTestSuite
## The seeded run (L2, FT-MIS-001, FT-MIS-024 to FT-MIS-027): a bot crew plays the director's
## run on the M3 map: four to six encounters (Q4) at named sites of the one cube, reached by
## impulse flight and by the jump drive, the same run for the same seed.


func _won(defs: DefLibrary) -> Dictionary:
	for seed_value: int in range(1, 9):
		var r: Dictionary = BotRun.play(defs, "average", "easy", seed_value, 3600.0, 0.5)
		if r["outcome"] == "win":
			return r
	return {}


# FT: FT-MIS-001, FT-MIS-024, FT-MIS-025, FT-MIS-026, FT-MIS-027
func test_four_to_six_encounters_at_named_sites_by_impulse_and_jump() -> void:
	var defs: DefLibrary = DefLibrary.new()
	var r: Dictionary = _won(defs)
	assert_bool(r.is_empty()).is_false()
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
	var picks: int = 0
	for d: Dictionary in r["decisions"]:
		picks += 1 if d["kind"] == "PICK_ENCOUNTER" else 0
		assert_str(d["reason_key"]).starts_with("director.reason.")
	assert_int(picks).is_equal(rows.size())


# FT: FT-ARC-008
func test_the_same_seed_plays_the_same_run() -> void:
	var defs: DefLibrary = DefLibrary.new()
	# 600 s of sim still covers two encounters, in two thirds of the time of 900 s (#27).
	var a: Dictionary = BotRun.play(defs, "average", "easy", 3, 600.0)
	var b: Dictionary = BotRun.play(defs, "average", "easy", 3, 600.0)
	assert_str(JSON.stringify(a)).is_equal(JSON.stringify(b))
