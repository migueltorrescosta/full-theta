extends GdUnitTestSuite
## L3 (T041): the headless server (NetServer) and NetClients over loopback WebSocket in
## one process. The server binds port 0 (a free port), so suites can run in parallel.

const PLAYER: int = M1Encounter.PLAYER_SHIP
const TIMEOUT_MS: int = 4000

var _servers: Array[NetServer] = []
var _clients: Array[NetClient] = []


func after_test() -> void:
	for c: NetClient in _clients:
		c.drop()
	_clients.clear()
	for s: NetServer in _servers:
		s.queue_free()
	_servers.clear()
	await get_tree().process_frame


func _server(
	chunk_size: int = NetChunker.DEFAULT_CHUNK_SIZE, host_secret: String = ""
) -> NetServer:
	var s: NetServer = NetServer.new()
	s.transport.chunk_size = chunk_size
	var m1: M1Encounter = M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	assert_int(s.start(m1, 0, "127.0.0.1", true, host_secret)).is_equal(OK)
	# These tests exercise the transport, not the lobby: start the run directly.
	s.session.launch(PLAYER)
	add_child(s)
	_servers.append(s)
	return s


func _client(server: NetServer, name: String) -> NetClient:
	var c: NetClient = NetClient.new()
	c.name = name
	assert_int(c.connect_to("ws://127.0.0.1:%d" % server.port())).is_equal(OK)
	_clients.append(c)
	return c


## Polls every client each frame until cond holds or the timeout passes.
func _until(cond: Callable, timeout_ms: int = TIMEOUT_MS) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		for c: NetClient in _clients:
			c.poll()
		if cond.call():
			return true
		await get_tree().process_frame
	return false


## Polls for ms milliseconds.
func _wait(ms: int) -> void:
	await _until(func() -> bool: return false, ms)


## A welcomed client holding a pick, with its first full snapshot applied.
func _joined(server: NetServer, name: String, entry: String) -> NetClient:
	var c: NetClient = _client(server, name)
	assert_bool(await _until(c.is_welcomed)).is_true()
	c.pick(PLAYER, entry)
	assert_bool(await _until(func() -> bool: return c.stats["fulls"] >= 1)).is_true()
	return c


func _events_of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


# FT: FT-NET-002, FT-NET-004, FT-NET-008, FT-ARC-005
# The dedicated server runs the M1 sim and accepts WebSocket clients: a client gets
# Welcome and the catalogue, picks Helm, receives its station's snapshots at about
# 30 Hz, and a Helm command it sends shows up in the state it renders.
func test_server_runs_sim_and_sends_snapshots_at_30_hz() -> void:
	var server: NetServer = _server()
	var c: NetClient = await _joined(server, "helm", "helm")
	assert_int(c.welcome["v"]).is_equal(NetProtocol.PROTOCOL_VERSION)
	assert_str(c.token).has_length(32)
	assert_float(c.welcome["period"]).is_equal(server.world.kin.period)
	assert_int((c.catalogue["entries"] as Array).size()).is_equal(6 + 3 + 2 + 1)
	assert_int((c.catalogue["ships"] as Array).size()).is_equal(1)
	var picked: Array[Dictionary] = _events_of(c.take_events(), NetProtocol.EVENT_PICKED)
	assert_str(picked[0]["payload"]["reason"]).is_equal("")
	assert_bool(c.view.blocks.has(StationViews.Section.HELM)).is_true()
	assert_bool(c.view.blocks.has(StationViews.Section.ENGINEERING)).is_false()
	# About 30 snapshots a second (wide band: 2 loaded cores).
	var n0: int = c.stats["snapshots"]
	var tick0: int = server.world.tick
	var t0: int = Time.get_ticks_usec()
	await _wait(1000)
	var rate: float = (c.stats["snapshots"] - n0) / ((Time.get_ticks_usec() - t0) / 1e6)
	var tick_rate: float = (server.world.tick - tick0) / ((Time.get_ticks_usec() - t0) / 1e6)
	assert_float(rate).is_between(20.0, 34.0)
	assert_float(tick_rate).is_between(45.0, 66.0)
	assert_float(rate / tick_rate).is_between(0.4, 0.6)
	assert_int(c.view.rejected).is_equal(0)
	# Commands up, state down.
	c.helm(1.0)
	var moving: Callable = func() -> bool:
		return c.view.blocks[StationViews.Section.HELM]["throttle_setpoint"] > 0.0
	assert_bool(await _until(moving)).is_true()
	assert_int(server.session.rejections.size()).is_equal(0)


# FT: FT-NET-005
# A Hello of another protocol version (with another field set) gets HelloRejected with
# a reason and the connection closes; so does an unreadable one.
func test_version_mismatch_is_rejected_with_a_reason() -> void:
	var server: NetServer = _server()
	var old: NetClient = _client(server, "old")
	old._hello_sent = true
	assert_bool(await _until(func() -> bool: return old._peer.get_ready_state() == 1)).is_true()
	old.send_raw(NetProtocol.encode(NetProtocol.Type.HELLO, {"v": 999, "nick": "old"}))
	var r1: bool = await _until(func() -> bool: return old.state == NetClient.State.REJECTED)
	assert_bool(r1).is_true()
	assert_str(old.reject_reason).is_equal(NetProtocol.REJECT_VERSION)
	assert_bool(await _until(func() -> bool: return old._peer.get_ready_state() == 3)).is_true()
	var bad: NetClient = _client(server, "bad")
	bad._hello_sent = true
	assert_bool(await _until(func() -> bool: return bad._peer.get_ready_state() == 1)).is_true()
	bad.send_raw(
		NetProtocol.encode(
			NetProtocol.Type.HELLO,
			{
				"v": NetProtocol.PROTOCOL_VERSION,
				"token": 5,
				"name": "",
				"kind": "",
				"host_secret": ""
			}
		)
	)
	(
		assert_bool(await _until(func() -> bool: return bad.state == NetClient.State.REJECTED))
		. is_true()
	)
	assert_str(bad.reject_reason).is_equal(NetProtocol.REJECT_BAD_HELLO)
	assert_int(server.session.by_id.size()).is_equal(0)


# FT: FT-NET-006, FT-NET-007, FT-NET-011
# Each invalid command produces CommandRejected{seq, reason} to its sender only, as an
# event stamped with the tick: no pick, another station's command, an unknown kind, a
# server-only command, another ship, a bad field, a non-finite value, and one the sim
# rejects on apply (game rules). A valid command is not rejected.
func test_invalid_commands_produce_command_rejected() -> void:
	var server: NetServer = _server()
	var eng: NetClient = _client(server, "eng")
	var other: NetClient = await _joined(server, "other", "engineering")
	assert_bool(await _until(eng.is_welcomed)).is_true()
	var expect: Dictionary = {}
	expect[eng.set_pips(SubsystemDef.Kind.ENGINES, 2)] = CommandGate.NO_PICK
	eng.pick(PLAYER, "engineering")
	assert_bool(await _until(func() -> bool: return eng.stats["fulls"] >= 1)).is_true()
	expect[eng.fire()] = CommandGate.NOT_YOUR_STATION
	expect[eng.command({"kind": "warp_drive"})] = CommandGate.UNKNOWN_KIND
	expect[eng.command({"kind": "reset_ship"})] = CommandGate.NOT_ALLOWED
	expect[eng.command({"kind": "boost", "ship_id": 1})] = CommandGate.WRONG_SHIP
	expect[eng.command({"kind": "set_pips", "pipz": 2})] = CommandGate.BAD_FIELD
	expect[eng.command({"kind": "set_pips", "pips": "2"})] = CommandGate.BAD_FIELD
	expect[eng.command({"kind": "set_shield", "tightness": INF})] = CommandGate.BAD_VALUE
	expect[eng.set_pips(SubsystemDef.Kind.ENGINES, 99)] = CommandGate.SIM_REJECTED
	var ok_seq: int = eng.set_pips(SubsystemDef.Kind.ENGINES, 2)
	var got: Dictionary = {}
	var rejected: Array[Dictionary] = []
	var all_in: Callable = func() -> bool:
		for e: Dictionary in _events_of(eng.take_events(), NetProtocol.EVENT_COMMAND_REJECTED):
			rejected.append(e)
			got[e["payload"]["seq"]] = e["payload"]["reason"]
		return got.size() >= expect.size()
	assert_bool(await _until(all_in)).is_true()
	await _wait(200)
	all_in.call()
	assert_dict(got).is_equal(expect)
	assert_bool(got.has(ok_seq)).is_false()
	for e: Dictionary in rejected:
		assert_int(e["tick"]).is_between(1, server.world.tick)
	assert_array(_events_of(other.take_events(), NetProtocol.EVENT_COMMAND_REJECTED)).is_empty()
	# The valid command reached the sim through submit and is in the command log.
	var logged: Array = server.world.accepted_commands().map(
		func(c: SimCommand) -> String: return c.kind()
	)
	assert_array(logged).contains([&"set_pips"])


# FT: FT-NET-006
# A client bursting commands past its token bucket gets rate_limited rejections; the
# rest go through.
func test_rate_limit_per_client() -> void:
	var server: NetServer = _server()
	var c: NetClient = await _joined(server, "spammer", "engineering")
	var calm: NetClient = await _joined(server, "calm", "engineering")
	for i: int in 400:
		c.set_pips(SubsystemDef.Kind.ENGINES, 1 + i % 2)
	calm.set_pips(SubsystemDef.Kind.SENSORS, 1)
	var limited: Array[int] = [0]
	var counted: Callable = func() -> bool:
		for e: Dictionary in _events_of(c.take_events(), NetProtocol.EVENT_COMMAND_REJECTED):
			if e["payload"]["reason"] == CommandGate.RATE_LIMITED:
				limited[0] += 1
		return limited[0] >= 150
	assert_bool(await _until(counted)).is_true()
	assert_int(limited[0]).is_less(400 - 150)
	assert_array(_events_of(calm.take_events(), NetProtocol.EVENT_COMMAND_REJECTED)).is_empty()


# FT: FT-NET-037, FT-NET-011
# A client that stops reading is marked stalled after more than 15 unacknowledged
# snapshots and gets no deltas; once it reads again it gets one full snapshot, and every
# event emitted meanwhile arrives in order, none lost.
func test_stalled_reader_gets_one_full_snapshot_and_every_event() -> void:
	var server: NetServer = _server()
	var gunner: NetClient = await _joined(server, "gunner", "weapons")
	var slow: NetClient = await _joined(server, "slow", "helm")
	await _wait(300)
	slow.take_events()
	var conn: int = slow.welcome["session"]
	slow.paused = true
	# Shots during the stall emit "fired" events to the ship's faction.
	for i: int in 6:
		gunner.fire()
		await _wait(150)
	var stats: Dictionary = server.transport.stats()
	var mine: Dictionary = _conn_of(stats, conn)
	assert_bool(mine["stalled"]).is_true()
	assert_int(mine["skipped"]).is_greater(0)
	var deltas_at_stall: int = mine["deltas"]
	await _wait(200)
	assert_int(_conn_of(server.transport.stats(), conn)["deltas"]).is_equal(deltas_at_stall)
	var fired: int = _events_of(gunner.take_events(), &"fired").size()
	assert_int(fired).is_greater(0)
	slow.paused = false
	var fulls_before: int = slow.stats["fulls"]
	assert_bool(await _until(func() -> bool: return slow.stats["fulls"] > fulls_before)).is_true()
	await _wait(500)
	assert_int(slow.stats["fulls"]).is_equal(fulls_before + 1)
	assert_int(slow.view.rejected).is_equal(0)
	var got: Array[Dictionary] = slow.take_events()
	assert_int(_events_of(got, &"fired").size()).is_equal(fired)
	for i: int in range(1, got.size()):
		assert_int(got[i]["seq"]).is_equal(got[i - 1]["seq"] + 1)
	assert_int(slow.inbox.waiting()).is_equal(0)
	assert_bool(_conn_of(server.transport.stats(), conn)["stalled"]).is_false()


func _conn_of(stats: Dictionary, session: int) -> Dictionary:
	for s: Dictionary in (stats["conns"] as Dictionary).values():
		if s["session"] == session:
			return s
	return {}


# FT: FT-NET-038
# Messages above the chunk size go in chunks, bundled per pump; a voice clip queued
# before a full snapshot goes on the low lane, so the snapshot arrives first and later
# snapshots slip between its chunks; the clip arrives intact. (The chunk size is lowered
# to 64 bytes so the M1 snapshot is "oversize"; tests/net/test_net_chunking.gd covers
# the 16 KiB default.)
func test_oversize_snapshot_and_voice_in_chunks_behind_snapshots() -> void:
	var server: NetServer = _server(64)
	var c: NetClient = await _joined(server, "viewer", "viewer")
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(6000)
	for i: int in pcm.size():
		pcm[i] = (i * 7) & 0xFF
	var arrived_before: int = c.arrivals.size()
	var session: int = c.welcome["session"]
	server.transport.post_voice(
		session, NetProtocol.encode(NetProtocol.Type.VOICE, {"clip": 7, "rate": 22050, "pcm": pcm})
	)
	server.transport.set_view(session, StationViews.key(PLAYER, "viewer"))
	assert_bool(await _until(func() -> bool: return c.stats["voice"] == 1)).is_true()
	assert_bool(c.voice_clips[0]["pcm"] == pcm).is_true()
	var order: PackedByteArray = c.arrivals.slice(arrived_before)
	var voice_at: int = order.find(NetChunker.STREAM_VOICE)
	assert_int(order.slice(0, voice_at).count(NetChunker.STREAM_SNAPSHOT)).is_greater_equal(2)
	assert_int(c.stats["fulls"]).is_equal(2)
	assert_int(c.view.rejected).is_equal(0)
	var mine: Dictionary = _conn_of(server.transport.stats(), session)
	assert_int(mine["ws_messages"]).is_greater(0)
	assert_int(c._chunker.errors).is_equal(0)


# FT: FT-NET-040
# Each snapshot is encoded once per distinct view key, not once per client, and every
# client of a key gets the same bytes; different keys get different messages.
func test_encode_once_per_view_key() -> void:
	var server: NetServer = _server()
	var entries: Array[String] = ["helm", "helm", "helm", "engineering", "engineering"]
	var clients: Array[NetClient] = []
	for i: int in entries.size():
		var c: NetClient = await _joined(server, "c%d" % i, entries[i])
		c.keep_raw = true
		clients.append(c)
	await _wait(200)
	var s0: Dictionary = server.transport.stats()
	await _wait(1000)
	var s1: Dictionary = server.transport.stats()
	var snapshots: int = s1["snapshots"] - s0["snapshots"]
	assert_int(snapshots).is_greater(15)
	assert_int(s1["delta_messages"] - s0["delta_messages"]).is_equal(2 * snapshots)
	assert_int(s1["full_messages"] - s0["full_messages"]).is_equal(0)
	assert_int(s1["sends"] - s0["sends"]).is_equal(5 * snapshots)
	var seq: int = s1["snapshot_seq"] - 2
	var has_seq: Callable = func(c: NetClient) -> bool: return c.raw_snapshots.has(seq)
	assert_bool(await _until(func() -> bool: return clients.all(has_seq))).is_true()
	assert_bool(clients[0].raw_snapshots[seq] == clients[1].raw_snapshots[seq]).is_true()
	assert_bool(clients[0].raw_snapshots[seq] == clients[2].raw_snapshots[seq]).is_true()
	assert_bool(clients[3].raw_snapshots[seq] == clients[4].raw_snapshots[seq]).is_true()
	assert_bool(clients[0].raw_snapshots[seq] == clients[3].raw_snapshots[seq]).is_false()


# FT: FT-NET-004
# A client that drops and presents its token gets the same session, pick and event
# stream back, with a full snapshot; the host secret marks the host (D127).
func test_resume_by_token_and_host_secret() -> void:
	var server: NetServer = _server(NetChunker.DEFAULT_CHUNK_SIZE, "c0ffee")
	var c: NetClient = _client(server, "host")
	c.host_secret = "c0ffee"
	assert_bool(await _until(c.is_welcomed)).is_true()
	c.pick(PLAYER, "engineering")
	assert_bool(await _until(func() -> bool: return c.stats["fulls"] >= 1)).is_true()
	var session: NetSession = server.session.by_id[c.session_id]
	assert_bool(session.is_host).is_true()
	assert_bool(c.welcome["host"]).is_true()
	c.set_pips(SubsystemDef.Kind.ENGINES, 99)
	assert_bool(await _until(func() -> bool: return c.inbox.last_seq >= 2)).is_true()
	var token: String = c.token
	var first: int = c.session_id
	c.drop()
	await _wait(200)
	assert_bool(session.connected()).is_false()
	c.resume()
	(
		assert_bool(await _until(func() -> bool: return c.is_welcomed() and c.stats["fulls"] >= 2))
		. is_true()
	)
	assert_bool(c.welcome["resumed"]).is_true()
	assert_str(c.token).is_equal(token)
	assert_int(c.session_id).is_equal(first)
	assert_str(c.welcome["entry"]).is_equal("engineering")
	assert_bool(c.view.blocks.has(StationViews.Section.ENGINEERING)).is_true()
	var guest: NetClient = _client(server, "guest")
	guest.host_secret = "wrong"
	assert_bool(await _until(guest.is_welcomed)).is_true()
	assert_bool(server.session.by_id[guest.session_id].is_host).is_false()
