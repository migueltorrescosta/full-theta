extends GdUnitTestSuite
## The Shakedown's Captain (review 2, M1; Q20, owner 2026-10-26): the Captain seat hears
## its own ship-computer lines, and the server tells a training run whether a Captain sits
## (a logged flag), so the Captain's track counts only when someone holds the seat.

const PLAYER: int = NetHarness.PLAYER

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _training(server: NetServer) -> void:
	var run: RunDef = RunDef.new()
	run.training = true
	server.world.run_def = run


func _seated(server: NetServer) -> int:
	return server.world.story_flags.get_flag(TrainingDriver.CAPTAIN_SEATED)


# FT: FT-MIS-039, FT-AUD-006
# A line for station "captain" reaches the Captain seat and nobody else.
func test_a_computer_line_for_the_captain_reaches_the_captain_seat() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	var captain: NetClient = await h.joined(server, "cap", "captain")
	var audience: PackedInt32Array = server.session.computer_audience(
		PLAYER, PackedStringArray(["captain"])
	)
	assert_array(Array(audience)).is_equal([captain.session_id])
	# A crew station's line still reaches its own holders only.
	audience = server.session.computer_audience(PLAYER, PackedStringArray(["helm"]))
	assert_array(Array(audience)).is_equal([crew[0].session_id])


# FT: FT-MIS-039
# The seat flag follows the Captain: set on a pick, cleared when the seat is left or lapses;
# a run that is not training gets none.
func test_the_seat_flag_follows_the_captain() -> void:
	var server: NetServer = h.server(false, 0.4)
	_training(server)
	var crew: Array[NetClient] = await h.crew3(server)
	assert_bool(await h.start(server, crew[0])).is_true()
	assert_int(_seated(server)).is_equal(0)
	var captain: NetClient = await h.joined(server, "cap", "captain")
	assert_bool(await h.until(func() -> bool: return _seated(server) == 1)).is_true()
	var gone: NetSession = h.session_of(server, captain)
	await h.drop(server, captain)
	await h.lapsed(gone)
	assert_bool(await h.until(func() -> bool: return _seated(server) == 0)).is_true()


# FT: FT-MIS-039
func test_no_seat_flag_outside_training() -> void:
	var server: NetServer = h.server()
	var crew: Array[NetClient] = await h.crew3(server)
	assert_bool(await h.start(server, crew[0])).is_true()
	await h.joined(server, "cap", "captain")
	await h.wait(300)
	assert_int(_seated(server)).is_equal(0)
