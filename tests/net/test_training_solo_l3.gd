extends GdUnitTestSuite
## Solo station lessons on a server (D303, FT-MIS-039, FT-NET-004): a client asks for one, a
## server with no other crew switches to a fresh Shakedown with bots on the other stations
## and starts it at once; a server with crew refuses, and nothing changes for them. The
## server goes back to its own encounter when the lesson's player is gone.

var h: NetHarness
var cli: ServerMain


func before_test() -> void:
	h = NetHarness.new(self)
	cli = ServerMain.new()


func after_test() -> void:
	await h.free_all()


## A harness server that can teach: the Shakedown's setup and driver as ServerMain builds them.
func _teaching_server(grace_s: float = 10.0) -> NetServer:
	var server: NetServer = h.server(false, grace_s)
	server.training_setup = func() -> RunSetup: return cli.run_setup(DefLibrary.new(), "shakedown")
	server.training_driver = cli._training_factory
	return server


func _since(c: NetClient, from: int, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array = h.events[c]
	for i: int in range(from, seen.size()):
		if seen[i]["type"] == type:
			out.append(seen[i])
	return out


# FT: FT-MIS-039
func test_a_lone_client_gets_a_started_lesson_at_its_station() -> void:
	var server: NetServer = _teaching_server()
	var c: NetClient = await h.welcomed(server, "ana")
	var n: int = h.mark(c)
	c.start_training("weapons")
	var started: Dictionary = await h.next_event(c, NetProtocol.EVENT_STARTED, n)
	assert_bool(started.is_empty()).is_false()
	var picked: Dictionary = await h.next_event(c, NetProtocol.EVENT_PICKED, n)
	assert_str(picked["payload"]["entry"]).is_equal("weapons")
	assert_str(picked["payload"]["reason"]).is_empty()
	assert_bool(server.training_active).is_true()
	assert_str(server.session.training.solo).is_equal("weapons")
	assert_bool(server.world.run_def.training).is_true()
	# Bots hold the other five stations, so the ship is crewed.
	var entries: Array = server.session.entries_of(picked["payload"]["ship"])
	assert_array(NetCoverage.uncovered(entries)).is_empty()
	assert_int(NetCoverage.crew_count(entries)).is_equal(6)
	# The driver is the solo one, and steps once the sim runs.
	assert_bool(await h.until(func() -> bool: return server.driver is TrainingDriver)).is_true()
	assert_str(String((server.driver as TrainingDriver).solo_station())).is_equal("weapons")


# FT: FT-MIS-039
func test_a_server_with_crew_says_busy_and_keeps_its_run() -> void:
	var server: NetServer = _teaching_server()
	await h.crew3(server)
	var c: NetClient = await h.welcomed(server, "late")
	var n: int = h.mark(c)
	c.start_training("helm")
	var refused: Dictionary = await h.next_event(c, NetProtocol.EVENT_REQUEST_REJECTED, n)
	assert_str(refused["payload"]["reason"]).is_equal("busy")
	assert_int(refused["payload"]["players"]).is_equal(3)
	assert_int(refused["payload"]["request"]).is_equal(NetProtocol.Type.TRAINING)
	assert_bool(server.training_active).is_false()
	assert_str(server.session.training.solo).is_empty()
	assert_array(_since(c, n, NetProtocol.EVENT_STARTED)).is_empty()


# FT: FT-MIS-039
func test_a_bad_station_is_refused() -> void:
	var server: NetServer = _teaching_server()
	var c: NetClient = await h.welcomed(server, "ana")
	var n: int = h.mark(c)
	c.start_training("galley")
	var refused: Dictionary = await h.next_event(c, NetProtocol.EVENT_REQUEST_REJECTED, n)
	assert_str(refused["payload"]["reason"]).is_equal(NetTraining.BAD_STATION)
	assert_bool(server.training_active).is_false()


# FT: FT-MIS-039
func test_the_server_goes_back_when_the_player_leaves() -> void:
	var server: NetServer = _teaching_server(0.3)
	var home: M1Encounter = server.encounter
	var c: NetClient = await h.welcomed(server, "ana")
	c.start_training("captain")
	assert_bool(await h.until(func() -> bool: return server.training_active)).is_true()
	var session: NetSession = h.session_of(server, c)
	await h.drop(server, c)
	await h.lapsed(session)
	assert_bool(await h.until(func() -> bool: return not server.training_active)).is_true()
	assert_object(server.encounter).is_same(home)
	assert_str(server.session.training.solo).is_empty()
	# A crew can now take the run as before.
	var crew: Array[NetClient] = await h.crew3(server)
	assert_bool(await h.start(server, crew[0])).is_true()


# FT: FT-MIS-039
func test_the_crew_drill_request_gives_a_fresh_shakedown_without_bots() -> void:
	var server: NetServer = _teaching_server()
	var c: NetClient = await h.welcomed(server, "ana")
	c.start_training("")
	assert_bool(await h.until(func() -> bool: return server.training_active)).is_true()
	assert_str(server.session.training.solo).is_empty()
	assert_array(server.session.training.bot_entries()).is_empty()
	assert_bool(server.world.run_def.training).is_true()


# FT: FT-MIS-039
func test_the_hosts_solo_flag_starts_a_lesson_on_join() -> void:
	var server: NetServer = _teaching_server()
	server.session.host_secret = "s3cret"
	server.session.training.solo_on_join = "relay"
	var c: NetClient = await h.welcomed(server, "host", "", "s3cret")
	assert_bool(await h.until(func() -> bool: return server.session.launched.size() == 1)).is_true()
	assert_str(h.session_of(server, c).entry).is_equal("relay")
	assert_str(server.session.training.solo).is_equal("relay")


# FT: FT-MIS-039
# The bots of a lesson on a server act for their own stations: their commands reach the world
# through the server's tick, and none is the player's.
func test_the_server_bots_submit_commands_for_their_own_stations_only() -> void:
	var server: NetServer = _teaching_server()
	var c: NetClient = await h.welcomed(server, "ana")
	c.start_training("helm")
	assert_bool(await h.until(func() -> bool: return server.driver is TrainingDriver)).is_true()
	server.partners.crew.record = true
	(
		assert_bool(
			await h.until(func() -> bool: return not server.partners.crew.sent.is_empty(), 12000)
		)
		. is_true()
	)
	for row: Array in server.partners.crew.sent:
		assert_str(String(row[1])).is_not_equal("helm")
		assert_str(StationViews.station_of_command(row[2])).is_equal(String(row[1]))


# FT: FT-MIS-039
# The server steps the bots with the driver: Helm's own track done, the partner presses for
# the first pair step (Engineering) by itself.
func test_the_bots_press_next_for_their_half_of_a_pair_step() -> void:
	var server: NetServer = _teaching_server()
	var c: NetClient = await h.welcomed(server, "ana")
	c.start_training("helm")
	assert_bool(await h.until(func() -> bool: return server.driver is TrainingDriver)).is_true()
	var driver: TrainingDriver = server.driver as TrainingDriver
	var rig: ShakedownRig = ShakedownRig.new()
	var guard: int = 0
	while driver.current(&"helm") != null and guard < 200:
		var step: TrainingStepDef = driver.current(&"helm")
		if step.kind == TrainingStepDef.Kind.COMMAND:
			server.world.submit(rig.command_for(step.command))
		else:
			var next: TrainingNextCommand = TrainingNextCommand.new()
			next.ship_id = driver.ship_id()
			next.station = &"helm"
			server.world.submit(next)
		await h.until(func() -> bool: return driver.current(&"helm") != step)
		guard += 1
	assert_bool(driver.finished(&"helm")).is_true()
	var flag: StringName = TrainingDriver.next_flag(&"engineering")
	(
		assert_bool(
			await h.until(
				func() -> bool: return server.world.story_flags.get_flag(flag) == 1, 12000
			)
		)
		. is_true()
	)


# FT: FT-MIS-039
func test_the_solo_flag_reaches_the_server_child_and_its_command_line() -> void:
	var o: HostSession.Options = HostSession.Options.new("127.0.0.1")
	o.encounter = "shakedown"
	o.solo = "comms"
	var args: PackedStringArray = HostLauncher.server_args(o, "/x/pid", "")
	assert_int(args.find("--solo")).is_greater(0)
	assert_str(args[args.find("--solo") + 1]).is_equal("comms")
	var server_cli: ServerMain = ServerMain.new()
	var good: PackedStringArray = ["--server", "--bind", "127.0.0.1", "--solo", "comms"]
	assert_bool(server_cli.parse_args(good)).is_true()
	assert_str(server_cli.solo_station).is_equal("comms")
	assert_str(server_cli.encounter_name).is_equal("shakedown")
	var bad: PackedStringArray = ["--server", "--bind", "127.0.0.1", "--solo", "x"]
	assert_bool(ServerMain.new().parse_args(bad)).is_false()
