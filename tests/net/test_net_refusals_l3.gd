extends GdUnitTestSuite
## L3 tests of the refusals the server owes a client: commands while the sim is stopped
## (#45 A4), from a station that is not the sender's, to a destroyed ship; lobby requests past
## the rate limit (R11-4); and a second connection with a token (C12, D6).

const PLAYER: int = NetHarness.PLAYER

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## The reason of the command_rejected event for `seq`, or "" when none arrives.
func _reason(c: NetClient, seq: int, from: int) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_COMMAND_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["seq"] == seq
	)
	return e.get("payload", {}).get("reason", "")


# FT: FT-NET-006, FT-NET-007, FT-NET-034
# A4: while the sim is stopped (the lobby, a host pause, a coverage pause) a crew command is
# refused `paused` instead of queueing until the resume; Next (the Shakedown) is let through.
func test_commands_are_refused_while_the_sim_is_stopped() -> void:
	var server: NetServer = h.server(true)
	var eng: NetClient = await h.joined(server, "eng", "engineering")
	var from: int = h.mark(eng)
	var seq: int = eng.set_pips(SubsystemDef.Kind.ENGINES, 2)
	assert_str(await _reason(eng, seq, from)).is_equal(CommandGate.PAUSED)
	assert_array(server.world.accepted_commands()).is_empty()
	server.session.launch(PLAYER)
	assert_bool(server.session.sim_running()).is_true()
	from = h.mark(eng)
	seq = eng.set_pips(SubsystemDef.Kind.ENGINES, 2)
	(
		assert_bool(
			await h.until(func() -> bool: return server.world.accepted_commands().size() > 0)
		)
		. is_true()
	)
	assert_str(await _reason(eng, seq, from)).is_empty()
	# A host pause, then a coverage pause.
	server.session.host_paused = true
	from = h.mark(eng)
	seq = eng.set_pips(SubsystemDef.Kind.ENGINES, 1)
	assert_str(await _reason(eng, seq, from)).is_equal(CommandGate.PAUSED)
	var next: int = eng.command({"kind": "training_next", "station": "engineering"})
	assert_str(await _reason(eng, next, from)).is_not_equal(CommandGate.PAUSED)
	server.session.host_paused = false
	server.session.paused[PLAYER] = ["helm"]
	from = h.mark(eng)
	seq = eng.set_pips(SubsystemDef.Kind.ENGINES, 1)
	assert_str(await _reason(eng, seq, from)).is_equal(CommandGate.PAUSED)
	server.session.paused.clear()
	assert_int(server.session.rejections.get(CommandGate.PAUSED, 0)).is_equal(3)


# FT: FT-NET-006, FT-NET-007
# B2: a Viewer and a Captain have no station of their own: Fire is `not_your_station`, and Next
# naming another seat is refused too.
func test_viewer_and_captain_cannot_use_station_commands() -> void:
	var server: NetServer = h.server(true)
	server.session.launch(PLAYER)
	var viewer: NetClient = await h.joined(server, "viewer", "viewer")
	var captain: NetClient = await h.joined(server, "captain", "captain")
	var expect: Dictionary = {}
	for c: NetClient in [viewer, captain]:
		expect[[c, c.fire()]] = CommandGate.NOT_YOUR_STATION
		expect[[c, c.command({"kind": "training_next", "station": "helm"})]] = (
			CommandGate.NOT_YOUR_STATION
		)
	expect[[viewer, viewer.command({"kind": "training_next", "station": "captain"})]] = (
		CommandGate.NOT_YOUR_STATION
	)
	for key: Array in expect:
		var reason: String = await _reason(key[0], key[1], 0)
		assert_str(reason).is_equal(expect[key])


# FT: FT-NET-006, FT-NET-011
# B2: a command to a ship that died before it was applied is reported `ship_destroyed`.
func test_a_command_to_a_destroyed_ship_is_reported() -> void:
	var server: NetServer = h.server(true)
	var eng: NetClient = await h.joined(server, "eng", "engineering")
	server.session.launch(PLAYER)
	server.world.kin.alive[PLAYER] = 0
	var from: int = h.mark(eng)
	var seq: int = eng.set_pips(SubsystemDef.Kind.ENGINES, 2)
	assert_str(await _reason(eng, seq, from)).is_equal(CommandGate.SHIP_DESTROYED)


# FT: FT-NET-006
# R11-4: a Pick, Claim or Ready dropped by the rate limit is answered `request_rejected`
# `rate_limited` with its request type, not left without an answer.
func test_a_rate_limited_lobby_request_is_answered() -> void:
	var server: NetServer = h.server(true)
	var spam: NetClient = await h.welcomed(server, "spam")
	for i: int in 400:
		spam.pick(PLAYER, "captain")
	var limited: Callable = func(e: Dictionary) -> bool:
		return (
			e["payload"]["reason"] == CommandGate.RATE_LIMITED
			and e["payload"]["request"] == NetProtocol.Type.PICK
		)
	var e: Dictionary = await h.next_event(spam, NetProtocol.EVENT_REQUEST_REJECTED, 0, limited)
	assert_bool(e.is_empty()).is_false()


# FT: FT-NET-025, FT-NET-026
# C12 (server side, D6): a Hello with the token of a still-connected session (a reloaded page
# whose old socket has not closed) takes the session over. The old socket closes with 4001, the
# session stays connected under the new socket with its pick, and the old socket's close does
# not drop it into its grace.
func test_a_token_takes_over_a_connected_session_cleanly() -> void:
	var server: NetServer = h.server(true)
	var first: NetClient = await h.joined(server, "page", "engineering")
	var session: NetSession = h.session_of(server, first)
	var second: NetClient = await h.welcomed(server, "page", first.token)
	assert_bool(second.welcome["resumed"]).is_true()
	assert_int(second.session_id).is_equal(session.id)
	(
		assert_bool(
			await h.until(
				func() -> bool: return first._peer.get_ready_state() == WebSocketPeer.STATE_CLOSED
			)
		)
		. is_true()
	)
	assert_int(first._peer.get_close_code()).is_equal(NetTransport.CLOSE_TAKEN_OVER)
	# R11-2: the client keeps the close code, so its shell stops resuming (LinkWatch).
	first.poll()
	assert_int(first.close_code).is_equal(NetTransport.CLOSE_TAKEN_OVER)
	assert_int(first.state).is_equal(NetClient.State.CLOSED)
	await h.wait(300)
	assert_bool(session.connected()).is_true()
	assert_object(server.session.by_conn.get(session.conn)).is_same(session)
	assert_str(session.entry).is_equal("engineering")
	assert_int(server.session.by_conn.size()).is_equal(1)
	assert_bool(await h.until(func() -> bool: return second.view.full_count >= 1)).is_true()


# FT: FT-NET-041
# R11-13: a second Hello with the host secret and no token (a relaunched host that lost its
# token file) becomes the host; the old session in its grace no longer is.
func test_only_one_session_is_the_host() -> void:
	var server: NetServer = h.server(false, 10.0, "s3cret")
	var old: NetClient = await h.welcomed(server, "host", "", "s3cret")
	var old_session: NetSession = h.session_of(server, old)
	assert_bool(old_session.is_host).is_true()
	var fresh: NetClient = await h.welcomed(server, "host", "", "s3cret")
	assert_bool(h.session_of(server, fresh).is_host).is_true()
	assert_bool(old_session.is_host).is_false()
