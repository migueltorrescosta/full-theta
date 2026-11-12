extends GdUnitTestSuite
## Room hardware events over OSC (FT-NET-047): LAN targets only, OSC 1.0 bytes, the crewed
## ships' hits, jumps, destruction and alert level, hits rate-limited, off by default.


func _event(kind: StringName, ship: int, value: float = 0.0) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = kind
	e.ship_id = ship
	e.value = value
	return e


func _normal(_ship: int) -> int:
	return CrewMarks.ALERT_NORMAL


# FT: FT-NET-047
func test_only_lan_ipv4_targets_are_accepted() -> void:
	var e: OscEmitter = OscEmitter.new()
	assert_str(e.set_targets("192.168.1.30:7700,10.0.0.5:9000, 127.0.0.1:53000")).is_empty()
	for ok: String in ["172.16.0.1", "172.31.255.255", "169.254.3.4"]:
		assert_bool(OscEmitter.is_lan(ok)).is_true()
	for bad: String in ["8.8.8.8", "172.32.0.1", "100.64.0.1", "192.169.0.1", "fe80::1", "x"]:
		assert_bool(OscEmitter.is_lan(bad)).override_failure_message(bad).is_false()
	assert_str(e.set_targets("8.8.8.8:9000")).contains("not a LAN address")
	assert_str(e.set_targets("192.168.1.30")).contains("IPv4:PORT")
	assert_str(e.set_targets("192.168.1.30:0")).contains("port")
	assert_str(e.set_targets("")).contains("no targets")
	var many: PackedStringArray = PackedStringArray()
	for i: int in OscEmitter.MAX_TARGETS + 1:
		many.append("10.0.0.%d:9000" % (i + 1))
	assert_str(e.set_targets(",".join(many))).contains("at most")


# FT: FT-NET-047
func test_encodes_osc_1_0_messages() -> void:
	# "/ft/ship/0/hit" is 14 bytes: 16 with its NUL and padding; ",fi" is 4 with its NUL.
	var b: PackedByteArray = OscEmitter.encode("/ft/ship/0/hit", [1.0, 7])
	var expected: PackedByteArray = "/ft/ship/0/hit".to_ascii_buffer()
	expected.append_array([0, 0, 0x2C, 0x66, 0x69, 0, 0x3F, 0x80, 0, 0, 0, 0, 0, 7])
	assert_array(Array(b)).is_equal(Array(expected))
	assert_int(OscEmitter.encode("/abc", []).size()).is_equal(12)


# FT: FT-NET-047
func test_events_of_crewed_ships_become_messages_and_hits_are_rate_limited() -> void:
	var e: OscEmitter = OscEmitter.new()
	var hit: Array[Array] = e.messages_for(_event(&"hit", 0, 250.0), 0)
	assert_array(hit).is_equal([["/ft/ship/0/hit", [1.0, 250.0]]])
	assert_array(e.messages_for(_event(&"hit", 0, 1.0), 50_000)).is_empty()
	assert_array(e.messages_for(_event(&"hit", 0, 1.0), 100_000)).is_not_empty()
	assert_array(e.messages_for(_event(&"jump_spool", 1), 0)).is_equal([["/ft/ship/1/jump", [1.0]]])
	assert_array(e.messages_for(_event(&"jump_arrive", 1), 0)).is_equal(
		[["/ft/ship/1/jump", [0.0]]]
	)
	assert_array(e.messages_for(_event(&"destroyed", 0), 0)).is_equal(
		[["/ft/ship/0/destroyed", [1.0]]]
	)
	assert_array(e.messages_for(_event(&"scan_done", 0), 0)).is_empty()


# FT: FT-NET-047
# A real datagram reaches a socket the test opens (the game itself never reads one): NPC
# events are left out, and an alert change goes once.
func test_sends_udp_datagrams_to_the_targets() -> void:
	var rx: PacketPeerUDP = PacketPeerUDP.new()
	assert_int(rx.bind(0, "127.0.0.1")).is_equal(OK)
	var e: OscEmitter = OscEmitter.from_list("127.0.0.1:%d" % rx.get_local_port())
	var level: Array[int] = [CrewMarks.ALERT_NORMAL]
	var alert_of: Callable = func(_ship: int) -> int: return level[0]
	var crew: PackedInt32Array = PackedInt32Array([0])
	var events: Array[SimEvent] = [_event(&"destroyed", 3), _event(&"jump_spool", 0)]
	e.after_ticks(events, crew, alert_of, 0)
	level[0] = CrewMarks.ALERT_RED
	e.after_ticks([], crew, alert_of, 1)
	e.after_ticks([], crew, alert_of, 2)
	assert_int(e.sent).is_equal(2)
	var got: Array[PackedByteArray] = []
	for i: int in 50:
		while rx.get_available_packet_count() > 0:
			got.append(rx.get_packet())
		if got.size() >= 2:
			break
		OS.delay_msec(10)
	rx.close()
	assert_array(got).is_equal(
		[
			OscEmitter.encode("/ft/ship/0/jump", [1.0]),
			OscEmitter.encode("/ft/ship/0/alert", [1.0, 2])
		]
	)


# FT: FT-NET-047
# Off by default; --osc turns it on and refuses a bad list.
func test_the_server_flag_turns_it_on() -> void:
	var cli: ServerMain = ServerMain.new()
	assert_bool(cli.parse_args(["--server", "--bind", "127.0.0.1"])).is_true()
	assert_str(cli.osc_targets).is_empty()
	cli = ServerMain.new()
	var args: PackedStringArray = ["--server", "--bind", "127.0.0.1", "--port", "0"]
	args.append_array(["--osc", "127.0.0.1:9000", "--encounter", "m1"])
	assert_bool(cli.parse_args(args)).is_true()
	var server: NetServer = cli.make_server()
	assert_object(server.osc).is_not_null()
	server.transport.stop()
	server.free()
	(
		assert_bool(
			ServerMain.new().parse_args(["--server", "--bind", "127.0.0.1", "--osc", "1.1.1.1:9"])
		)
		. is_false()
	)


# FT: FT-NET-047, FT-DAT-015
# A game hosted from the menu passes the client's --osc and --packs on to its server.
func test_the_host_button_forwards_osc_and_packs() -> void:
	var client: PackedStringArray = ["--dev", "--osc", "10.0.0.2:9000", "--packs", "/p", "--osc"]
	assert_array(Array(HostLauncher.forwarded(client))).is_equal(
		["--osc", "10.0.0.2:9000", "--packs", "/p"]
	)
