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
