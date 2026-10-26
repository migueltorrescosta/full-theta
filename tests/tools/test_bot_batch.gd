extends GdUnitTestSuite
## The bot batch (FT-TST-022, FT-GEN-009): a small run of scripted crews with no game master
## and no network writes a report with the loss rate, fled encounters apart and run length,
## and the same seeds give the same report.


func _batch() -> Array[Dictionary]:
	var defs: DefLibrary = DefLibrary.new()
	var out: Array[Dictionary] = []
	for profile: String in BotProfiles.NAMES:
		for n: int in 2:
			out.append(BotRun.play(defs, profile, "easy", 1 + n, 700.0))
	return out


# FT: FT-TST-022, FT-GEN-009
func test_a_smoke_batch_gives_a_deterministic_report() -> void:
	var results: Array[Dictionary] = _batch()
	var encounters: int = 0
	for r: Dictionary in results:
		encounters += (r["encounters"] as Array).size()
	assert_int(encounters).is_greater_equal(8)
	var report: String = BotReport.markdown(results)
	assert_str(report).contains("| easy / average |")
	assert_str(report).contains("| easy / novice |")
	assert_str(report).contains("loss rate")
	assert_str(report).contains("fled rate")
	assert_str(report).contains("run length min")
	assert_str(report).contains("survive 3 of 5")
	assert_str(BotReport.markdown(_batch())).is_equal(report)


# FT: FT-TST-022
func test_the_report_counts_losses_and_fled_encounters_apart() -> void:
	var rows: Array[Dictionary] = [
		{
			"id": 0,
			"scenario": "enemy_wave",
			"result": "won",
			"lost": false,
			"fled": false,
			"s": 60.0
		},
		{"id": 1, "scenario": "rescue", "result": "fled", "lost": false, "fled": true, "s": 30.0},
		{
			"id": 2,
			"scenario": "enemy_wave",
			"result": "lost",
			"lost": true,
			"fled": false,
			"s": 20.0
		},
	]
	var run: Dictionary = {
		"profile": "average",
		"difficulty": "easy",
		"outcome": "loss",
		"run_s": 300.0,
		"encounters": rows
	}
	var report: String = BotReport.markdown([run])
	assert_str(report).contains("| 3 | 1 | 33.3 % | 1 | 33.3 % |")
	assert_str(report).contains("| enemy_wave | 2 | 1 | 50.0 % | 0 | 0.0 % |")
