extends GdUnitTestSuite
## The multi-ship and PvP messages of protocol version 8 (#11): the client builders encode
## the shapes the schemas accept, and every event payload FleetMessages builds passes its
## check after a trip through the event codec.


# FT: FT-NET-004
# The fleet intents of NetClient encode what the schemas accept, as the real client sends them
# (the table NetProtocol.MESSAGES says a client may send them, each rated).
func test_client_intents_decode() -> void:
	var c: NetClient = NetClient.new()
	c.add_ship("Kestrel II")
	c.set_team(1, 0)
	c.set_mode("holdout", "last_team_standing", 3)
	c.vote_relaunch(0, true)
	var queue: NetSendQueue = c._queue
	var back: Array[Dictionary] = []
	var chunker: NetChunker = NetChunker.new()
	queue.begin_pump()
	while queue.peek_size() > 0:
		var msg: Dictionary = chunker.feed(queue.next_chunk())
		back.append(NetProtocol.decode(msg["data"]))
	assert_int(back.size()).is_equal(4)
	for fields: Dictionary in back:
		assert_bool(fields.is_empty()).is_false()
		assert_bool(NetProtocol.from_client.has(fields["t"])).is_true()
		assert_bool(NetProtocol.rated_requests.has(fields["t"])).is_true()
	assert_str(back[0]["name"]).is_equal("Kestrel II")


## One payload per FleetMessages event.
func _payloads() -> Dictionary:
	var row: Dictionary = FleetMessages.fleet_ship(
		1, "Kestrel II", 0, [{"name": "Ana", "seat": "tactical"}], 1, ["helm"], false, false
	)
	var reason: String = GameOutcome.REASON_NAMES[GameOutcome.Reason.LAST_STANDING]
	var teams: String = GameRules.MODE_NAMES[GameRules.Mode.TEAMS]
	var team_win: String = GameRules.TEAM_WIN_NAMES[0]
	return {
		NetProtocol.EVENT_FLEET:
		FleetMessages.fleet([row], teams, team_win, GameRules.MAX_SHIPS, -1, [1], false),
		NetProtocol.EVENT_TAKEOVER: FleetMessages.takeover(0, "helm", "Ana", 1),
		NetProtocol.EVENT_HANDOVER: FleetMessages.handover(0, FleetMessages.TO_SCOREBOARD),
		NetProtocol.EVENT_SCOREBOARD:
		FleetMessages.scoreboard(
			[FleetMessages.scoreboard_row(0, "Kestrel", 0, FleetMessages.DESTROYED, 2, 314.5, 1)]
		),
		NetProtocol.EVENT_ELIMINATED: FleetMessages.eliminated(0, "forfeit", 0),
		NetProtocol.EVENT_RELAUNCH_VOTES:
		{"ship": 0, "voters": ["Ana"], "sessions": [4], "needed": 2},
		NetProtocol.EVENT_RELAUNCHED: FleetMessages.relaunched(0, -1),
		NetProtocol.EVENT_GAME_OVER: FleetMessages.game_over(reason, [2], -1, 0.0, 600.0),
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
