extends GdUnitTestSuite
## WebLoadStage and where the client reports it (#11, DC2): the loading screen's stages after
## the download. The page's side is checked in test_shell_html.gd and, in a real browser,
## by the L6 tier (tools/l6/web_load.mjs).

const MAIN_MENU: String = "res://app/main_menu.gd"
const WEB_SESSION: String = "res://app/web/web_session.gd"


# FT: FT-NET-030
# Off the web nothing is reported (and nothing fails), so desktop clients and tests can call it.
func test_reporting_a_stage_is_a_no_op_off_the_web() -> void:
	for stage: String in WebLoadStage.STAGES:
		WebLoadStage.report(stage)
	assert_bool(OS.has_feature("web")).is_false()


# FT: FT-NET-030
# The menu reports "connect" when it starts joining, "lobby" when welcomed, and "ready" when
# joining cannot go on (a failed connect, a rejection, a bad address, ?join=0), so the page's
# loading screen never hides the menu's message.
func test_the_menu_reports_each_stage_where_it_happens() -> void:
	var src: String = FileAccess.get_file_as_string(MAIN_MENU)
	assert_int(src.count("WebLoadStage.report(WebLoadStage.CONNECT)")).is_equal(1)
	assert_int(src.count("WebLoadStage.report(WebLoadStage.LOBBY)")).is_equal(1)
	assert_int(src.count("WebLoadStage.report(WebLoadStage.READY)")).is_equal(4)
	var connect_at: int = src.find("WebLoadStage.report(WebLoadStage.CONNECT)")
	assert_int(connect_at).is_less(src.find("joining.connect_to(url)"))
	var shell_at: int = src.find("func _start_shell")
	assert_int(src.find("WebLoadStage.report(WebLoadStage.LOBBY)")).is_greater(shell_at)
	assert_int(src.find("WebLoadStage.report(WebLoadStage.LOBBY)")).is_less(
		src.find("shell = ClientShell.new()")
	)


# FT: FT-NET-030
# The browser session reports "ready" when it first tells the page its panel, i.e. the lobby is up.
func test_the_session_reports_ready_with_the_first_panel() -> void:
	var src: String = FileAccess.get_file_as_string(WEB_SESSION)
	var panel_at: int = src.find("WebPage.set_panel(panel)")
	assert_int(panel_at).is_greater(0)
	var ready_at: int = src.find("WebLoadStage.report(WebLoadStage.READY)")
	assert_int(ready_at).is_greater(panel_at)
	assert_int(ready_at - panel_at).is_less(60)
