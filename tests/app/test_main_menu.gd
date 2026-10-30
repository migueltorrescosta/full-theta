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
	SafeArea.simulate([])


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


# FT: FT-STN-005, FT-STN-013
# #28: a browser draws in canvas px, so the UI scale is multiplied by the (capped) device
# pixel ratio: a 48 px button stays 48 CSS px at dpr 2. Native windows keep the UI scale.
func test_web_content_scale_follows_the_device_pixel_ratio() -> void:
	assert_float(MainMenu.content_scale(1.0, true, 2.0)).is_equal(2.0)
	assert_float(MainMenu.content_scale(1.5, true, 2.0)).is_equal(3.0)
	assert_float(MainMenu.content_scale(1.25, false, 2.0)).is_equal(1.25)
	assert_float(MainMenu.content_scale(1.0, true, 0.5)).is_equal(1.0)


# FT: FT-STN-005
# The game's root is a full-rect Control that lets clicks through, so the window's theme
# (LayoutMode) reaches what the game puts under it, such as the shell; a menu outside it
# (under a plain Node) still follows the window's theme.
func test_the_window_theme_reaches_the_game_and_the_menu() -> void:
	var root: Control = auto_free((load("res://app/main.tscn") as PackedScene).instantiate())
	# The scene without main.gd (which would start a menu and a LAN browser of its own),
	# straight under the window as the game runs it.
	root.set_script(null)
	get_tree().root.add_child(root)
	LayoutMode.apply(get_tree().root)
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_vector(root.size).is_equal(get_tree().root.get_visible_rect().size)
	var field: LineEdit = LineEdit.new()
	root.add_child(field)
	assert_object(field.get_theme_stylebox("normal")).is_same(
		get_tree().root.theme.get_stylebox("normal", "LineEdit")
	)
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	var m: MainMenu = MainMenu.new()
	m.token_path = TOKEN
	m.pid_path = PID
	m.settings = ClientSettings.new(SETTINGS)
	holder.add_child(m)
	assert_object(m.theme).is_same(get_tree().root.theme)
	var name_field: LineEdit = m.find_child("Name", true, false)
	assert_object(name_field.get_theme_stylebox("normal")).is_same(
		get_tree().root.theme.get_stylebox("normal", "LineEdit")
	)


func _phone_menu(size: Vector2i, insets: Array, on_web: bool) -> MainMenu:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var m: MainMenu = MainMenu.new()
	m.web = on_web
	m.token_path = TOKEN
	m.pid_path = PID
	m.settings = ClientSettings.new(SETTINGS)
	vp.add_child(m)
	for i: int in 3:
		await get_tree().process_frame
	return m


# FT: FT-STN-005, FT-NET-013
# #28: a phone on its side shows the menu and join in two columns without scrolling, every
# target at least 44 px with 8 px gaps, none under an inset or in the gesture band; upright
# it keeps one column.
func test_phone_landscape_menu_has_two_columns_inside_the_safe_area() -> void:
	for on_web: bool in [true, false]:
		var m: MainMenu = await _phone_menu(Vector2i(844, 390), [47, 0, 47, 21], on_web)
		var cols: Control = m.find_child("TwoColumns", true, false)
		assert_bool(cols.is_visible_in_tree()).is_true()
		var join: Button = m.find_child("Join", true, false)
		var name_field: LineEdit = m.find_child("Name", true, false)
		assert_float(join.get_global_rect().position.x).is_greater(
			name_field.get_global_rect().end.x
		)
		var report: Dictionary = TapAudit.check(m)
		assert_array(report["targets"]).is_not_empty()
		for k: String in ["under_min", "in_band", "outside_safe", "tight"]:
			assert_array(report[k]).override_failure_message("%s: %s" % [k, report[k]]).is_empty()
		m.get_parent().remove_child(m)
		m.free()
	var up: MainMenu = await _phone_menu(Vector2i(390, 844), [0, 47, 0, 34], true)
	(
		assert_bool((up.find_child("TwoColumns", true, false) as Control).is_visible_in_tree())
		. is_false()
	)
	var r: Dictionary = TapAudit.check(up)
	for k: String in ["under_min", "in_band", "outside_safe", "tight"]:
		assert_array(r[k]).override_failure_message("%s: %s" % [k, r[k]]).is_empty()


func _frames_until(cond: Callable) -> bool:
	for i: int in 120:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()
