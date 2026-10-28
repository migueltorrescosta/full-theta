extends GdUnitTestSuite
## The lobby's way out and the host's join info: "Back to ships", "Main menu" and the
## "How to join" panel with the QR code.

const URL: String = "http://192.168.1.20:47800/?join=1"


func before() -> void:
	I18n.apply("en")


func _lobby(bind: String = "", port: int = 47801) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context("helm")
	ctx.crew.lobby[0]["started"] = false
	ctx.host_bind = bind
	ctx.host_port = port
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	return l


func _button(l: LobbyScreen, node_name: String) -> Button:
	return l.find_child(node_name, true, false)


# FT: FT-NET-015
# "Back to ships" sends the release (the server answers it with a `picked` event of no
# ship, see test_net_lobby_l3) and shows the ship list alone, with no ship chosen, until
# the player picks a ship again. Before, the button sent the release and the screen
# kept showing the same ship's seats, so nothing seemed to happen.
func test_back_to_ships_releases_the_seat_and_returns_to_ship_selection() -> void:
	var l: LobbyScreen = _lobby()
	var entries: Control = l.find_child("Body", true, false)
	assert_bool(entries.visible).is_true()
	_button(l, "BackToShips").pressed.emit()
	assert_int(StationFixture.sent(l.ctx).of("release_pick").size()).is_equal(1)
	assert_bool(entries.visible).is_false()
	assert_bool(_button(l, "Start").visible).is_false()
	assert_int(l.ship).is_equal(-1)
	# The server's answer must not bring the old ship back.
	l.ctx.crew.handle_event({"type": "picked", "payload": {"ship": -1, "entry": ""}}, 0)
	assert_bool(entries.visible).is_false()
	assert_int(l.ship).is_equal(-1)
	# Choosing a ship shows its seats again.
	var ship_name: String = str(l.ctx.crew.catalogue["ships"][0]["name"])
	for b: Node in l.find_children("*", "Button", true, false):
		if (b as Button).text == ship_name:
			(b as Button).pressed.emit()
	assert_bool(entries.visible).is_true()
	assert_int(l.ship).is_equal(int(l.ctx.crew.catalogue["ships"][0]["id"]))


# FT: FT-NET-003
func test_main_menu_button_asks_the_shell_to_leave() -> void:
	var l: LobbyScreen = _lobby()
	var asked: Array[bool] = []
	l.menu_requested.connect(func() -> void: asked.append(true))
	_button(l, "MainMenu").pressed.emit()
	assert_array(asked).has_size(1)
	# Back to ships is not leaving.
	_button(l, "BackToShips").pressed.emit()
	assert_array(asked).has_size(1)


# FT: FT-NET-013
func test_host_lobby_shows_url_address_and_qr() -> void:
	var l: LobbyScreen = _lobby("192.168.1.20")
	assert_str((l.find_child("JoinUrl", true, false) as Label).text).contains(URL)
	assert_str((l.find_child("JoinDesktop", true, false) as Label).text).contains("192.168.1.20")
	var qr: QrView = l.find_child("JoinQr", true, false)
	assert_array(qr.modules).is_equal(QrCode.encode(URL))
	assert_object(l.find_child("JoinLocal", true, false)).is_null()


# FT: FT-NET-013
func test_loopback_host_says_nobody_else_can_join_and_shows_no_qr() -> void:
	var l: LobbyScreen = _lobby("127.0.0.1")
	assert_str((l.find_child("JoinLocal", true, false) as Label).text).contains("127.0.0.1")
	assert_object(l.find_child("JoinQr", true, false)).is_null()
	assert_object(l.find_child("JoinUrl", true, false)).is_null()


# FT: FT-NET-013
func test_a_joined_player_sees_no_join_panel() -> void:
	assert_object(_lobby().find_child("JoinPanel", true, false)).is_null()


# FT: FT-NET-013
func test_join_url_uses_the_http_port_below_the_websocket_port() -> void:
	assert_str(LobbyJoinPanel.join_url("10.0.0.5", 47801)).is_equal("http://10.0.0.5:47800/?join=1")
	assert_str(LobbyJoinPanel.join_url("10.0.0.5", 5001)).is_equal("http://10.0.0.5:5000/?join=1")


## A context of a host whose server serves HTTPS (`host_tls`, which StationContext doesn't
## have yet): the fixture's context with the flag.
class TlsContext:
	extends StationContext
	var host_tls: bool = true


# FT: FT-NET-013
# A server with TLS serves the page over HTTPS: the URL and the QR code say https, on the same
# port; a context without the flag stays http.
func test_join_url_says_https_when_the_server_uses_tls() -> void:
	assert_str(LobbyJoinPanel.join_url("10.0.0.5", 47801, true)).is_equal(
		"https://10.0.0.5:47800/?join=1"
	)
	assert_bool(LobbyJoinPanel.host_tls(StationFixture.context("helm"))).is_false()
	var plain: StationContext = StationFixture.context("helm")
	var ctx: TlsContext = TlsContext.new()
	for prop: Dictionary in plain.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			ctx.set(prop["name"], plain.get(prop["name"]))
	ctx.crew.lobby[0]["started"] = false
	ctx.host_bind = "192.168.1.20"
	ctx.host_port = 47801
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	var https: String = URL.replace("http://", "https://")
	assert_str((l.find_child("JoinUrl", true, false) as Label).text).contains(https)
	var qr: QrView = l.find_child("JoinQr", true, false)
	assert_array(qr.modules).is_equal(QrCode.encode(https))
