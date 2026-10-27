extends GdUnitTestSuite
## The bot batch (FT-TST-022, FT-GEN-009): a small run of scripted crews with no game master
## and no network writes a report with the loss rate, fled encounters apart and run length,
## and the same seeds give the same report.


func _batch() -> Array[Dictionary]:
	var defs: DefLibrary = DefLibrary.new()
	var out: Array[Dictionary] = []
	for profile: String in BotProfiles.NAMES:
		for n: int in 2:
			out.append(BotRun.play(defs, profile, "easy", 1 + n, 1500.0))
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
	assert_str(report).contains("run length min, all runs")
	assert_str(report).contains("won runs")
	assert_str(report).contains("lost runs")
	assert_str(report).contains("encounters per run")
	assert_str(report).contains("survive 60 %")
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


# FT: FT-TST-022, FT-GEN-011
# Q4: the run length is averaged over all runs and over the won and lost ones apart, and the
# encounters per run (4 to 6) are counted.
func test_the_report_averages_run_length_over_all_runs_and_counts_encounters() -> void:
	var enc: Dictionary = {"scenario": "rescue", "result": "won", "lost": false, "fled": false}
	var lost_enc: Dictionary = {"scenario": "rescue", "result": "lost", "lost": true, "fled": false}
	var runs: Array[Dictionary] = [
		{
			"profile": "average",
			"difficulty": "easy",
			"outcome": "win",
			"run_s": 1200.0,
			"encounters": [enc, enc, enc, enc]
		},
		{
			"profile": "average",
			"difficulty": "easy",
			"outcome": "win",
			"run_s": 2400.0,
			"encounters": [enc, enc, enc, enc, enc, enc]
		},
		{
			"profile": "average",
			"difficulty": "easy",
			"outcome": "loss",
			"run_s": 600.0,
			"encounters": [enc, lost_enc]
		},
	]
	var report: String = BotReport.markdown(runs)
	# All runs: (20 + 40 + 10) / 3 = 23.3, median 20; won: 30, 40 (median of two taken high);
	# lost: 10. Encounters per run: 12 over 3 runs, 2 to 6. Survived 60 %: two of three runs.
	assert_str(report).contains("| 4.0 (2 to 6) | 12 |")
	assert_str(report).contains("| 23.3, 20.0 | 30.0, 40.0 | 10.0, 10.0 | 66.7 % |")
