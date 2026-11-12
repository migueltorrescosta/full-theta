extends GdUnitTestSuite
## The protocol's message set (T040): every control message round-trips through the
## codec, the schema rejects anything else, the handshake carries the version, and
## events carry their tick.


## One valid instance of every control message.
func _samples() -> Dictionary:
	return {
		NetProtocol.Type.HELLO:
		{"v": 1, "token": "ab", "name": "Ana", "kind": "desktop", "host_secret": ""},
		NetProtocol.Type.WELCOME:
		{
			"v": 1,
			"token": "ab",
			"session": 3,
			"resumed": false,
			"tick": 120,
			"period": 200000.0,
			"ev_from": 0,
			"ship": -1,
			"seat": "",
			"dev_all": false,
			"host": false,
			"lang": "en",
			"tls": false,
		},
		NetProtocol.Type.HELLO_REJECTED: {"v": 1, "reason": "session_full"},
		NetProtocol.Type.CATALOGUE:
		{
			"ships": [{"id": 0, "def": "m1_corvette", "name": "Corvette", "faction": 1}],
			"seats": [{"id": "helm", "name": "Helm", "stations": ["helm"]}],
			"load_tags": [],
		},
		NetProtocol.Type.PICK: {"ship": 0, "seat": "tactical"},
		NetProtocol.Type.RELEASE: {},
		NetProtocol.Type.READY: {"ready": true},
		NetProtocol.Type.CLAIM: {"item": "mount:0"},
		NetProtocol.Type.RELEASE_CLAIM: {"item": "mount:0"},
		NetProtocol.Type.COMMAND: {"seq": 9, "cmd": {"kind": "fire", "mount_index": 0}},
		NetProtocol.Type.ACK: {"snap": 40, "ev": 12},
		NetProtocol.Type.EVENT: {"seq": 4, "tick": 361, "type": "hit", "payload": {"ship": 0}},
		NetProtocol.Type.ABANDON: {"ship": 0},
		NetProtocol.Type.TAKEOVER: {"ship": 0, "seat": "helm"},
		NetProtocol.Type.BYE: {"reason": "quit"},
		NetProtocol.Type.VOICE:
		{
			"clip": 2,
			"rate": 22050,
			"pcm": PackedByteArray([1, 2, 3]),
			"part": 0,
			"last": true,
		},
		NetProtocol.Type.ABANDON_VOTE: {"ship": 0, "vote": true},
		NetProtocol.Type.ALERT: {"level": 2},
		# x keeps 64 bits (D104).
		NetProtocol.Type.MARK:
		{
			"op": "place",
			"slot": -1,
			"name": "",
			"contact": -1,
			"x": 98765.4321012345,
			"y": -0.5,
			"z": 3.0,
		},
		NetProtocol.Type.PING: {"kind": "contact", "id": 1, "x": 0.0, "y": 0.0, "z": 0.0},
		NetProtocol.Type.RUN_AGAIN: {"ship": 0, "vote": true},
		NetProtocol.Type.MAIN_VIEW: {"view": 3},
		NetProtocol.Type.MARK_SEND: {"slot": 2, "ship": 1},
		NetProtocol.Type.MARK_ACCEPT: {"id": 7, "accept": true, "slot": -1},
		NetProtocol.Type.TOGGLES: {"set": "normal:11111000"},
		NetProtocol.Type.CHIP:
		{"op": "send", "chip": "bring_to_bear", "arg": 2, "id": -1, "accept": false},
		NetProtocol.Type.CLIENT_STATS: {"sent_us": 5, "ua": "x", "pairs": PackedInt64Array([1, 2])},
		NetProtocol.Type.SHARE: {"feature": "routes"},
		NetProtocol.Type.HOST_PAUSE: {"on": true},
		NetProtocol.Type.SHIP_ADD: {"name": "Kestrel II"},
		NetProtocol.Type.SHIP_TEAM: {"ship": 2, "team": 1},
		NetProtocol.Type.GAME_MODE: {"mode": "teams", "team_win": "first_to_finish", "lives": -1},
		NetProtocol.Type.RELAUNCH: {"ship": 1, "vote": true},
		NetProtocol.Type.CLIENT_FRAME: {"ms": 812, "what": "build station:0:helm"},
		NetProtocol.Type.TRAINING: {"station": "helm"},
		NetProtocol.Type.RENAME: {"name": "Ana"},
		NetProtocol.Type.START: {},
	}


# FT: FT-NET-004
func test_every_control_message_round_trips() -> void:
	assert_int(_samples().size()).is_equal(NetProtocol.MESSAGES.size())
	var samples: Dictionary = _samples()
	for type: int in samples:
		var fields: Dictionary = samples[type]
		var back: Dictionary = NetProtocol.decode(NetProtocol.encode(type, fields))
		assert_int(back.get("t", -1)).is_equal(type)
		back.erase("t")
		assert_dict(back).is_equal(fields)


# FT: FT-NET-004
func test_schema_rejects_other_shapes() -> void:
	var hello: Dictionary = _samples()[NetProtocol.Type.HELLO]
	var extra: Dictionary = hello.duplicate()
	extra["admin"] = true
	var missing: Dictionary = hello.duplicate()
	missing.erase("name")
	var wrong: Dictionary = hello.duplicate()
	wrong["token"] = 7
	for fields: Dictionary in [extra, missing, wrong]:
		(
			assert_dict(NetProtocol.decode(NetProtocol.encode(NetProtocol.Type.HELLO, fields)))
			. is_empty()
		)
	# Unknown types, a non-Dictionary body, garbage and an empty message.
	assert_dict(NetProtocol.decode(PackedByteArray([99, 0, 0, 0, 0]))).is_empty()
	var not_dict: PackedByteArray = PackedByteArray([NetProtocol.Type.ACK])
	not_dict.append_array(var_to_bytes([1, 2]))
	assert_dict(NetProtocol.decode(not_dict)).is_empty()
	assert_dict(NetProtocol.decode(PackedByteArray([NetProtocol.Type.ACK, 1, 2, 3]))).is_empty()
	assert_dict(NetProtocol.decode(PackedByteArray())).is_empty()
	# Objects are never decoded.
	var with_object: PackedByteArray = PackedByteArray([NetProtocol.Type.BYE])
	with_object.append_array(var_to_bytes_with_objects({"reason": RefCounted.new()}))
	assert_dict(NetProtocol.decode(with_object)).is_empty()


# FT: FT-NET-005
# The handshake carries the protocol version, readable whatever else a Hello holds.
func test_hello_carries_the_protocol_version() -> void:
	var hello: PackedByteArray = NetProtocol.hello("", "Ana", "desktop")
	assert_int(NetProtocol.decode(hello)["v"]).is_equal(NetProtocol.PROTOCOL_VERSION)
	assert_int(NetProtocol.hello_version(hello)).is_equal(NetProtocol.PROTOCOL_VERSION)
	var future: PackedByteArray = NetProtocol.encode(NetProtocol.Type.HELLO, {"v": 7, "caps": []})
	assert_dict(NetProtocol.decode(future)).is_empty()
	assert_int(NetProtocol.hello_version(future)).is_equal(7)
	assert_int(NetProtocol.hello_version(NetProtocol.ack(1, 1))).is_equal(-1)
	var rejected: Dictionary = NetProtocol.decode(
		NetProtocol.hello_rejected(NetProtocol.REJECT_VERSION)
	)
	assert_str(rejected["reason"]).is_equal(NetProtocol.REJECT_VERSION)


# FT: FT-NET-004
# A Hello's kind must be desktop, web or bot; its name is trimmed and cut to 32 bytes of
# UTF-8 between characters.
func test_hello_kind_and_name_are_checked() -> void:
	for kind: String in NetProtocol.CLIENT_KINDS:
		assert_dict(NetProtocol.decode(NetProtocol.hello("", "Ana", kind))).is_not_empty()
	assert_dict(NetProtocol.decode(NetProtocol.hello("", "Ana", "admin"))).is_empty()
	assert_dict(NetProtocol.decode(NetProtocol.hello("", "Ana", ""))).is_empty()
	var name_of: Callable = func(name: String) -> String:
		return NetProtocol.decode(NetProtocol.hello("", name, "bot"))["name"]
	assert_str(name_of.call("  Ana  ")).is_equal("Ana")
	assert_str(name_of.call("x".repeat(60000))).is_equal("x".repeat(32))
	# 31 ASCII bytes and a 2-byte letter: the letter doesn't fit and goes whole.
	assert_str(name_of.call("a".repeat(31) + "é")).is_equal("a".repeat(31))
	assert_str(name_of.call("é".repeat(20))).is_equal("é".repeat(16))
	assert_str(name_of.call("a".repeat(31) + " b")).is_equal("a".repeat(31))


# FT: FT-NET-011
# Reliable ordered events carry their sequence number and the sim tick.
func test_events_carry_seq_and_tick() -> void:
	var e: Dictionary = NetProtocol.decode(
		NetProtocol.event(5, 1234, NetProtocol.EVENT_COMMAND_REJECTED, {"seq": 2, "reason": "x"})
	)
	assert_int(e["seq"]).is_equal(5)
	assert_int(e["tick"]).is_equal(1234)
	assert_str(e["type"]).is_equal(NetProtocol.EVENT_COMMAND_REJECTED)
	assert_dict(e["payload"]).is_equal({"seq": 2, "reason": "x"})


# FT: FT-NET-004
# Snapshots are packed binary with a fixed header the client can peek.
func test_snapshot_header() -> void:
	var world: SimWorld = (
		M1Encounter.new(1, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()
	)
	world.step()
	var b: SnapshotWriter = SnapshotWriter.new()
	var key: String = StationCatalogue.key(0, "helm")
	b.build(SimCopy.of(world), 77, [key])
	var bytes: PackedByteArray = b.message(key, true)
	assert_int(NetProtocol.type_of(bytes)).is_equal(NetProtocol.Type.SNAPSHOT)
	assert_array(SnapshotReader.peek(bytes)).is_equal([77, true, 1])
	assert_dict(NetProtocol.decode(bytes)).is_empty()
	var snap: SnapshotState = SnapshotState.new(NetCodec.period_units(world.kin.period))
	assert_bool(snap.apply(bytes)).is_true()
	assert_array(snap.kinds).is_equal(StationCatalogue.sections_of("helm"))


# FT: FT-NET-004
# G6: NetProtocol.MESSAGES is the one table; what a client may send and what takes a rate-limit
# token derive from it. Hello, Ack, Bye and Command are sent but not rated, and every rated
# type is sent.
func test_the_sets_derive_from_one_table() -> void:
	for type: int in NetProtocol.rated_requests:
		assert_bool(NetProtocol.from_client.has(type)).is_true()
	for type: int in [NetProtocol.Type.HELLO, NetProtocol.Type.ACK, NetProtocol.Type.BYE]:
		assert_bool(NetProtocol.from_client.has(type)).is_true()
		assert_bool(NetProtocol.rated_requests.has(type)).is_false()
	assert_bool(NetProtocol.from_client.has(NetProtocol.Type.COMMAND)).is_true()
	assert_bool(NetProtocol.rated_requests.has(NetProtocol.Type.COMMAND)).is_false()
	for type: int in [NetProtocol.Type.WELCOME, NetProtocol.Type.EVENT, NetProtocol.Type.CATALOGUE]:
		assert_bool(NetProtocol.from_client.has(type)).is_false()
	assert_bool(NetProtocol.rated_requests.has(NetProtocol.Type.RENAME)).is_true()


# FT: FT-NET-004
# G6: one clean_text cuts every player-chosen name (Hello, Rename and ShipAdd) the same way:
# trimmed, cut to 32 bytes between characters, trimmed again.
func test_names_are_cleaned_in_one_place() -> void:
	assert_str(NetProtocol.clean_text("  Ana  ", 32)).is_equal("Ana")
	assert_str(NetProtocol.clean_text("é".repeat(40), 32)).is_equal("é".repeat(16))
	assert_str(NetProtocol.clean_text("a".repeat(31) + " b", 32)).is_equal("a".repeat(31))
	for type: int in [NetProtocol.Type.RENAME, NetProtocol.Type.SHIP_ADD]:
		var padded: String = "   " + "k".repeat(40)
		var back: Dictionary = NetProtocol.decode(NetProtocol.encode(type, {"name": padded}))
		assert_str(back["name"]).is_equal("k".repeat(32))
