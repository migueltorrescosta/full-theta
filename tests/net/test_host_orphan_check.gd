extends GdUnitTestSuite
## OrphanCheck: what a starting client does about a server left running by a
## crashed host client (FT-NET-003, TECH-8).

const PID_FILE: String = "user://host_test_orphan_pid.json"
const TOKEN_FILE: String = "user://host_test_orphan_token.json"

var _children: Array[int] = []


func after_test() -> void:
	for pid: int in _children:
		if OrphanCheck.process_alive(pid):
			OS.kill(pid)
	_children.clear()
	ServerPidFile.remove(PID_FILE)
	SessionTokenFile.remove(TOKEN_FILE)


func _record(session: bool) -> ServerPidFile:
	var info: ServerPidFile = ServerPidFile.for_this_process(47800, "127.0.0.1")
	info.session_active = session
	return info


## Starts a process that looks like our server in /proc (argv[0] is our
## executable, "--server" among the arguments) but only sleeps: one process,
## so killing it leaves nothing behind.
func _fake_server() -> int:
	var script: String = 'exec -a "$0" python3 -c "import time; time.sleep(30)" --server'
	var pid: int = OS.create_process("bash", ["-c", script, OS.get_executable_path()])
	_children.append(pid)
	var until: int = Time.get_ticks_msec() + 2000
	while not OrphanCheck.read_cmdline(pid).has("--server") and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	return pid


# FT: FT-NET-003
func test_decision_table() -> void:
	var act: Dictionary = OrphanCheck.Action
	var idn: Dictionary = OrphanCheck.Identity
	var idle: ServerPidFile = _record(false)
	var busy: ServerPidFile = _record(true)
	# [file, alive, identity, has_token, expected]
	var rows: Array = [
		[null, true, idn.OURS, true, act.NONE],
		[idle, false, idn.OURS, true, act.CLEAR_STALE],
		[busy, false, idn.OURS, true, act.CLEAR_STALE],
		[busy, true, idn.NOT_SERVER, true, act.CLEAR_STALE],
		[busy, true, idn.OTHER_INSTALL, true, act.LEAVE],
		[idle, true, idn.OTHER_INSTALL, false, act.LEAVE],
		[idle, true, idn.OURS, false, act.TERMINATE],
		[idle, true, idn.OURS, true, act.TERMINATE],
		[idle, true, idn.UNVERIFIED, false, act.OFFER_TERMINATE],
		[busy, true, idn.OURS, true, act.OFFER_REJOIN],
		[busy, true, idn.UNVERIFIED, true, act.OFFER_REJOIN],
		[busy, true, idn.OURS, false, act.OFFER_TERMINATE],
	]
	for row: Array in rows:
		var got: OrphanCheck.Action = OrphanCheck.decide(row[0], row[1], row[2], row[3])
		assert_int(got).override_failure_message("row %s gave %d" % [row, got]).is_equal(row[4])


func test_identify() -> void:
	var idn: Dictionary = OrphanCheck.Identity
	var srv: PackedStringArray = ["/opt/ft/ft", "--headless", "--", "--server"]
	assert_int(OrphanCheck.identify(srv, "/opt/ft/ft", "/opt/ft/ft")).is_equal(idn.OURS)
	assert_int(OrphanCheck.identify(srv, "/opt/ft/ft", "/home/ft2/ft")).is_equal(idn.OTHER_INSTALL)
	assert_int(OrphanCheck.identify(["/usr/bin/vim"], "/opt/ft/ft", "/opt/ft/ft")).is_equal(
		idn.NOT_SERVER
	)
	assert_int(OrphanCheck.identify(["/opt/ft/ft", "-e"], "/opt/ft/ft", "/opt/ft/ft")).is_equal(
		idn.NOT_SERVER
	)
	assert_int(OrphanCheck.identify([], "/opt/ft/ft", "/opt/ft/ft")).is_equal(idn.UNVERIFIED)


func test_split_cmdline() -> void:
	var raw: PackedByteArray = "a|--b|c d|".to_utf8_buffer()
	for i: int in range(raw.size()):
		if raw[i] == "|".unicode_at(0):
			raw[i] = 0
	assert_array(Array(OrphanCheck.split_cmdline(raw))).is_equal(["a", "--b", "c d"])
	assert_array(Array(OrphanCheck.split_cmdline("x".to_utf8_buffer()))).is_equal(["x"])
	assert_bool(OrphanCheck.split_cmdline(PackedByteArray()).is_empty()).is_true()


func test_no_pid_file_means_nothing_to_do() -> void:
	var check: OrphanCheck = OrphanCheck.inspect(PID_FILE, TOKEN_FILE)
	assert_int(check.action).is_equal(OrphanCheck.Action.NONE)
	assert_bool(check.apply_automatic()).is_false()


# FT: FT-NET-003
func test_a_dead_pid_is_cleared_without_killing_anything() -> void:
	var pid: int = OS.create_process("true", [])
	var until: int = Time.get_ticks_msec() + 2000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	var info: ServerPidFile = _record(true)
	info.pid = pid
	info.save(PID_FILE)
	var check: OrphanCheck = OrphanCheck.inspect(PID_FILE, TOKEN_FILE)
	assert_int(check.action).is_equal(OrphanCheck.Action.CLEAR_STALE)
	assert_bool(check.apply_automatic()).is_false()
	assert_bool(FileAccess.file_exists(PID_FILE)).is_false()


# FT: FT-NET-003
func test_a_reused_pid_is_not_killed() -> void:
	if OS.get_name() != "Linux":
		return
	var pid: int = OS.create_process("sleep", ["30"])
	_children.append(pid)
	var until: int = Time.get_ticks_msec() + 2000
	while not OrphanCheck.read_cmdline(pid).has("30") and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	var info: ServerPidFile = _record(false)
	info.pid = pid
	info.save(PID_FILE)
	var check: OrphanCheck = OrphanCheck.inspect(PID_FILE, TOKEN_FILE)
	assert_int(check.action).is_equal(OrphanCheck.Action.CLEAR_STALE)
	check.apply_automatic()
	assert_bool(OrphanCheck.process_alive(pid)).is_true()


# FT: FT-NET-003
func test_an_idle_orphan_is_terminated() -> void:
	if OS.get_name() != "Linux":
		return
	var pid: int = _fake_server()
	var info: ServerPidFile = _record(false)
	info.pid = pid
	info.save(PID_FILE)
	var check: OrphanCheck = OrphanCheck.inspect(PID_FILE, TOKEN_FILE)
	assert_int(check.action).is_equal(OrphanCheck.Action.TERMINATE)
	assert_bool(check.apply_automatic()).is_false()
	assert_bool(FileAccess.file_exists(PID_FILE)).is_false()
	var until: int = Time.get_ticks_msec() + 2000
	while OrphanCheck.process_alive(pid) and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	assert_bool(OrphanCheck.process_alive(pid)).is_false()


# FT: FT-NET-003
func test_an_orphan_with_a_session_offers_rejoin_with_the_stored_token() -> void:
	if OS.get_name() != "Linux":
		return
	var pid: int = _fake_server()
	var info: ServerPidFile = _record(true)
	info.pid = pid
	info.save(PID_FILE)
	SessionTokenFile.make("tok", "127.0.0.1", info.port).save(TOKEN_FILE)
	var check: OrphanCheck = OrphanCheck.inspect(PID_FILE, TOKEN_FILE)
	assert_int(check.action).is_equal(OrphanCheck.Action.OFFER_REJOIN)
	assert_str(check.token.token).is_equal("tok")
	assert_bool(check.apply_automatic()).is_true()
	assert_bool(OrphanCheck.process_alive(pid)).is_true()
	# A token for another server's port can't rejoin this one.
	SessionTokenFile.make("tok", "127.0.0.1", info.port + 2).save(TOKEN_FILE)
	check = OrphanCheck.inspect(PID_FILE, TOKEN_FILE)
	assert_int(check.action).is_equal(OrphanCheck.Action.OFFER_TERMINATE)
	# The player chooses to terminate.
	check.terminate()
	assert_bool(FileAccess.file_exists(PID_FILE)).is_false()
	var until: int = Time.get_ticks_msec() + 2000
	while OrphanCheck.process_alive(pid) and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	assert_bool(OrphanCheck.process_alive(pid)).is_false()


# FT: FT-NET-003
# Pid reuse between the check and the player's answer: terminate() identifies the
# process again right before the kill, so an unrelated program that took the pid
# lives; only our server is killed.
func test_terminate_kills_only_our_server() -> void:
	if OS.get_name() != "Linux":
		return
	var server: int = _fake_server()
	var info: ServerPidFile = _record(true)
	info.pid = server
	info.save(PID_FILE)
	var check: OrphanCheck = OrphanCheck.inspect(PID_FILE, TOKEN_FILE)
	assert_int(check.action).is_equal(OrphanCheck.Action.OFFER_TERMINATE)
	var other: int = OS.create_process("sleep", ["30"])
	_children.append(other)
	check.info.pid = other  # the server exited and the pid went to `sleep`
	check.terminate()
	OS.delay_msec(200)
	assert_bool(OrphanCheck.process_alive(other)).is_true()
	assert_bool(FileAccess.file_exists(PID_FILE)).is_false()
	assert_bool(OrphanCheck.kill_if_ours(other, OS.get_executable_path())).is_false()
	assert_bool(OrphanCheck.kill_if_ours(server, "/another/install/full-theta")).is_false()
	assert_bool(OrphanCheck.process_alive(server)).is_true()
	assert_bool(OrphanCheck.kill_if_ours(server, OS.get_executable_path())).is_true()
	var until: int = Time.get_ticks_msec() + 2000
	while OrphanCheck.process_alive(server) and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	assert_bool(OrphanCheck.process_alive(server)).is_false()
