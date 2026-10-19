extends GdUnitTestSuite
## T047: LAN discovery beacon and browser (FT-NET-012, FT-NET-013). Socket tests use
## an ephemeral browser port and send the beacon to 127.0.0.1, so parallel runs don't
## clash and no broadcast leaves the machine.

const PROTO: int = 7

var _beacon: LanBeacon
var _browser: LanBrowser


func after_test() -> void:
	if _beacon != null:
		_beacon.stop()
		_beacon = null
	if _browser != null:
		_browser.stop()
		_browser = null


## Polls the browser until it lists a host or 2 s pass (wall clock).
func _wait_for_host(now_usec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		_browser.poll(now_usec)
		if not _browser.hosts().is_empty():
			return true
		OS.delay_msec(5)
	return false


# FT: FT-NET-012, FT-NET-013
func test_loopback_beacon_is_listed_with_its_fields() -> void:
	_browser = LanBrowser.new(PROTO)
	assert_int(_browser.start(0, "127.0.0.1")).is_equal(OK)
	var port: int = _browser.local_port()
	assert_int(port).is_greater(0)
	_beacon = LanBeacon.new(PROTO, "Bridge of Theta", 47821)
	_beacon.players = 5
	_beacon.player_cap = 64
	_beacon.session_running = true
	assert_int(_beacon.start(port, PackedStringArray(["127.0.0.1"]))).is_equal(OK)
	assert_bool(_beacon.poll(1_000_000)).is_true()
	assert_bool(_wait_for_host(1_000_000)).is_true()
	var hosts: Array[LanBrowser.Host] = _browser.hosts()
	assert_int(hosts.size()).is_equal(1)
	var h: LanBrowser.Host = hosts[0]
	assert_str(h.address).is_equal("127.0.0.1")
	assert_str(h.name).is_equal("Bridge of Theta")
	assert_int(h.ws_port).is_equal(47821)
	assert_int(h.http_port).is_equal(47820)  # D108: WS = HTTP + 1
	assert_int(h.players).is_equal(5)
	assert_int(h.cap).is_equal(64)
	assert_bool(h.running).is_true()
	assert_bool(h.compatible).is_true()
	assert_str(h.url()).is_equal("ws://127.0.0.1:47821")


# FT: FT-NET-012
func test_beacon_sends_once_a_second() -> void:
	_beacon = LanBeacon.new(PROTO, "s", 40001)
	# Never polled into a socket that matters: port 9 (discard) on loopback.
	_beacon.start(9, PackedStringArray(["127.0.0.1"]))
	var t0: int = 5_000_000
	var sends: int = 0
	for ms: int in range(0, 3100, 16):  # a 60 Hz server loop for 3.1 s
		if _beacon.poll(t0 + ms * 1000):
			sends += 1
	assert_int(sends).is_equal(4)  # at 0, 1.008, 2.016 and 3.024 s
	# A stalled loop sends once, not a burst.
	assert_bool(_beacon.poll(t0 + 10_000_000)).is_true()
	assert_bool(_beacon.poll(t0 + 10_000_001)).is_false()


# FT: FT-NET-012
func test_encode_decode_round_trip_and_name_truncation() -> void:
	var b: LanBeacon = LanBeacon.new(123456, "Ω".repeat(40), 47801, 47800)
	b.players = 300  # clamped to a byte
	var d: Dictionary = LanBeacon.decode(b.encode())
	assert_int(d["protocol"]).is_equal(123456)
	assert_int(d["ws_port"]).is_equal(47801)
	assert_int(d["http_port"]).is_equal(47800)
	assert_int(d["players"]).is_equal(255)
	assert_bool(d["running"]).is_false()
	# Ω is 2 UTF-8 bytes: 63 bytes hold 31 whole characters.
	assert_str(d["name"]).is_equal("Ω".repeat(31))
	# A newer format with extra trailing fields still parses.
	var newer: PackedByteArray = b.encode()
	newer[4] = 2
	newer.append_array(PackedByteArray([1, 2, 3]))
	assert_int(LanBeacon.decode(newer)["ws_port"]).is_equal(47801)


# FT: FT-NET-013
func test_malformed_and_wrong_magic_packets_are_ignored() -> void:
	_browser = LanBrowser.new(PROTO)
	var good: PackedByteArray = LanBeacon.new(PROTO, "ok", 47801).encode()
	var wrong_magic: PackedByteArray = good.duplicate()
	wrong_magic[0] = 0x58
	var short: PackedByteArray = good.slice(0, 10)
	var name_overrun: PackedByteArray = good.duplicate()
	name_overrun[16] = 60
	var zero_format: PackedByteArray = good.duplicate()
	zero_format[4] = 0
	var zero_port: PackedByteArray = good.duplicate()
	zero_port.encode_u16(9, 0)
	var bad: Array[PackedByteArray] = [
		PackedByteArray(),
		short,
		wrong_magic,
		name_overrun,
		zero_format,
		zero_port,
		"hello".to_utf8_buffer(),
	]
	for p: PackedByteArray in bad:
		assert_bool(_browser.ingest(p, "10.0.0.2", 1)).is_false()
	assert_int(_browser.ignored).is_equal(bad.size())
	assert_array(_browser.hosts()).is_empty()
	assert_bool(_browser.ingest(good, "10.0.0.2", 1)).is_true()
	assert_int(_browser.hosts().size()).is_equal(1)


# FT: FT-NET-013
func test_mismatched_protocol_is_listed_as_incompatible() -> void:
	_browser = LanBrowser.new(PROTO)
	_browser.ingest(LanBeacon.new(PROTO + 1, "newer", 47801).encode(), "10.0.0.3", 1)
	_browser.ingest(LanBeacon.new(PROTO, "same", 47801).encode(), "10.0.0.4", 1)
	var hosts: Array[LanBrowser.Host] = _browser.hosts()
	assert_int(hosts.size()).is_equal(2)
	assert_str(hosts[0].name).is_equal("same")
	assert_bool(hosts[0].compatible).is_true()
	assert_str(hosts[1].name).is_equal("newer")
	assert_bool(hosts[1].compatible).is_false()


# FT: FT-NET-013
func test_hosts_keyed_by_address_and_port_and_expire() -> void:
	_browser = LanBrowser.new(PROTO)
	var a: LanBeacon = LanBeacon.new(PROTO, "a", 47801)
	var a2: LanBeacon = LanBeacon.new(PROTO, "a2", 47811)
	var t: int = 100_000_000
	assert_bool(_browser.ingest(a.encode(), "10.0.0.5", t)).is_true()
	assert_bool(_browser.ingest(a2.encode(), "10.0.0.5", t)).is_true()
	assert_bool(_browser.ingest(a.encode(), "10.0.0.6", t)).is_true()
	assert_int(_browser.hosts().size()).is_equal(3)
	# A repeat beacon refreshes last-seen without reporting a change.
	assert_bool(_browser.ingest(a.encode(), "10.0.0.5", t + 2_000_000)).is_false()
	a.players = 2
	assert_bool(_browser.ingest(a.encode(), "10.0.0.5", t + 2_000_000)).is_true()
	# At t + 3.5 s nothing has expired yet; just after, the two silent hosts go.
	assert_bool(_browser.poll(t + LanBrowser.EXPIRY_USEC)).is_false()
	assert_bool(_browser.poll(t + LanBrowser.EXPIRY_USEC + 1)).is_true()
	var hosts: Array[LanBrowser.Host] = _browser.hosts()
	assert_int(hosts.size()).is_equal(1)
	assert_str(hosts[0].key()).is_equal("10.0.0.5|47801")
	assert_bool(_browser.poll(t + 2_000_000 + LanBrowser.EXPIRY_USEC + 1)).is_true()
	assert_array(_browser.hosts()).is_empty()
