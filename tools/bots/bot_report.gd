class_name BotReport
extends RefCounted
## The bot batch's markdown report (FT-TST-022, FT-MIS-009, FT-MIS-037, FT-GEN-011): per
## difficulty and crew profile, the per-encounter ship-loss rate (fled encounters counted
## apart), per scenario too, the encounters per run (the director picks 4 to 6, Q4), the run
## length in minutes over all runs and over the won and the lost ones apart, and the share of
## runs that survive at least 60 % of their encounters. Built from BotRun records only, with
## no clock or path in it, so the same runs give the same text.

## The targets the figures are read against.
const LOSS_LO: float = 0.05
const LOSS_HI: float = 0.10
const RUN_MIN_LO: float = 20.0
const RUN_MIN_HI: float = 40.0
## A run counts as survived when the ship came through at least this share of its encounters
## (FT-MIS-037 with a variable run length, Q4 owner 2026-10-26).
const SURVIVE_SHARE: float = 0.6


## `results` are BotRun.play records.
static func markdown(results: Array[Dictionary]) -> String:
	var groups: Dictionary = {}
	for r: Dictionary in results:
		var key: String = "%s / %s" % [r["difficulty"], r["profile"]]
		(groups.get_or_add(key, []) as Array).append(r)
	var keys: Array = groups.keys()
	keys.sort()
	var out: PackedStringArray = PackedStringArray()
	out.append("# Bot batch report\n")
	out.append("Runs: %d. Encounters played: %d.\n" % [results.size(), _encounters(results).size()])
	out.append(
		(
			"| difficulty / crew | runs | won | lost | stalled | encounters per run (mean, range) "
			+ "| encounters | ship lost | loss rate | fled | fled rate "
			+ "| run length min, all runs (mean, median) | won runs (mean, median) "
			+ "| lost runs (mean, median) | survive 60 % |"
		)
	)
	out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for key: String in keys:
		out.append(_row(key, groups[key]))
	out.append("")
	var targets: String = (
		"Targets: loss rate %d to %d %% per encounter for an average crew (FT-MIS-009), "
		+ "run length %d to %d min (FT-GEN-011, the all-runs column; stalled runs count at "
		+ "the cap), Easy with a novice crew survives at least 60 %% of its encounters in most "
		+ "runs (FT-MIS-037). Fled encounters are not losses and are counted apart "
		+ "(FT-MIS-010).\n"
	)
	out.append(targets % [LOSS_LO * 100, LOSS_HI * 100, RUN_MIN_LO, RUN_MIN_HI])
	for key: String in keys:
		out.append(_by_scenario(key, groups[key]))
	return "\n".join(out) + "\n"


## Encounters of the records, with the run's profile and difficulty.
static func _encounters(runs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in runs:
		for e: Dictionary in r["encounters"]:
			out.append(e)
	return out


static func _row(key: String, runs: Array) -> String:
	var rows: Array[Dictionary] = _encounters(runs)
	var lost: int = _count(rows, "lost")
	var fled: int = _count(rows, "fled")
	var counts: Dictionary = {"win": 0, "loss": 0, "stalled": 0}
	var all: Array[float] = []
	var won: Array[float] = []
	var lost_runs: Array[float] = []
	var survived: int = 0
	for r: Dictionary in runs:
		counts[r["outcome"]] = int(counts.get(r["outcome"], 0)) + 1
		var minutes: float = float(r["run_s"]) / 60.0
		all.append(minutes)
		if r["outcome"] == "win":
			won.append(minutes)
		elif r["outcome"] == "loss":
			lost_runs.append(minutes)
		survived += 1 if _survived_share(r) >= SURVIVE_SHARE else 0
	return (
		"| %s | %d | %d | %d | %d | %s | %d | %d | %s | %d | %s | %s | %s | %s | %s |"
		% [
			key,
			runs.size(),
			counts["win"],
			counts["loss"],
			counts["stalled"],
			_per_run(runs),
			rows.size(),
			lost,
			_pct(lost, rows.size()),
			fled,
			_pct(fled, rows.size()),
			_length(all),
			_length(won),
			_length(lost_runs),
			_pct(survived, runs.size()),
		]
	)


## Encounters per run as "mean (fewest to most)".
static func _per_run(runs: Array) -> String:
	if runs.is_empty():
		return "-"
	var fewest: int = 1 << 30
	var most: int = 0
	var total: int = 0
	for r: Dictionary in runs:
		var n: int = (r["encounters"] as Array).size()
		fewest = mini(fewest, n)
		most = maxi(most, n)
		total += n
	return "%.1f (%d to %d)" % [float(total) / runs.size(), fewest, most]


static func _by_scenario(key: String, runs: Array) -> String:
	var by: Dictionary = {}
	for e: Dictionary in _encounters(runs):
		(by.get_or_add(e["scenario"], []) as Array).append(e)
	var names: Array = by.keys()
	names.sort()
	var out: PackedStringArray = PackedStringArray(
		[
			"### %s\n" % key,
			"| scenario | encounters | ship lost | loss rate | fled | fled rate |",
			"|---|---|---|---|---|---|"
		]
	)
	for n: String in names:
		var rows: Array = by[n]
		var lost: int = _count(rows, "lost")
		var fled: int = _count(rows, "fled")
		out.append(
			(
				"| %s | %d | %d | %s | %d | %s |"
				% [n, rows.size(), lost, _pct(lost, rows.size()), fled, _pct(fled, rows.size())]
			)
		)
	out.append("")
	return "\n".join(out)


## The share of the run's encounters the ship came through: not lost (a fled encounter is
## survived), over every encounter of the run; 0 for a run with none.
static func _survived_share(run: Dictionary) -> float:
	var rows: Array = run["encounters"]
	if rows.is_empty():
		return 0.0
	var n: int = 0
	for e: Dictionary in rows:
		if not e["lost"] and e["result"] != "active" and e["result"] != "pending":
			n += 1
	return float(n) / rows.size()


static func _count(rows: Array, field: String) -> int:
	var n: int = 0
	for e: Dictionary in rows:
		n += 1 if e[field] else 0
	return n


static func _pct(part: int, whole: int) -> String:
	return "-" if whole == 0 else "%.1f %%" % (100.0 * part / whole)


static func _length(minutes: Array[float]) -> String:
	if minutes.is_empty():
		return "-"
	minutes.sort()
	var total: float = 0.0
	for m: float in minutes:
		total += m
	return "%.1f, %.1f" % [total / minutes.size(), minutes[minutes.size() / 2]]
