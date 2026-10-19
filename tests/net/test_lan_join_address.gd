extends GdUnitTestSuite
## T047: manual IP join (FT-NET-013). JoinAddress.parse turns typed input into a
## ws:// URL with the default WebSocket port, or a reason.


# FT: FT-NET-013
func test_accepted_addresses() -> void:
	var d: int = JoinAddress.DEFAULT_WS_PORT
	var cases: Array[Array] = [
		["192.168.1.20", "ws://192.168.1.20:%d" % d],
		["  10.0.0.7  ", "ws://10.0.0.7:%d" % d],
		["10.0.0.7:47900", "ws://10.0.0.7:47900"],
		["localhost", "ws://localhost:%d" % d],
		["theta-host", "ws://theta-host:%d" % d],
		["theta-host.local:5000", "ws://theta-host.local:5000"],
		["::1", "ws://[::1]:%d" % d],
		["fe80::1c2b:3aff:fe4d:1", "ws://[fe80::1c2b:3aff:fe4d:1]:%d" % d],
		["[::1]", "ws://[::1]:%d" % d],
		["[2001:db8::5]:47801", "ws://[2001:db8::5]:47801"],
		["ws://10.0.0.7:47801", "ws://10.0.0.7:47801"],
		["WS://host/", "ws://host:%d" % d],
		["host:1", "ws://host:1"],
		["host:65535", "ws://host:65535"],
	]
	for c: Array in cases:
		var r: JoinAddress = JoinAddress.parse(c[0])
		assert_bool(r.ok).override_failure_message("%s: %s" % [c[0], r.error]).is_true()
		assert_str(r.url).override_failure_message(c[0]).is_equal(c[1])


# FT: FT-NET-013
func test_default_port_parameter() -> void:
	assert_str(JoinAddress.parse("10.1.2.3", 1234).url).is_equal("ws://10.1.2.3:1234")


# FT: FT-NET-013
func test_rejected_addresses_have_a_reason() -> void:
	var bad: Array[String] = [
		"",
		"   ",
		"host:",
		":47800",
		"host:0",
		"host:65536",
		"host:+80",
		"host:abc",
		"256.1.1.1",
		"10.0.0",
		"1.2.3.4.5",
		"-host",
		"host-",
		"ho_st",
		"a..b",
		"two words",
		"user@host",
		"host/path",
		"http://10.0.0.7:47820/",
		"wss://host",
		"[::1",
		"[::1]x",
		"[10.0.0.1]",
		"1:2:3:4:5:6:7:8:9",
		"gggg::1",
		"x".repeat(64),
	]
	for s: String in bad:
		var r: JoinAddress = JoinAddress.parse(s)
		assert_bool(r.ok).override_failure_message("accepted %s" % s).is_false()
		assert_str(r.error).override_failure_message("no reason for %s" % s).is_not_empty()
		assert_str(r.url).is_empty()
