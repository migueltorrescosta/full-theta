extends GdUnitTestSuite
## MainMenu without a server: bind choices, typed addresses, the stored-token rejoin and
## the orphan check on start.

const TOKEN: String = "user://test_menu_token.json"
const PID: String = "user://test_menu_pid.json"
const SETTINGS: String = "user://test_menu_settings.cfg"


func after_test() -> void:
	for p: String in [TOKEN, PID, SETTINGS]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	get_tree().root.content_scale_factor = 1.0


func _menu() -> MainMenu:
	var m: MainMenu = auto_free(MainMenu.new())
	m.token_path = TOKEN
	m.pid_path = PID
	m.settings = ClientSettings.new(SETTINGS)
	add_child(m)
	return m


# FT: FT-NET-001
# D108: "This computer only" first, then LAN addresses; never every interface.
func test_bind_choices_start_with_loopback() -> void:
	var binds: PackedStringArray = MainMenu.bind_addresses()
	assert_str(binds[0]).is_equal("127.0.0.1")
	assert_bool(binds.has("0.0.0.0")).is_false()


# FT: FT-NET-013
func test_a_bad_typed_address_says_why_and_a_good_one_connects() -> void:
	var m: MainMenu = _menu()
	m.join("ftp://x")
	assert_object(m.joining).is_null()
	assert_str((m.find_child("Status", true, false) as Label).text).is_not_empty()
	m.join("127.0.0.1:1")
	assert_object(m.joining).is_not_null()
	assert_str(m.joining.url).is_equal("ws://127.0.0.1:1")
	assert_str(m.settings.last_address).is_equal("127.0.0.1:1")


# FT: FT-NET-003, FT-M1-013
func test_rejoin_uses_the_stored_token() -> void:
	SessionTokenFile.make("tok123", "127.0.0.1", 2).save(TOKEN)
	var m: MainMenu = _menu()
	await get_tree().process_frame
	assert_bool((m.find_child("Rejoin", true, false) as Button).visible).is_true()
	m.rejoin()
	assert_str(m.joining.token).is_equal("tok123")
	assert_str(m.joining.url).is_equal("ws://127.0.0.1:2")


func test_no_rejoin_without_a_token_and_the_name_persists() -> void:
	var m: MainMenu = _menu()
	await get_tree().process_frame
	assert_bool((m.find_child("Rejoin", true, false) as Button).visible).is_false()
	(m.find_child("Name", true, false) as LineEdit).text = "  Ana "
	m.join("127.0.0.1:1")
	var again: ClientSettings = ClientSettings.new(SETTINGS)
	again.load_file()
	assert_str(again.player_name).is_equal("Ana")


# FT: FT-NET-012
# The LAN list redraws when a beacon changes it, and nothing is polled while the shell
# is up.
func test_lan_list_updates_on_change_and_pauses_under_the_shell() -> void:
	var m: MainMenu = _menu()
	assert_int(m.browser.start(0, "127.0.0.1")).is_equal(OK)
	var hosts: ItemList = m.find_child("Hosts", true, false)
	var udp: PacketPeerUDP = PacketPeerUDP.new()
	udp.set_dest_address("127.0.0.1", m.browser.local_port())
	var beacon: Callable = func(ws_port: int) -> void:
		udp.put_packet(LanBeacon.new(NetProtocol.PROTOCOL_VERSION, "A", ws_port).encode())
	beacon.call(47801)
	assert_bool(await _frames_until(func() -> bool: return hosts.item_count == 1)).is_true()
	m.shell = auto_free(ClientShell.new())
	beacon.call(47802)
	for i: int in 10:
		await get_tree().process_frame
	assert_int(hosts.item_count).is_equal(1)
	m.shell = null
	assert_bool(await _frames_until(func() -> bool: return hosts.item_count == 2)).is_true()
	udp.close()


# FT: FT-NET-003
# Leaving from the lobby ends the host's server and brings the menu back.
func test_leaving_stops_the_host_session_and_shows_the_menu() -> void:
	var m: MainMenu = _menu()
	var hosted: HostSession = HostSession.new()
	hosted.token_file = TOKEN
	hosted.state = HostSession.State.JOINED
	m.host_session = hosted
	m.shell = ClientShell.new()
	m.add_child(m.shell)
	m.shell.left.connect(m._on_left)
	m.shell.left.emit()
	assert_int(hosted.state).is_equal(HostSession.State.STOPPED)
	assert_object(m.host_session).is_null()
	assert_object(m.shell).is_null()
	assert_bool((m.find_child("Host", true, false) as Button).is_visible_in_tree()).is_true()


func _frames_until(cond: Callable) -> bool:
	for i: int in 120:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
