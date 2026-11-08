extends GdUnitTestSuite
## Gamepad navigation of the menu, the lobby and the Training picker (D4, R25-5): the first
## pad press gives the first control focus, and the d-pad then moves it.


func _button(pressed: bool = true) -> InputEventJoypadButton:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_DPAD_DOWN
	b.pressed = pressed
	return b


func _screen() -> Control:
	var screen: VBoxContainer = auto_free(VBoxContainer.new())
	for n: String in ["Hidden", "Off", "First", "Second"]:
		var b: Button = Button.new()
		b.name = n
		screen.add_child(b)
	(screen.get_node("Hidden") as Button).visible = false
	(screen.get_node("Off") as Button).disabled = true
	add_child(screen)
	return screen


# FT: FT-STN-005
func test_the_first_visible_enabled_control_is_found() -> void:
	var screen: Control = _screen()
	assert_str(PadFocus.first_focusable(screen).name).is_equal("First")
	(screen.get_node("First") as Button).focus_mode = Control.FOCUS_NONE
	assert_str(PadFocus.first_focusable(screen).name).is_equal("Second")


# FT: FT-STN-005
func test_a_pad_press_grabs_focus_once_and_a_key_does_not() -> void:
	var screen: Control = _screen()
	var focus: PadFocus = PadFocus.attach(screen)
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	assert_bool(PadFocus.is_pad_input(key)).is_false()
	assert_bool(PadFocus.is_pad_input(_button(false))).is_false()
	focus._input(key)
	assert_object(get_viewport().gui_get_focus_owner()).is_null()
	assert_bool(PadFocus.is_pad_input(_button())).is_true()
	assert_bool(focus.grab()).is_true()
	assert_str(get_viewport().gui_get_focus_owner().name).is_equal("First")
	# Focus is there now: a second press leaves it alone for the engine's navigation.
	assert_bool(focus.grab()).is_false()
	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.axis_value = 0.2
	assert_bool(PadFocus.is_pad_input(stick)).is_false()
	stick.axis_value = -0.9
	assert_bool(PadFocus.is_pad_input(stick)).is_true()


# FT: FT-STN-005
func test_a_hidden_screen_grabs_nothing() -> void:
	var screen: Control = _screen()
	var focus: PadFocus = PadFocus.attach(screen)
	screen.visible = false
	assert_bool(focus.grab()).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_null()


## The PadFocus children of `node`'s tree whose screen is `root`'s descendants or `root`.
func _focus_of(node: Node) -> Array[PadFocus]:
	var out: Array[PadFocus] = []
	for n: Node in node.find_children("PadFocus", "PadFocus", true, false):
		out.append(n as PadFocus)
	return out


# FT: FT-STN-005, FT-MIS-039
func test_the_menu_its_settings_and_its_picker_have_pad_focus() -> void:
	var m: MainMenu = auto_free(MainMenu.new())
	m.token_path = "user://test_pad_focus.token"
	m.pid_path = "user://test_pad_focus.pid"
	m.settings = ClientSettings.new("user://test_pad_focus.cfg")
	add_child(m)
	var roots: Array = _focus_of(m).map(func(f: PadFocus) -> Control: return f.root)
	assert_int(roots.size()).is_equal(3)
	assert_bool(roots.any(func(r: Control) -> bool: return r is TrainingPicker)).is_true()
	assert_bool(roots.any(func(r: Control) -> bool: return r is SettingsScreen)).is_true()


# FT: FT-STN-005
func test_the_lobby_has_pad_focus() -> void:
	var lobby: LobbyScreen = auto_free(LobbyScreen.new())
	lobby.setup(StationFixture.context("helm", "user://test_pad_focus.cfg"))
	add_child(lobby)
	var found: Array[PadFocus] = _focus_of(lobby)
	assert_int(found.size()).is_equal(1)
	assert_object(found[0].root).is_same(lobby)
