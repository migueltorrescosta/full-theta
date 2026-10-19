extends GdUnitTestSuite
## HostLauncher: the server child's argument list, and a real spawn and kill.

const PID_FILE: String = "user://host_test_launcher_pid.json"

var _launcher: HostLauncher


func after_test() -> void:
	if _launcher != null:
		_launcher.stop()
		_launcher = null
	ServerPidFile.remove(PID_FILE)


# FT: FT-NET-001
# Every HostSession option maps to its server flag; the secret never does (D127).
func test_server_args_from_the_editor_binary() -> void:
	var o: HostSession.Options = HostSession.Options.new("192.168.1.20")
	o.grace_s = 12.5
	o.idle_exit_min = 10
	var args: PackedStringArray = HostLauncher.server_args(o, "/u/pid.json", "/proj/")
	(
		assert_array(Array(args))
		. is_equal(
			[
				"--headless",
				"--path",
				"/proj/",
				"--",
				"--server",
				"--bind",
				"192.168.1.20",
				"--port",
				str(ServerMain.DEFAULT_PORT),
				"--pid-file",
				"/u/pid.json",
				"--grace-s",
				"12.5",
				"--idle-exit-min",
				"10.0",
				"--host-secret-env",
				"--language",
				"en",
			]
		)
	)
	o.port = 5000
	o.beacon = false
	o.http_root = "/srv/web"
	args = HostLauncher.server_args(o, "/u/pid.json", "/proj/")
	assert_str(args[args.find("--port") + 1]).is_equal("5000")
	assert_str(args[args.find("--http-root") + 1]).is_equal("/srv/web")
	assert_bool(args.has("--no-beacon")).is_true()
	# What the child parses back.
	var cli: ServerMain = ServerMain.new()
	OS.set_environment(HostLauncher.SECRET_ENV, "c0ffee")
	assert_bool(cli.parse_args(args.slice(args.find("--") + 1))).is_true()
	assert_str(cli.bind_address).is_equal("192.168.1.20")
	assert_int(cli.port).is_equal(5000)
	assert_float(cli.grace_s).is_equal(12.5)
	assert_float(cli.idle_exit_min).is_equal(10.0)
	assert_str(cli.http_root).is_equal("/srv/web")
	assert_bool(cli.beacon).is_false()
	assert_str(cli.host_secret).is_equal("c0ffee")


# FT: FT-NET-001
func test_server_args_in_an_export_have_no_path() -> void:
	var o: HostSession.Options = HostSession.Options.new("127.0.0.1")
	var args: PackedStringArray = HostLauncher.server_args(o, "/u/p.json", "")
	assert_bool(args.has("--path")).is_false()
	assert_str(args[0]).is_equal("--headless")
	assert_str(args[1]).is_equal("--")
	assert_str(args[args.find("--bind") + 1]).is_equal("127.0.0.1")
	assert_bool(args.has("--http-root")).is_false()
	assert_bool(args.has("--no-beacon")).is_false()


# FT: FT-NET-001
# D108: the bind address is required; there is no every-interface default.
func test_spawn_needs_a_bind_address() -> void:
	_launcher = HostLauncher.new()
	assert_int(_launcher.spawn(HostSession.Options.new(), PID_FILE)).is_equal(ERR_INVALID_PARAMETER)
	assert_int(_launcher.pid).is_equal(-1)
	var h: HostSession = HostSession.new()
	assert_int(h.host(HostSession.Options.new())).is_equal(ERR_INVALID_PARAMETER)
	assert_int(h.state).is_equal(HostSession.State.FAILED)
	# The host client joins at the bind address; every-interface binds via loopback.
	for pair: Array in [["192.168.1.20", "192.168.1.20"], ["0.0.0.0", "127.0.0.1"], ["::", "::1"]]:
		h.launcher.bind = pair[0]
		assert_str(h.join_address()).is_equal(pair[1])


func test_host_secrets_are_random_hex() -> void:
	var a: String = HostLauncher.new_secret()
	assert_int(a.length()).is_equal(HostLauncher.SECRET_BYTES * 2)
	assert_bool(a.is_valid_hex_number()).is_true()
	assert_str(HostLauncher.new_secret()).is_not_equal(a)


func test_project_path_points_at_this_project_when_not_exported() -> void:
	# The tests run from the editor binary with --path.
	assert_str(HostLauncher.project_path()).is_equal(ProjectSettings.globalize_path("res://"))


# FT: FT-NET-001, FT-NET-003
# The host secret (D127) reaches the child through its environment, which only the
# same user can read, never through its world-readable command line; this process's
# environment is clean again after the spawn.
func test_spawns_this_executable_and_kills_it() -> void:
	_launcher = HostLauncher.new()
	# A port nobody listens on; the child is killed long before it matters.
	var o: HostSession.Options = HostSession.Options.new("127.0.0.1")
	o.port = 40000 + randi() % 20000
	o.idle_exit_min = 1
	o.beacon = false
	assert_int(_launcher.spawn(o, PID_FILE)).is_equal(OK)
	var pid: int = _launcher.pid
	assert_int(pid).is_greater(0)
	if OS.get_name() == "Linux":
		# Right after the fork /proc still shows our own command line; wait
		# for the exec.
		var args: PackedStringArray = []
		var until: int = Time.get_ticks_msec() + 2000
		while not args.has("--server") and Time.get_ticks_msec() < until:
			args = OrphanCheck.read_cmdline(pid)
			OS.delay_msec(5)
		assert_str(args[0]).is_equal(OS.get_executable_path())
		assert_bool(args.has("--headless")).is_true()
		assert_bool(args.has("--server")).is_true()
		assert_bool(args.has("--host-secret-env")).is_true()
		assert_bool(args.has(_launcher.host_secret)).is_false()
		assert_bool(args.has("--host-secret")).is_false()
		var environ: PackedStringArray = OrphanCheck.split_cmdline(
			FileAccess.open("/proc/%d/environ" % pid, FileAccess.READ).get_buffer(1 << 20)
		)
		assert_bool(environ.has(HostLauncher.SECRET_ENV + "=" + _launcher.host_secret)).is_true()
	assert_str(OS.get_environment(HostLauncher.SECRET_ENV)).is_empty()
	# A pid file left behind with the child's pid goes with it.
	var info: ServerPidFile = ServerPidFile.for_this_process(1, "127.0.0.1")
	info.pid = pid
	assert_int(info.save(PID_FILE)).is_equal(OK)
	_launcher.stop()
	assert_int(_launcher.pid).is_equal(-1)
	assert_bool(FileAccess.file_exists(PID_FILE)).is_false()
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and OrphanCheck.process_alive(pid):
		OS.delay_msec(10)
	assert_bool(OrphanCheck.process_alive(pid)).is_false()


# FT: FT-NET-003
# Pid reuse: an adopted orphan's pid now runs an unrelated program. stop() identifies
# the process again right before the kill and leaves it alone, but still removes the
# stale pid file.
func test_stop_leaves_an_unrelated_process_with_the_adopted_pid() -> void:
	if OS.get_name() != "Linux":
		return
	var other: int = OS.create_process("sleep", ["30"])
	assert_int(other).is_greater(0)
	var info: ServerPidFile = ServerPidFile.for_this_process(1, "127.0.0.1")
	info.pid = other
	assert_int(info.save(PID_FILE)).is_equal(OK)
	_launcher = HostLauncher.new()
	_launcher.adopt(info, "", PID_FILE)
	_launcher.stop()
	OS.delay_msec(200)
	assert_bool(OS.is_process_running(other)).is_true()
	assert_bool(FileAccess.file_exists(PID_FILE)).is_false()
	OS.kill(other)
