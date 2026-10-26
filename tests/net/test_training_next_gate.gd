extends GdUnitTestSuite
## Next (Shakedown, D235) through the command gate: any crew station of the pick may press it
## for itself, the Captain seat for the Captain, nobody for another station; viewers cannot.


func _session(entry: String) -> NetSession:
	var s: NetSession = NetSession.new(1, 1000.0, 1000.0)
	s.ship = 0
	s.entry = entry
	return s


func _check(entry: String, station: String) -> String:
	var out: Array = CommandGate.check(
		_session(entry), {"kind": "training_next", "station": station}, 0
	)
	return out[1]


# FT: FT-MIS-039, FT-NET-006
func test_a_station_presses_next_for_itself_only() -> void:
	for station: String in StationViews.CREW:
		assert_str(_check(station, station)).is_empty()
	assert_str(_check("helm", "weapons")).is_equal(CommandGate.NOT_YOUR_STATION)
	assert_str(_check("helm", "")).is_equal(CommandGate.NOT_YOUR_STATION)
	assert_str(_check("helm", "captain")).is_equal(CommandGate.NOT_YOUR_STATION)


# FT: FT-MIS-039, FT-NET-006
func test_a_joint_view_presses_next_for_either_of_its_stations() -> void:
	assert_str(_check("tactical", "helm")).is_empty()
	assert_str(_check("tactical", "weapons")).is_empty()
	assert_str(_check("tactical", "comms")).is_equal(CommandGate.NOT_YOUR_STATION)


# FT: FT-MIS-039, FT-NET-006
func test_the_captain_seat_presses_next_and_a_viewer_cannot() -> void:
	assert_str(_check("captain", "captain")).is_empty()
	assert_str(_check("captain", "helm")).is_equal(CommandGate.NOT_YOUR_STATION)
	assert_str(_check("viewer", "viewer")).is_equal(CommandGate.NOT_YOUR_STATION)
	assert_str(_check("viewer", "captain")).is_equal(CommandGate.NOT_YOUR_STATION)


# FT: FT-MIS-039
func test_the_command_carries_the_station() -> void:
	var out: Array = CommandGate.check(
		_session("relay"), {"kind": "training_next", "station": "relay"}, 0
	)
	var cmd: TrainingNextCommand = out[0] as TrainingNextCommand
	assert_object(cmd).is_not_null()
	assert_str(String(cmd.station)).is_equal("relay")
	assert_int(cmd.source).is_equal(SimCommand.Source.CREW)
	assert_int(cmd.ship_id).is_equal(0)
