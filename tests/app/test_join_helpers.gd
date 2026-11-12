extends GdUnitTestSuite
## FT: FT-NET-030
## JoinHelpers.config_from: the web join address and auto-join, without a browser.


# FT: FT-NET-030
# The join address from the page's hostname and port: the default page port and no port keep
# the bare host, another page port gives the WebSocket port one above it, and an IPv6 literal
# is bracketed once (location.hostname may already carry the brackets).
func test_join_address_from_hostname_and_port() -> void:
	for c: Array in [
		["theta.local", 47800, "theta.local"],
		["192.168.1.5", 0, "192.168.1.5"],
		["theta.local", 5000, "theta.local:5001"],
		["fd00::1", 6000, "[fd00::1]:6001"],
		["[fd00::1]", 6000, "[fd00::1]:6001"],
	]:
		var address: String = JoinHelpers.config_from(c[0], c[1], "").address
		assert_str(address).override_failure_message(str(c)).is_equal(c[2])
		if c[1] != 0 and c[1] != 47800:
			assert_int(LanBrowser.parse_address(address).port).is_equal(c[1] + 1)


func test_join_is_automatic_unless_switched_off() -> void:
	assert_bool(JoinHelpers.config_from("h", 47800, "").auto_join).is_true()
	assert_bool(JoinHelpers.config_from("h", 47800, "?join=1").auto_join).is_true()
	assert_bool(JoinHelpers.config_from("h", 47800, "?x=2&join=1").auto_join).is_true()
	assert_bool(JoinHelpers.config_from("h", 47800, "?join=0").auto_join).is_false()
	assert_bool(JoinHelpers.config_from("h", 47800, "?x=1&join=0").auto_join).is_false()
	assert_bool(JoinHelpers.config_from("h", 47800, "?nojoin=0").auto_join).is_true()


func test_test_hooks_name_a_station_and_ready() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.config_from(
		"h", 47800, "?pick=tactical&ready=1"
	)
	assert_str(cfg.pick).is_equal("tactical")
	assert_bool(cfg.ready).is_true()
	assert_str(JoinHelpers.config_from("h", 47800, "").pick).is_empty()
	assert_bool(JoinHelpers.config_from("h", 47800, "?ready=0").ready).is_false()


func test_empty_hostname_gives_nothing_to_join() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.config_from("", 47800, "?join=1")
	assert_str(cfg.address).is_empty()
	assert_bool(cfg.auto_join).is_false()
