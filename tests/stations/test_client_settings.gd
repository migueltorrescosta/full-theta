extends GdUnitTestSuite
## ClientSettings persistence and the Settings screen.

const PATH: String = "user://test_client_settings.cfg"


func after_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


# FT: FT-STN-007, FT-STN-013, FT-STN-014, FT-STN-012, FT-STN-017
func test_settings_round_trip_through_the_file() -> void:
	var a: ClientSettings = ClientSettings.new(PATH)
	a.player_name = "Ana"
	a.set_ui_scale(1.5)
	a.invert_pitch = true
	a.bindings.rebind("cycle_target", "kbm", PackedStringArray(["U"]))
	a.bindings.set_toggle("face", true)
	a.mark_tooltip_seen("helm")
	a.comfort = true
	a.roll_lock = "reference"
	a.reference_plane = Quaternion(Vector3.RIGHT, 0.5)
	assert_int(a.save()).is_equal(OK)
	var b: ClientSettings = ClientSettings.new(PATH)
	assert_int(b.load_file()).is_equal(OK)
	assert_str(b.player_name).is_equal("Ana")
	assert_float(b.ui_scale).is_equal(1.5)
	assert_bool(b.invert_pitch).is_true()
	assert_array(Array(b.bindings.bindings("cycle_target", "kbm"))).is_equal(["U"])
	assert_array(Array(b.bindings.bindings("cycle_target", "pad"))).is_equal(["RB"])
	assert_bool(b.bindings.is_toggle("face")).is_true()
	assert_bool(b.tooltip_seen("helm")).is_true()
	assert_bool(b.tooltip_seen("weapons")).is_false()
	assert_str(b.roll_lock).is_equal("reference")
	assert_bool(b.reference_plane.is_equal_approx(Quaternion(Vector3.RIGHT, 0.5))).is_true()
	b.reset_tooltips()
	assert_bool(b.tooltip_seen("helm")).is_false()


# FT: FT-STN-013
func test_ui_scale_is_clamped_to_75_150_percent() -> void:
	var s: ClientSettings = ClientSettings.new(PATH)
	s.set_ui_scale(3.0)
	assert_float(s.ui_scale).is_equal(1.5)
	s.set_ui_scale(0.2)
	assert_float(s.ui_scale).is_equal(0.75)
	assert_int(ClientSettings.new("user://missing_settings.cfg").load_file()).is_equal(OK)


# FT: FT-STN-007, FT-STN-014
func test_settings_screen_rebinds_from_a_pressed_key() -> void:
	var s: ClientSettings = ClientSettings.new(PATH)
	var screen: SettingsScreen = auto_free(SettingsScreen.new())
	screen.setup(s, true)
	add_child(screen)
	screen.start_capture("cycle_target", "kbm")
	var k: InputEventKey = InputEventKey.new()
	k.keycode = KEY_U
	k.pressed = true
	screen._input(k)
	assert_array(Array(s.bindings.bindings("cycle_target", "kbm"))).is_equal(["U"])
	assert_array(screen.capturing).is_empty()
	var toggle: CheckBox = screen.find_child("Row_face", true, false).get_node("Toggle")
	toggle.button_pressed = true
	assert_bool(s.bindings.is_toggle("face")).is_true()
	screen.set_ui_scale(1.25)
	assert_float(s.ui_scale).is_equal(1.25)
	screen.close()
	assert_bool(FileAccess.file_exists(PATH)).is_true()


func test_binding_from_event_covers_keys_mouse_and_pad() -> void:
	var k: InputEventKey = InputEventKey.new()
	k.keycode = KEY_A
	k.alt_pressed = true
	assert_str(SettingsScreen.binding_from_event(k, "kbm")).is_equal("Alt+A")
	var m: InputEventMouseButton = InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_MIDDLE
	m.shift_pressed = true
	assert_str(SettingsScreen.binding_from_event(m, "kbm")).is_equal("Shift+MMB")
	var j: InputEventJoypadButton = InputEventJoypadButton.new()
	j.button_index = JOY_BUTTON_BACK
	assert_str(SettingsScreen.binding_from_event(j, "pad")).is_equal("View")
	assert_str(SettingsScreen.binding_from_event(j, "kbm")).is_empty()
