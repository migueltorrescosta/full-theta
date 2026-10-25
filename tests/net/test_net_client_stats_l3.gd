extends GdUnitTestSuite
## L3: a client's snapshot arrival report reaches the server's age statistics and the
## session log (D199, FT-NET-046).

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


# FT: FT-NET-046
func test_client_reports_reach_the_server_age_stats_and_the_session_log() -> void:
	var path: String = "user://logs_test/l3.jsonl"
	DirAccess.remove_absolute(path)
	var server: NetServer = h.server()
	assert_int(server.start_session_log(path)).is_equal(OK)
	var c: NetClient = await h.joined(server, "tab", "tactical")
	c.user_agent = "TestAgent/1"
	var got: Callable = func() -> bool:
		return (
			not server.age_stats.clients.is_empty()
			and (server.age_stats.total_summary()["pooled"] as Dictionary)["n"] > 5
		)
	# The report goes out every 2 s; wait for the first.
	assert_bool(await h.until(got, 6000)).is_true()
	var total: Dictionary = server.age_stats.total_summary()
	var line: Dictionary = (total["clients"] as Array)[0]
	assert_str(line["ua"]).is_equal("TestAgent/1")
	# Same machine, same clock: ages are small and never far below zero.
	assert_int((total["pooled"] as Dictionary)["age_p99_ms"]).is_less(1000)
	server._next_stats_us = 0
	await h.wait(100)
	server.session_log.close()
	var text: String = FileAccess.get_file_as_string(path)
	assert_bool(text.contains('"kind":"snapshot_age"')).is_true()
	DirAccess.remove_absolute(path)


# FT: FT-NET-046
# The server cuts the user agent to 200 bytes, takes at most 400 pairs and rate-limits
# the report like the other requests (D199, D207).
func test_stats_report_is_clipped_capped_and_rate_limited() -> void:
	var server: NetServer = h.server()
	assert_int(server.start_session_log("user://logs_test/l3_cap.jsonl")).is_equal(OK)
	var c: NetClient = await h.joined(server, "tab", "tactical")
	var report: Callable = func(ua: String, n: int) -> void:
		c._send(
			NetProtocol.Type.CLIENT_STATS,
			{"sent_us": 1, "ua": ua, "pairs": PackedInt64Array(range(2 * n))}
		)
	report.call("a".repeat(5000), 0)
	var cut: Callable = func() -> bool:
		return (
			not server.age_stats.clients.is_empty()
			and (server.age_stats.clients.values()[0] as SnapshotAgeStats.Client).user_agent != ""
		)
	await h.until(cut, 3000)
	for client: SnapshotAgeStats.Client in server.age_stats.clients.values():
		assert_int(client.user_agent.length()).is_equal(NetProtocol.MAX_UA_BYTES)
		client.user_agent = ""
	report.call("b", NetProtocol.MAX_STATS_PAIRS + 1)
	await h.wait(200)
	for client: SnapshotAgeStats.Client in server.age_stats.clients.values():
		assert_str(client.user_agent).is_empty()
	for i: int in 300:
		report.call("c", 0)
	var limited: Callable = func() -> bool:
		return server.session.rejections.get(CommandGate.RATE_LIMITED, 0) > 0
	assert_bool(await h.until(limited, 3000)).is_true()
	server.session_log.close()
	DirAccess.remove_absolute("user://logs_test/l3_cap.jsonl")
