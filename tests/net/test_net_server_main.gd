extends GdUnitTestSuite
## The dedicated server's command line (app/server_main.gd).


# FT: FT-NET-002
func test_parses_server_flags() -> void:
	var cli: ServerMain = ServerMain.new()
	var args: PackedStringArray = [
		"--server",
		"--bind",
		"192.168.1.20",
		"--port",
		"47811",
		"--dev-all-stations",
		"--seed",
		"9",
		"--host-secret",
		"beef",
		"--grace-s",
		"12.5",
		"--idle-exit-min",
		"30",
		"--pid-file",
		"/tmp/ft.pid",
		"--run-for",
		"3",
	]
	assert_bool(cli.parse_args(args)).is_true()
	assert_str(cli.bind_address).is_equal("192.168.1.20")
	assert_int(cli.port).is_equal(47811)
	assert_bool(cli.dev_all_stations).is_true()
	assert_int(cli.seed_value).is_equal(9)
	assert_str(cli.host_secret).is_equal("beef")
	assert_float(cli.grace_s).is_equal(12.5)
	assert_float(cli.idle_exit_min).is_equal(30.0)
	assert_str(cli.pid_file).is_equal("/tmp/ft.pid")
	assert_float(cli.run_for).is_equal(3.0)


# FT: FT-NET-002
func test_rejects_bad_command_lines() -> void:
	assert_bool(ServerMain.new().parse_args(["--server"])).is_false()
	assert_bool(ServerMain.new().parse_args(["--server", "--bind"])).is_false()
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--port", "x"])).is_false()
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--port", "70000"])).is_false()
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--warp"])).is_false()
	var cli: ServerMain = ServerMain.new()
	assert_bool(cli.parse_args(["--server", "--bind", "127.0.0.1"])).is_true()
	assert_int(cli.port).is_equal(ServerMain.DEFAULT_PORT)


# FT: FT-NET-002
# The server builds the M1 encounter from the content definitions and listens.
func test_makes_a_listening_server() -> void:
	var cli: ServerMain = ServerMain.new()
	assert_bool(cli.parse_args(["--server", "--bind", "127.0.0.1", "--port", "0"])).is_true()
	var server: NetServer = cli.make_server()
	assert_object(server).is_not_null()
	assert_int(server.port()).is_greater(0)
	assert_int(server.world.ship_count()).is_equal(2)
	server.transport.stop()
	server.free()


# FT: FT-NET-003, FT-NET-012, FT-NET-030
# The host and LAN flags: pid file, idle exit, web export root, beacon name and port,
# and the beacon off switch.
func test_parses_host_and_lan_flags() -> void:
	var cli: ServerMain = ServerMain.new()
	assert_bool(cli.beacon).is_true()
	assert_str(cli.http_root).is_empty()
	var args: PackedStringArray = [
		"--server",
		"--bind",
		"127.0.0.1",
		"--http-root",
		"/srv/web",
		"--name",
		"Bridge Party",
		"--discovery-port",
		"47791",
		"--no-beacon",
		"--idle-exit-min",
		"0.5",
	]
	assert_bool(cli.parse_args(args)).is_true()
	assert_str(cli.http_root).is_equal("/srv/web")
	assert_str(cli.server_name).is_equal("Bridge Party")
	assert_int(cli.discovery_port).is_equal(47791)
	assert_bool(cli.beacon).is_false()
	assert_float(cli.idle_exit_min).is_equal(0.5)
	var bad: PackedStringArray = ["--bind", "127.0.0.1", "--discovery-port", "0"]
	assert_bool(ServerMain.new().parse_args(bad)).is_false()


# FT: FT-NET-001
# D127: --host-secret-env takes the host secret from FT_HOST_SECRET (what HostLauncher
# passes, off the world-readable command line) and clears the variable; it fails when
# the variable is missing.
func test_host_secret_comes_from_the_environment() -> void:
	OS.set_environment(HostLauncher.SECRET_ENV, "c0ffee")
	var cli: ServerMain = ServerMain.new()
	assert_bool(cli.parse_args(["--server", "--bind", "127.0.0.1", "--host-secret-env"])).is_true()
	assert_str(cli.host_secret).is_equal("c0ffee")
	assert_str(OS.get_environment(HostLauncher.SECRET_ENV)).is_empty()
	var none: ServerMain = ServerMain.new()
	assert_bool(none.parse_args(["--bind", "127.0.0.1", "--host-secret-env"])).is_false()


# FT: FT-NET-012
# make_server starts the beacon unless --no-beacon, and the HTTP server only with
# --http-root.
func test_makes_beacon_and_optional_http() -> void:
	var cli: ServerMain = ServerMain.new()
	var args: PackedStringArray = ["--bind", "127.0.0.1", "--port", "0", "--discovery-port", "9"]
	assert_bool(cli.parse_args(args)).is_true()
	var server: NetServer = cli.make_server()
	assert_object(server.beacon).is_not_null()
	assert_int(server.beacon.ws_port).is_equal(server.port())
	assert_object(server.http).is_null()
	server.transport.stop()
	server.beacon.stop()
	server.free()
	var quiet: ServerMain = ServerMain.new()
	assert_bool(quiet.parse_args(["--bind", "127.0.0.1", "--port", "0", "--no-beacon"])).is_true()
	var server2: NetServer = quiet.make_server()
	assert_object(server2.beacon).is_null()
	server2.transport.stop()
	server2.free()


# FT: FT-AUD-013
# The host picks the session language before launch: --language takes en, pt_PT or it
# (en by default), refuses anything else, and HostLauncher passes it to the child.
func test_language_flag() -> void:
	var cli: ServerMain = ServerMain.new()
	assert_bool(cli.parse_args(["--bind", "127.0.0.1"])).is_true()
	assert_str(cli.language).is_equal("en")
	for lang: String in ["en", "pt_PT", "it"]:
		var ok: ServerMain = ServerMain.new()
		assert_bool(ok.parse_args(["--bind", "127.0.0.1", "--language", lang])).is_true()
		assert_str(ok.language).is_equal(lang)
	for bad: String in ["pt", "EN", "de", ""]:
		assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--language", bad])).is_false()
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--language"])).is_false()
	var args: PackedStringArray = HostLauncher.server_args(5000, "/u/p.json", 3, "", "pt_PT")
	assert_str(args[args.find("--language") + 1]).is_equal("pt_PT")


# FT: FT-AUD-013
# Welcome carries the --language value to every client (L3: a real client over loopback).
func test_welcome_carries_the_language() -> void:
	var cli: ServerMain = ServerMain.new()
	var args: PackedStringArray = ["--bind", "127.0.0.1", "--port", "0", "--no-beacon"]
	args.append_array(["--language", "it"])
	assert_bool(cli.parse_args(args)).is_true()
	var server: NetServer = cli.make_server()
	add_child(server)
	var c: NetClient = NetClient.new()
	assert_int(c.connect_to("ws://127.0.0.1:%d" % server.port())).is_equal(OK)
	var end: int = Time.get_ticks_msec() + 4000
	while not c.is_welcomed() and Time.get_ticks_msec() < end:
		c.poll()
		await get_tree().process_frame
	assert_bool(c.is_welcomed()).is_true()
	assert_str(c.welcome["lang"]).is_equal("it")
	# The voice service composed next to it shares its transport (E10).
	var voice: VoiceService = cli.make_voice(server)
	assert_object(voice.transport).is_same(server.transport)
	assert_int(voice.tick_source.call()).is_equal(server.world.tick)
	voice.free()
	c.drop()
	server.queue_free()
	await get_tree().process_frame
