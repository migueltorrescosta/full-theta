extends GdUnitTestSuite
## The multi-ship and PvP messages of protocol version 8 (#11): the client builders encode
## the shapes the schemas accept, and every event payload FleetMessages builds passes its
## check after a trip through the event codec.


# FT: FT-NET-004
func test_client_builders_decode() -> void:
	var sent: Array[PackedByteArray] = [
		NetProtocol.ship_add("Kestrel II"),
		NetProtocol.ship_team(1, 0),
		NetProtocol.session_mode("holdout", "last_team_standing", 3),
		NetProtocol.relaunch(0, true),
	]
	for bytes: PackedByteArray in sent:
		var back: Dictionary = NetProtocol.decode(bytes)
		assert_bool(back.is_empty()).is_false()
		assert_bool(NetProtocol.FROM_CLIENT.has(back["t"])).is_true()
		assert_bool(NetProtocol.RATED_REQUESTS.has(back["t"])).is_true()


## One payload per FleetMessages event.
func _payloads() -> Dictionary:
	var row: Dictionary = FleetMessages.fleet_ship(
		1, "Kestrel II", 0, [{"name": "Ana", "entry": "tactical"}], 1, ["helm"], false, false
	)
	var outcome: SessionOutcome = SessionOutcome.new()
	outcome.reason = SessionOutcome.Reason.LAST_STANDING
	outcome.winners = PackedInt32Array([2])
	return {
		NetProtocol.EVENT_FLEET:
		FleetMessages.fleet([row], SessionRules.of_mode(SessionRules.Mode.TEAMS), -1, [1], false),
		NetProtocol.EVENT_TAKEOVER: FleetMessages.takeover(0, "helm", "Ana", 1),
		NetProtocol.EVENT_HANDOVER: FleetMessages.handover(0, FleetMessages.TO_SCOREBOARD),
		NetProtocol.EVENT_SCOREBOARD:
		FleetMessages.scoreboard(
			[FleetMessages.scoreboard_row(0, "Kestrel", 0, FleetMessages.DESTROYED, 2, 314.5, 1)]
		),
		NetProtocol.EVENT_ELIMINATED: FleetMessages.eliminated(0, "forfeit", 0),
		NetProtocol.EVENT_RELAUNCH_VOTES: FleetMessages.relaunch_votes(0, ["Ana"], 2),
		NetProtocol.EVENT_RELAUNCHED: FleetMessages.relaunched(0, -1),
		NetProtocol.EVENT_SESSION_OVER: FleetMessages.session_over(outcome, 600.0),
	}


# FT: FT-NET-004
func test_event_payloads_round_trip() -> void:
	var payloads: Dictionary = _payloads()
	assert_int(payloads.size()).is_equal(FleetMessages.PAYLOADS.size())
	for type: String in payloads:
		var bytes: PackedByteArray = NetProtocol.event(3, 120, type, payloads[type])
		var back: Dictionary = NetProtocol.decode(bytes)
		assert_str(back["type"]).is_equal(type)
		assert_str(FleetMessages.check(type, back["payload"])).is_equal("")
		assert_dict(back["payload"]).is_equal(payloads[type])


# FT: FT-NET-004
func test_check_rejects_other_shapes() -> void:
	var takeover: Dictionary = FleetMessages.takeover(0, "helm", "Ana", 1)
	takeover["hull"] = 0.5
	assert_str(FleetMessages.check(NetProtocol.EVENT_TAKEOVER, takeover)).is_not_empty()
	# A scoreboard row with a hull or a position leaks (M4-Q9).
	var row: Dictionary = FleetMessages.scoreboard_row(0, "K", 0, FleetMessages.IN_PLAY, 0, 0.0, 0)
	row["hull"] = 0.5
	var board: Dictionary = FleetMessages.scoreboard([row])
	assert_str(FleetMessages.check(NetProtocol.EVENT_SCOREBOARD, board)).is_not_empty()
	assert_str(FleetMessages.check("nope", {})).is_not_empty()
