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
