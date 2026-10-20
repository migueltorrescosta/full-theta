extends GdUnitTestSuite
## L3/L4-style (T046): the Host flow and the orphan rejoin with a real server child
## process (this executable, headless, on loopback). Each test spawns its own child on a
## free port (--port 0) with its own pid, token and log files, and kills it afterwards.
## The children bind 127.0.0.1 (HostSession.Options.bind) and run without the LAN
## beacon. Linux only for the orphan tests (/proc).

const PLAYER: int = M1Encounter.PLAYER_SHIP
## A cold child start on 2 loaded cores can take several seconds.
const TIMEOUT_MS: int = 30_000

var _hosts: Array[HostSession] = []
var _clients: Array[NetClient] = []
var _pids: Array[int] = []
var _pid_file: String
var _token_file: String
var _log_file: String


func before_test() -> void:
	var tag: String = "%d_%d" % [OS.get_process_id(), randi()]
	_pid_file = "user://host_test_flow_pid_%s.json" % tag
	_token_file = "user://host_test_flow_token_%s.json" % tag
	_log_file = ProjectSettings.globalize_path("user://host_test_flow_%s.log" % tag)


func after_test() -> void:
	for c: NetClient in _clients:
		c.drop()
	_clients.clear()
	for h: HostSession in _hosts:
		h.stop()
	_hosts.clear()
	for pid: int in _pids:
		if OrphanCheck.process_alive(pid):
			OS.kill(pid)
	_pids.clear()
	ServerPidFile.remove(_pid_file)
	SessionTokenFile.remove(_token_file)
	if FileAccess.file_exists(_log_file):
		DirAccess.remove_absolute(_log_file)


## A HostSession whose child logs to _log_file and writes _pid_file.
func _host_session(idle_exit_min: float = 1.0) -> HostSession:
	var h: HostSession = HostSession.new("captain")
	h.token_file = _token_file
	h.launcher.pid_file = _pid_file
	h.launcher.engine_args = ["--log-file", _log_file]
	var options: HostSession.Options = HostSession.Options.new("127.0.0.1")
	options.port = 0
	options.idle_exit_min = idle_exit_min
	options.beacon = false
	_hosts.append(h)
	assert_int(h.host(options)).is_equal(OK)
	_pids.append(h.launcher.pid)
	return h


func _until(cond: Callable, timeout_ms: int = TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		for h: HostSession in _hosts:
			h.poll()
		for c: NetClient in _clients:
			c.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _log() -> String:
	return FileAccess.get_file_as_string(_log_file) if FileAccess.file_exists(_log_file) else ""


## True once `pid` has exited and been reaped. OS.kill() reaps a child of this process
## itself (it waits for it), so after a kill /proc is the whole answer; asking
## is_process_running() then logs "not a child of the calling process". Only a child
## that exited by itself still needs reaping to leave /proc.
func _gone(pid: int) -> bool:
	if not OrphanCheck.process_alive(pid):
		return true
	return not OS.is_process_running(pid) and not OrphanCheck.process_alive(pid)


## True once the host joined; on a failed start or join the failure names the reason.
func _joined(h: HostSession) -> bool:
	await _until(func() -> bool: return h.is_joined() or h.state == h.State.FAILED)
	assert_str(h.error).is_empty()
	return h.is_joined()


# FT: FT-NET-001, FT-NET-003, FT-M1-002
# Host spawns this executable as a headless server child on localhost, the host client
# connects and the server marks it host (it presented the secret from the environment,
# D127), the token is stored; stopping kills the child and removes the pid and token
# files.
func test_host_spawns_a_headless_child_and_stop_kills_it() -> void:
	var h: HostSession = _host_session()
	assert_bool(await _joined(h)).is_true()
	assert_str(h.error).is_empty()
	assert_int(h.state).is_equal(HostSession.State.JOINED)
	var pid: int = h.launcher.pid
	if OS.get_name() == "Linux":
		var args: PackedStringArray = OrphanCheck.read_cmdline(pid)
		assert_str(args[0]).is_equal(OS.get_executable_path())
		assert_bool(args.has("--headless")).is_true()
		assert_str(args[args.find("--bind") + 1]).is_equal("127.0.0.1")
	var info: ServerPidFile = ServerPidFile.load_from(_pid_file)
	assert_int(info.pid).is_equal(pid)
	assert_int(info.port).is_equal(h.launcher.port)
	assert_int(info.port).is_greater(0)
	var marked: Callable = func() -> bool:
		return _log().contains("server: host is session %d" % h.client.session_id)
	assert_bool(await _until(marked)).is_true()
	assert_bool(h.client.welcome["host"]).is_true()
	var stored: SessionTokenFile = SessionTokenFile.load_from(_token_file)
	assert_str(stored.token).is_equal(h.client.token)
	assert_int(stored.port).is_equal(info.port)
	assert_str(stored.host_secret).is_equal(h.launcher.host_secret)
	# The joined host makes the session active in the pid file.
	var active: Callable = func() -> bool:
		var f: ServerPidFile = ServerPidFile.load_from(_pid_file)
		return f != null and f.session_active
	assert_bool(await _until(active)).is_true()
	h.stop()
	assert_bool(FileAccess.file_exists(_pid_file)).is_false()
	assert_bool(FileAccess.file_exists(_token_file)).is_false()
	assert_bool(await _until(_gone.bind(pid))).is_true()


# FT: FT-NET-003
# The real child exits by itself after --idle-exit-min without connections (here
# 0.03 min, 1.8 s) and removes its pid file on the way out.
func test_child_exits_after_idle_minutes_and_removes_its_pid_file() -> void:
	var h: HostSession = _host_session(0.03)
	h.state = HostSession.State.IDLE  # don't connect: the server stays empty
	var ready: Callable = func() -> bool: return FileAccess.file_exists(_pid_file)
	assert_bool(await _until(ready)).is_true()
	var pid: int = h.launcher.pid
	var gone: Callable = func() -> bool: return not OS.is_process_running(pid)
	assert_bool(await _until(gone)).is_true()
	assert_bool(FileAccess.file_exists(_pid_file)).is_false()
	assert_str(_log()).contains("server: no connected players for")


# FT: FT-NET-003
# TECH-8: the host client crashes mid-session (its HostSession is dropped without
# stop, the child keeps running as an orphan, another player stays). On start the
# client finds the orphan, offers to rejoin, and on REJOIN reconnects with the stored
# token: the same session, ship and pick, as host. Stop then terminates it.
func test_relaunched_host_rejoins_its_orphan_on_the_same_pick() -> void:
	if OS.get_name() != "Linux":
		return
	var h: HostSession = _host_session()
	assert_bool(await _joined(h)).is_true()
	h.client.pick(PLAYER, "helm")
	var picked: Callable = func() -> bool: return h.client.stats["fulls"] >= 1
	assert_bool(await _until(picked)).is_true()
	var other: NetClient = NetClient.new()
	other.connect_to(LanBrowser.ws_url("127.0.0.1", h.launcher.port))
	_clients.append(other)
	assert_bool(await _until(other.is_welcomed)).is_true()
	var session_id: int = h.client.session_id
	var pid: int = h.launcher.pid
	var active: Callable = func() -> bool:
		var f: ServerPidFile = ServerPidFile.load_from(_pid_file)
		return f != null and f.session_active
	assert_bool(await _until(active)).is_true()
	# Crash: the socket drops, nothing is cleaned up.
	h.client.drop()
	_hosts.erase(h)
	h = null
	assert_bool(OrphanCheck.process_alive(pid)).is_true()
	var offered: Array = []
	var choose: Callable = func(c: OrphanCheck) -> HostSession.Answer:
		offered.append(c.action)
		return HostSession.Answer.REJOIN
	var again: HostSession = HostSession.check_orphan(choose, _pid_file, _token_file)
	assert_array(offered).is_equal([OrphanCheck.Action.OFFER_REJOIN])
	assert_object(again).is_not_null()
	_hosts.append(again)
	assert_bool(await _joined(again)).is_true()
	assert_bool(again.client.welcome["resumed"]).is_true()
	assert_int(again.client.session_id).is_equal(session_id)
	assert_int(again.client.welcome["ship"]).is_equal(PLAYER)
	assert_str(again.client.welcome["entry"]).is_equal("helm")
	# Host again by the stored secret (D127), from Welcome. Not from the child's "host
	# is session" log line: when the drop and the rejoin land in one server frame,
	# the host never reads as gone and the line isn't printed twice.
	assert_bool(again.client.welcome["host"]).is_true()
	assert_bool(other.is_welcomed()).is_true()
	assert_bool(OrphanCheck.process_alive(pid)).is_true()
	again.stop()
	assert_bool(await _until(_gone.bind(pid))).is_true()
	assert_bool(FileAccess.file_exists(_pid_file)).is_false()


# FT: FT-NET-003
# An orphan without a session is terminated without asking; one with a session is
# terminated only when the player chooses, and LEAVE leaves it running.
func test_orphan_is_terminated_only_without_a_session_or_by_choice() -> void:
	if OS.get_name() != "Linux":
		return
	var asked: Array = []
	var never: Callable = func(c: OrphanCheck) -> HostSession.Answer:
		asked.append(c.action)
		return HostSession.Answer.LEAVE
	# No session: nobody ever joined.
	var idle: HostSession = _host_session()
	idle.state = HostSession.State.IDLE
	var ready: Callable = func() -> bool: return FileAccess.file_exists(_pid_file)
	assert_bool(await _until(ready)).is_true()
	var pid: int = idle.launcher.pid
	_hosts.erase(idle)
	assert_object(HostSession.check_orphan(never, _pid_file, _token_file)).is_null()
	assert_array(asked).is_empty()
	assert_bool(await _until(_gone.bind(pid))).is_true()
	assert_bool(FileAccess.file_exists(_pid_file)).is_false()
	# With a session: LEAVE keeps it, TERMINATE kills it.
	var h: HostSession = _host_session()
	assert_bool(await _joined(h)).is_true()
	h.client.pick(PLAYER, "weapons")
	var active: Callable = func() -> bool:
		var f: ServerPidFile = ServerPidFile.load_from(_pid_file)
		return f != null and f.session_active
	assert_bool(await _until(active)).is_true()
	pid = h.launcher.pid
	_hosts.erase(h)
	var leave: Callable = func(_c: OrphanCheck) -> HostSession.Answer:
		return HostSession.Answer.LEAVE
	assert_object(HostSession.check_orphan(leave, _pid_file, _token_file)).is_null()
	assert_bool(OrphanCheck.process_alive(pid)).is_true()
	var terminate: Callable = func(_c: OrphanCheck) -> HostSession.Answer:
		return HostSession.Answer.TERMINATE
	assert_object(HostSession.check_orphan(terminate, _pid_file, _token_file)).is_null()
	assert_bool(await _until(_gone.bind(pid))).is_true()
	assert_bool(FileAccess.file_exists(_pid_file)).is_false()
	assert_bool(FileAccess.file_exists(_token_file)).is_false()
	h.client.drop()
