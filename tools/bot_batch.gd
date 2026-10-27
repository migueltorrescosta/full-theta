extends SceneTree
## The headless bot batch (FT-TST-022, FT-MIS-009, FT-MIS-037, FT-GEN-011): plays whole runs
## of the director's run with scripted crews, without a network, and writes a markdown
## report of the per-encounter loss rate, fled encounters, encounters per run (4 to 6, Q4),
## run length (all runs, won and lost apart) and the share of runs that survive 60 % of
## their encounters. Run it as a transient unit (tools/bot_batch.sh).
##   godot --headless --path . -s res://tools/bot_batch.gd -- [flags]
##   --profiles average,novice   crews [average,novice]
##   --difficulties easy,normal  presets [easy,normal]
##   --runs N                    runs per profile and difficulty [40]
##   --seed N                    first seed; run i uses seed + i [1]
##   --cap-min M                 sim minutes after which a run counts as stalled [120]
##   --out DIR                   report.md and runs.jsonl go here [build/bot_batch]
## The report holds no clock, so the same flags give the same file; progress lines
## (with wall time) go to stdout.


func _init() -> void:
	var opts: Dictionary = {
		"profiles": "average,novice",
		"difficulties": "easy,normal",
		"runs": "40",
		"seed": "1",
		"cap-min": "120",
		"out": "build/bot_batch",
	}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i + 1 < args.size():
		opts[args[i].trim_prefix("--")] = args[i + 1]
		i += 2
	var out_dir: String = opts["out"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var defs: DefLibrary = DefLibrary.new()
	var results: Array[Dictionary] = []
	var lines: FileAccess = FileAccess.open(out_dir.path_join("runs.jsonl"), FileAccess.WRITE)
	var started: int = Time.get_ticks_msec()
	for difficulty: String in String(opts["difficulties"]).split(","):
		for profile: String in String(opts["profiles"]).split(","):
			for n: int in int(opts["runs"]):
				var r: Dictionary = BotRun.play(
					defs, profile, difficulty, int(opts["seed"]) + n, float(opts["cap-min"]) * 60.0
				)
				results.append(r)
				lines.store_line(JSON.stringify(r))
				lines.flush()
				print(
					(
						"%s %s #%d %s %.0fs sim, %d encounters (%d s wall)"
						% [
							difficulty,
							profile,
							n,
							r["outcome"],
							r["run_s"],
							(r["encounters"] as Array).size(),
							(Time.get_ticks_msec() - started) / 1000
						]
					)
				)
	var report: FileAccess = FileAccess.open(out_dir.path_join("report.md"), FileAccess.WRITE)
	report.store_string(BotReport.markdown(results))
	report.close()
	print("bot_batch: %d runs, report in %s" % [results.size(), out_dir])
	quit()
