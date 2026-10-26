class_name BotReport
extends RefCounted
## The bot batch's markdown report (FT-TST-022, FT-MIS-009, FT-MIS-037, FT-GEN-011): per
## difficulty and crew profile, the per-encounter ship-loss rate (fled encounters counted
## apart), per scenario too, the run length in minutes and the share of runs that survive
## at least 3 of 5 encounters. Built from BotRun records only, with no clock or path in it, so
## the same runs give the same text.

## The targets the figures are read against.
const LOSS_LO: float = 0.05
const LOSS_HI: float = 0.10
const RUN_MIN_LO: float = 20.0
const RUN_MIN_HI: float = 40.0
const SURVIVE_ENCOUNTERS: int = 3


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
			"| difficulty / crew | runs | won | lost | stalled | encounters | ship lost | "
			+ "loss rate | fled | fled rate | run length min (mean, median) | survive 3 of 5 |"
		)
	)
	out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for key: String in keys:
		out.append(_row(key, groups[key]))
	out.append("")
	var targets: String = (
		"Targets: loss rate %d to %d %% per encounter for an average crew (FT-MIS-009), "
		+ "run length %d to %d min (FT-GEN-011), Easy with a novice crew survives at least 3 "
		+ "of 5 encounters in most runs (FT-MIS-037). Fled encounters are not losses and are "
		+ "counted apart (FT-MIS-010).\n"
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
	var minutes: Array[float] = []
	var survived: int = 0
	for r: Dictionary in runs:
		counts[r["outcome"]] = int(counts.get(r["outcome"], 0)) + 1
		if r["outcome"] == "win":
			minutes.append(float(r["run_s"]) / 60.0)
		survived += 1 if _survived(r) >= SURVIVE_ENCOUNTERS else 0
	return (
		"| %s | %d | %d | %d | %d | %d | %d | %s | %d | %s | %s | %s |"
		% [
			key,
			runs.size(),
			counts["win"],
			counts["loss"],
			counts["stalled"],
			rows.size(),
			lost,
			_pct(lost, rows.size()),
			fled,
			_pct(fled, rows.size()),
			_length(minutes),
			_pct(survived, runs.size()),
		]
	)


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


## Encounters the ship came through: not lost (a fled encounter is survived).
static func _survived(run: Dictionary) -> int:
	var n: int = 0
	for e: Dictionary in run["encounters"]:
		if not e["lost"] and e["result"] != "active" and e["result"] != "pending":
			n += 1
	return n


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
