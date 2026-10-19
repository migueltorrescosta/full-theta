extends GdUnitTestSuite
## L3 (T046): the server process's services in one process over loopback: the pid file
## and idle exit (ServerLifecycle), the static HTTP server beside the WebSocket port,
## and the 64-connection session cap. Servers bind port 0.

const TIMEOUT_MS: int = 8000

var _servers: Array[NetServer] = []
var _clients: Array[NetClient] = []
var _pid_file: String
var _dir: String


func before_test() -> void:
	var tag: String = "%d_%d" % [OS.get_process_id(), randi()]
	_pid_file = "user://host_test_services_pid_%s.json" % tag
	_dir = ProjectSettings.globalize_path("user://host_test_services_www_%s" % tag)


func after_test() -> void:
	for c: NetClient in _clients:
		c.drop()
	_clients.clear()
	for s: NetServer in _servers:
		s.queue_free()
	_servers.clear()
	await get_tree().process_frame
	ServerPidFile.remove(_pid_file)
	if DirAccess.dir_exists_absolute(_dir):
		for f: String in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(f))
		DirAccess.remove_absolute(_dir)


func _server() -> NetServer:
	var s: NetServer = NetServer.new()
	var m1: M1Encounter = M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	assert_int(s.start(m1, 0, "127.0.0.1")).is_equal(OK)
	add_child(s)
	_servers.append(s)
	return s


func _client(server: NetServer) -> NetClient:
	var c: NetClient = NetClient.new()
	assert_int(c.connect_to("ws://127.0.0.1:%d" % server.port())).is_equal(OK)
	_clients.append(c)
	return c


func _until(cond: Callable, timeout_ms: int = TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		for c: NetClient in _clients:
			c.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _active() -> bool:
	var f: ServerPidFile = ServerPidFile.load_from(_pid_file)
	return f != null and f.session_active


# FT: FT-NET-003
# The server writes its pid file once it listens, marks the session active while a
# session exists (connected or within its grace), clears it when the last session
# expires, and removes the file when it shuts down cleanly.
func test_pid_file_follows_the_session_and_goes_on_clean_exit() -> void:
	var server: NetServer = _server()
	server.session.sessions.grace_us = 200_000
	var life: ServerLifecycle = ServerLifecycle.new(server, _pid_file, 0.0)
	add_child(life)
	var info: ServerPidFile = ServerPidFile.load_from(_pid_file)
	assert_int(info.pid).is_equal(OS.get_process_id())
	assert_int(info.port).is_equal(server.port())
	assert_str(info.bind).is_equal("127.0.0.1")
	assert_bool(info.session_active).is_false()
	var c: NetClient = _client(server)
	assert_bool(await _until(c.is_welcomed)).is_true()
	assert_bool(await _until(_active)).is_true()
	c.drop()
	assert_bool(await _until(func() -> bool: return not _active())).is_true()
	assert_bool(FileAccess.file_exists(_pid_file)).is_true()
	life.queue_free()
	await get_tree().process_frame
	assert_bool(FileAccess.file_exists(_pid_file)).is_false()


# FT: FT-NET-003
# With --idle-exit-min, the server exits once it has had no connection for that long
# on the wall clock, and not while a client is connected.
func test_idle_exit_waits_for_no_connections() -> void:
	var server: NetServer = _server()
	var life: ServerLifecycle = ServerLifecycle.new(server, _pid_file, 0.01)
	var exits: Array[int] = []
	life.on_idle_exit = func() -> void:
		exits.append(Time.get_ticks_msec())
		life.remove_pid_file()
	add_child(life)
	var c: NetClient = _client(server)
	assert_bool(await _until(c.is_welcomed)).is_true()
	await _until(func() -> bool: return false, 1200)
	assert_array(exits).is_empty()
	var dropped: int = Time.get_ticks_msec()
	c.drop()
	assert_bool(await _until(func() -> bool: return not exits.is_empty())).is_true()
	assert_int(exits[0] - dropped).is_greater_equal(550)
	assert_bool(FileAccess.file_exists(_pid_file)).is_false()
	life.queue_free()


# FT: FT-NET-030
# --http-root serves the web export over plain HTTP on the bind address at the
# WebSocket port - 1 (D108), polled by the server loop.
func test_static_http_runs_beside_the_websocket_port() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var page: FileAccess = FileAccess.open(_dir.path_join("index.html"), FileAccess.WRITE)
	page.store_string("<p>station</p>")
	page.close()
	var server: NetServer = _server()
	if server.start_http(_dir) != OK:
		# Port - 1 of a random port can be taken by another program; not this test's case.
		push_warning("port %d busy; skipped" % (server.port() - 1))
		return
	assert_int(server.http.local_port()).is_equal(server.port() - 1)
	var tcp: StreamPeerTCP = StreamPeerTCP.new()
	assert_int(tcp.connect_to_host("127.0.0.1", server.port() - 1)).is_equal(OK)
	var reply: PackedByteArray = PackedByteArray()
	var sent: Array[bool] = [false]
	var got: Callable = func() -> bool:
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent[0]:
				tcp.put_data("GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n".to_utf8_buffer())
				sent[0] = true
			var n: int = tcp.get_available_bytes()
			if n > 0:
				reply.append_array(tcp.get_data(n)[1])
		return reply.get_string_from_utf8().contains("<p>station</p>")
	assert_bool(await _until(got)).is_true()
	assert_str(reply.get_string_from_utf8()).starts_with("HTTP/1.1 200")
	assert_int(server.http.requests).is_equal(1)
	tcp.disconnect_from_host()


# FT: FT-NET-014, FT-GEN-003
# 64 connections are admitted; connection 65 is refused with "session full" and
# closed. The refused one doesn't take a session, and a slot freed by a leaving
# player admits a newcomer.
func test_connection_65_is_refused_as_session_full() -> void:
	var server: NetServer = _server()
	var cap: int = server.session.max_sessions
	assert_int(cap).is_equal(64)
	for i: int in cap:
		_client(server)
	var all_in: Callable = func() -> bool:
		return _clients.all(func(c: NetClient) -> bool: return c.is_welcomed())
	assert_bool(await _until(all_in, 30_000)).is_true()
	assert_int(server.players()).is_equal(cap)
	var late: NetClient = _client(server)
	var refused: Callable = func() -> bool: return late.state == NetClient.State.REJECTED
	assert_bool(await _until(refused)).is_true()
	assert_str(late.reject_reason).is_equal(NetProtocol.REJECT_FULL)
	assert_str(NetProtocol.REJECT_FULL).is_equal("session_full")
	assert_int(server.session.by_id.size()).is_equal(cap)
	# One player says Bye: a newcomer gets in.
	_clients[0].bye()
	assert_bool(await _until(func() -> bool: return server.players() == cap - 1)).is_true()
	var next: NetClient = _client(server)
	assert_bool(await _until(next.is_welcomed)).is_true()
