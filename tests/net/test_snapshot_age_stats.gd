extends GdUnitTestSuite
## SnapshotAgeStats and SessionLog (D199): percentiles, the clock offset, the log file.

const MS: int = 1000


## Stamps for seq 1..n: capture at 1_000_000 + 33 ms * seq (server unix us).
func _stamp(seq: int) -> int:
	return 1_000_000 + 33 * MS * seq


# FT: FT-NET-046
func test_age_is_arrival_minus_capture_with_the_clock_offset_removed() -> void:
	var stats: SnapshotAgeStats = SnapshotAgeStats.new()
	var c: SnapshotAgeStats.Client = stats.client_for(7, "tab", "web")
	# The client's clock runs 5 s ahead. Snapshots arrive 20 ms after capture except
	# the last, 120 ms. The report is sent at client 6_000_000 and received 2 ms later.
	var skew: int = 5_000_000
	var pairs: PackedInt64Array = PackedInt64Array()
	for seq: int in range(1, 100):
		pairs.append_array([seq, _stamp(seq) + 20 * MS + skew])
	pairs.append_array([100, _stamp(100) + 120 * MS + skew])
	stats.report(c, 6_000_000 + skew, 6_000_000 + 2 * MS, pairs, _stamp)
	# offset = rx - sent = skew-corrected + 2 ms uplink, so every age reads 2 ms high.
	var w: Dictionary = stats.window_summary()
	assert_int((w["pooled"] as Dictionary)["n"]).is_equal(100)
	assert_int((w["pooled"] as Dictionary)["age_p50_ms"]).is_between(21, 24)
	assert_int((w["pooled"] as Dictionary)["age_p99_ms"]).is_between(21, 24)
	assert_int((w["pooled"] as Dictionary)["age_p99_ms"] as int).is_less(100)
	var line: Dictionary = (w["clients"] as Array)[0]
	assert_str(line["name"]).is_equal("tab")
	assert_str(line["client"]).is_equal("web")
	# The late 100th snapshot opens a 133 ms gap, the 99th percentile of 99 gaps.
	assert_int(line["gap_p99_ms"]).is_between(130, 136)
	# The window resets; the totals keep everything.
	assert_int((stats.window_summary()["pooled"] as Dictionary)["n"]).is_equal(0)
	assert_int((stats.total_summary()["pooled"] as Dictionary)["n"]).is_equal(100)


# FT: FT-NET-046
func test_unknown_stamps_are_counted_not_measured_and_pooling_spans_clients() -> void:
	var stats: SnapshotAgeStats = SnapshotAgeStats.new()
	var a: SnapshotAgeStats.Client = stats.client_for(1, "a", "desktop")
	var b: SnapshotAgeStats.Client = stats.client_for(2, "b", "web")
	stats.report(
		a, 0, 0, PackedInt64Array([1, _stamp(1) + 10 * MS, 2, _stamp(2) + 10 * MS]), _stamp
	)
	stats.report(
		b,
		0,
		0,
		PackedInt64Array([1, _stamp(1) + 90 * MS, 99999, 5]),
		func(s: int) -> int: return 0 if s == 99999 else _stamp(s)
	)
	assert_int(b.unmatched).is_equal(1)
	var w: Dictionary = stats.window_summary()
	assert_int((w["pooled"] as Dictionary)["n"]).is_equal(3)
	assert_int((w["pooled"] as Dictionary)["age_p99_ms"]).is_between(90, 92)
	assert_int((w["clients"] as Array).size()).is_equal(2)


# FT: FT-NET-046
func test_session_log_appends_json_lines_and_a_summary_with_counters() -> void:
	var path: String = "user://logs_test/session.jsonl"
	DirAccess.remove_absolute(path)
	var log: SessionLog = SessionLog.open(path)
	assert_object(log).is_not_null()
	log.event("start", {"port": 47801})
	log.count("chip", 2)
	log.count("chip")
	log.close({"extra": 1})
	log.event("late")
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).strip_edges().split("\n")
	assert_int(lines.size()).is_equal(2)
	var first: Dictionary = JSON.parse_string(lines[0])
	assert_str(first["kind"]).is_equal("start")
	assert_int(int(first["port"])).is_equal(47801)
	var last: Dictionary = JSON.parse_string(lines[1])
	assert_str(last["kind"]).is_equal("summary")
	assert_int(int(last["counters"]["chip"])).is_equal(3)
	assert_int(int(last["extra"])).is_equal(1)
	DirAccess.remove_absolute(path)
