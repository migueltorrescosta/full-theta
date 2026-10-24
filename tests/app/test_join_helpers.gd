extends GdUnitTestSuite
## FT: FT-NET-030
## JoinHelpers.config_from: the web join address and auto-join, without a browser.


func test_prefills_hostname_on_the_default_page_port() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.config_from("theta.local", 47800, "")
	assert_str(cfg.address).is_equal("theta.local")
	assert_bool(cfg.auto_join).is_false()


func test_hostname_without_a_port_in_the_url() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.config_from("192.168.1.5", 0, "")
	assert_str(cfg.address).is_equal("192.168.1.5")


func test_other_page_port_gives_websocket_port_plus_one() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.config_from("theta.local", 5000, "")
	assert_str(cfg.address).is_equal("theta.local:5001")
	assert_bool(LanBrowser.parse_address(cfg.address).ok).is_true()
	assert_int(LanBrowser.parse_address(cfg.address).port).is_equal(5001)


func test_ipv6_hostname_is_bracketed() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.config_from("fd00::1", 6000, "")
	assert_str(cfg.address).is_equal("[fd00::1]:6001")
	assert_int(LanBrowser.parse_address(cfg.address).port).is_equal(6001)


func test_join_flag_auto_joins() -> void:
	assert_bool(JoinHelpers.config_from("h", 47800, "?join=1").auto_join).is_true()
	assert_bool(JoinHelpers.config_from("h", 47800, "?x=2&join=1").auto_join).is_true()
	assert_bool(JoinHelpers.config_from("h", 47800, "?join=0").auto_join).is_false()
	assert_bool(JoinHelpers.config_from("h", 47800, "?nojoin=1").auto_join).is_false()


func test_empty_hostname_gives_nothing_even_with_join_flag() -> void:
	var cfg: JoinHelpers.WebJoinConfig = JoinHelpers.config_from("", 47800, "?join=1")
	assert_str(cfg.address).is_empty()
	assert_bool(cfg.auto_join).is_false()


func test_off_web_the_page_config_is_empty() -> void:
	if OS.has_feature("web"):
		return
	assert_str(JoinHelpers.web_config().address).is_empty()
