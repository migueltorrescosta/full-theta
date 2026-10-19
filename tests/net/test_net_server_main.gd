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
	# D127: no secret on the command line, which other local users can read.
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--host-secret", "beef"])).is_false()
	assert_bool(ServerMain.new().parse_args(["--bind", "::1", "--http-root", "web"])).is_false()
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


# FT: FT-NET-003, FT-NET-012
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
# make_server starts the beacon unless --no-beacon or the bind address is loopback (no
# other machine could join), and the HTTP server only with --http-root; without HTTP
# the beacon advertises HTTP port 0.
func test_makes_beacon_only_off_loopback_and_optional_http() -> void:
	for a: String in ["127.0.0.1", "127.1.2.3", "::1", "localhost"]:
		assert_bool(ServerMain.is_loopback(a)).override_failure_message(a).is_true()
	for a: String in ["192.168.1.20", "10.0.0.7", "0.0.0.0", "::", "fe80::1"]:
		assert_bool(ServerMain.is_loopback(a)).override_failure_message(a).is_false()
	var cli: ServerMain = ServerMain.new()
	var args: PackedStringArray = ["--bind", "127.0.0.1", "--port", "0", "--discovery-port", "9"]
	assert_bool(cli.parse_args(args)).is_true()
	assert_bool(cli.beacon).is_true()
	var server: NetServer = cli.make_server()
	assert_object(server.beacon).is_null()
	assert_object(server.http).is_null()
	# What a LAN-bound server sends (its beacon started by hand here, on loopback).
	assert_int(server.start_beacon("x", 9, ["127.0.0.1"])).is_equal(OK)
	assert_int(server.beacon.ws_port).is_equal(server.port())
	assert_int(server.beacon.http_port).is_equal(0)
	server.transport.stop()
	server.beacon.stop()
	server.free()


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
	var o: HostSession.Options = HostSession.Options.new("127.0.0.1")
	o.language = "pt_PT"
	var args: PackedStringArray = HostLauncher.server_args(o, "/u/p.json", "")
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
	assert_str(voice.clip_dir).is_equal(VoiceSetup.CLIP_DIR)
	voice.free()
	c.drop()
	server.queue_free()
	await get_tree().process_frame


# FT: FT-NET-002, FT-GEN-003
# The load gate's dev and test flags (#11, D160, D161): --load-ships builds the 6-ship
# LoadEncounter instead of M1's, and --probe-* configure the LoadProbe.
func test_parses_load_gate_flags() -> void:
	var cli: ServerMain = ServerMain.new()
	var args: PackedStringArray = [
		"--bind",
		"127.0.0.1",
		"--port",
		"0",
		"--no-beacon",
		"--load-ships",
		"6",
		"--load-world",
		"100",
		"--probe-out",
		"/tmp/probe.json",
		"--probe-picks",
		"10",
		"--probe-warmup",
		"1.5",
		"--probe-window",
		"20",
	]
	assert_bool(cli.parse_args(args)).is_true()
	assert_int(cli.load_ships).is_equal(6)
	assert_int(cli.load_world).is_equal(100)
	assert_str(cli.probe_out).is_equal("/tmp/probe.json")
	assert_int(cli.probe_picks).is_equal(10)
	assert_float(cli.probe_warmup).is_equal(1.5)
	assert_float(cli.probe_window).is_equal(20.0)
	var server: NetServer = cli.make_server()
	assert_object(server).is_not_null()
	assert_bool(server.encounter is LoadEncounter).is_true()
	assert_int(server.session.crew_ships().size()).is_equal(6)
	assert_int(server.world.ship_count()).is_equal(100)
	assert_object(server.probe).is_not_null()
	assert_float(server.probe.window_s).is_equal(20.0)
	assert_bool(server.transport.probe).is_true()
	server.transport.stop()
	server.free()


# FT: FT-NET-002
# The load flags need their companions: --load-world without --load-ships and a
# --probe-* setting without --probe-out are errors, not silently ignored.
func test_rejects_load_flags_without_their_companions() -> void:
	var base: PackedStringArray = ["--bind", "127.0.0.1", "--port", "0"]
	(
		assert_bool(ServerMain.new().parse_args(base + PackedStringArray(["--load-world", "100"])))
		. is_false()
	)
	(
		assert_bool(ServerMain.new().parse_args(base + PackedStringArray(["--probe-window", "5"])))
		. is_false()
	)
	(
		assert_bool(ServerMain.new().parse_args(base + PackedStringArray(["--load-ships", "-1"])))
		. is_false()
	)
	(
		assert_bool(ServerMain.new().parse_args(base + PackedStringArray(["--load-ships", "6"])))
		. is_true()
	)
