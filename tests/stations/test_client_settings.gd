extends GdUnitTestSuite
## ClientSettings persistence and the Settings screen.

const PATH: String = "user://test_client_settings.cfg"


func before() -> void:
	I18n.apply("en")


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


# FT: FT-STN-013, FT-STN-007
# A broken file (wrong types, a non-finite or out-of-range scale) falls back per value.
func test_bad_values_in_the_file_fall_back_to_defaults() -> void:
	for bad: Variant in [INF, NAN, 9.0, 0.1, "big"]:
		var cfg: ConfigFile = ConfigFile.new()
		cfg.set_value("ui", "scale", bad)
		cfg.set_value("player", "name", 42)
		cfg.set_value("input", "invert_pitch", "yes")
		cfg.set_value("input", "bindings", [1, 2])
		cfg.set_value("ui", "tooltips_seen", 3)
		cfg.set_value("comfort", "on", 1)
		cfg.set_value("comfort", "roll_lock", 7)
		cfg.set_value("comfort", "reference_plane", "up")
		assert_int(cfg.save(PATH)).is_equal(OK)
		var s: ClientSettings = ClientSettings.new(PATH)
		assert_int(s.load_file()).is_equal(OK)
		assert_float(s.ui_scale).is_equal(1.0)
		assert_str(s.player_name).is_equal("")
		assert_bool(s.invert_pitch or s.comfort).is_false()
		assert_dict(s.tooltips_seen).is_empty()
		assert_str(s.roll_lock).is_equal("deck")
		assert_bool(s.reference_plane == Quaternion.IDENTITY).is_true()


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


func _capture_screen() -> SettingsScreen:
	var screen: SettingsScreen = auto_free(SettingsScreen.new())
	screen.setup(ClientSettings.new(PATH), true)
	add_child(screen)
	return screen


func _k(code: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var k: InputEventKey = InputEventKey.new()
	k.physical_keycode = code
	k.pressed = pressed
	k.shift_pressed = shift
	return k


func _b(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var j: InputEventJoypadButton = InputEventJoypadButton.new()
	j.button_index = button
	j.pressed = pressed
	return j


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var m: InputEventJoypadMotion = InputEventJoypadMotion.new()
	m.axis = axis
	m.axis_value = value
	return m


## Captures `events` as the binding of `id` on `device`; returns its bindings after.
func _capture(screen: SettingsScreen, id: String, device: String, events: Array) -> Array:
	screen.start_capture(id, device)
	for e: InputEvent in events:
		screen._input(e)
	return Array(screen.settings.bindings.bindings(id, device))


# FT: FT-STN-007
# Physical keys (layout-independent), lone modifiers on release, Shift chords, pad
# chords, triggers and sticks past half way.
func test_capture_variants() -> void:
	var s: SettingsScreen = _capture_screen()
	var ky: InputEventKey = _k(KEY_U, true)
	ky.keycode = KEY_SEMICOLON
	assert_array(_capture(s, "approach", "kbm", [ky])).is_equal(["U"])
	assert_array(_capture(s, "approach", "kbm", [_k(KEY_ALT, true), _k(KEY_ALT, false)])).is_equal(
		["Alt"]
	)
	assert_array(_capture(s, "approach", "kbm", [_k(KEY_SHIFT, true, true), _k(KEY_J, true, true)]))
	assert_array(s.settings.bindings.bindings("approach", "kbm")).is_equal(["Shift+J"])
	var lb: JoyButton = JOY_BUTTON_LEFT_SHOULDER
	var chord: Array = [_b(lb, true), _b(JOY_BUTTON_A, true)]
	assert_array(_capture(s, "approach", "pad", chord)).is_equal(["LB+A"])
	s._input(_b(JOY_BUTTON_A, false))
	s._input(_b(lb, false))
	assert_array(_capture(s, "approach", "pad", [_b(lb, true), _b(lb, false)])).is_equal(["LB"])
	var rt: Array = [_axis(JOY_AXIS_TRIGGER_RIGHT, 0.05), _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)]
	rt.append(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0))
	assert_array(_capture(s, "approach", "pad", rt)).is_equal(["RT"])
	var lb_rt: Array = [_b(lb, true), _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)]
	assert_array(_capture(s, "approach", "pad", lb_rt)).is_equal(["LB+RT"])
	var stick: Array = [_axis(JOY_AXIS_RIGHT_X, 0.2), _axis(JOY_AXIS_RIGHT_X, 0.8)]
	assert_array(_capture(s, "approach", "pad", stick)).is_equal(["RS"])
	var yaw: Array = [_axis(JOY_AXIS_LEFT_X, -0.9)]
	assert_array(_capture(s, "helm_yaw", "pad", yaw)).is_equal(["-LS_X"])
	assert_array(s.capturing).is_empty()


# FT: FT-STN-007, FT-STN-009
# A binding that a common or always-live intent uses is refused with a warning, both
# ways; two station intents may share one; LMB stays select and fire (D176).
func test_capture_refuses_collisions_with_common_and_live_keys() -> void:
	var s: SettingsScreen = _capture_screen()
	assert_array(_capture(s, "cycle_target", "kbm", [_k(KEY_F, true)])).is_equal(["T"])
	assert_str(s.warning.text).contains(tr("intent.face"))
	assert_array(s.capturing).is_equal(["cycle_target", "kbm"])
	assert_array(_capture(s, "approach", "kbm", [_k(KEY_T, true)])).is_equal(["X"])
	assert_array(_capture(s, "approach", "kbm", [_k(KEY_H, true)])).is_equal(["H"])
	assert_str(s.warning.text).is_empty()
	var lmb: InputEventMouseButton = InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	assert_array(_capture(s, "fire", "kbm", [lmb])).is_equal(["LMB"])
	assert_array(s.capturing).is_empty()


# FT: FT-STN-007
# Menu and Decline can't be unbound and can always get their default key back; Esc
# cancels and Backspace unbinds anything else; Esc closes Settings.
func test_menu_and_decline_stay_bound() -> void:
	var s: SettingsScreen = _capture_screen()
	assert_array(_capture(s, "menu", "kbm", [_k(KEY_I, true)])).is_equal(["I"])
	assert_array(_capture(s, "menu", "kbm", [_k(KEY_BACKSPACE, true)])).is_equal(["I"])
	assert_str(s.warning.text).is_equal(tr("settings.must_bind"))
	assert_array(_capture(s, "menu", "kbm", [_k(KEY_ESCAPE, true)])).is_equal(["Escape"])
	assert_array(_capture(s, "decline", "pad", [_k(KEY_BACKSPACE, true)])).is_equal(["Y"])
	assert_array(_capture(s, "decline", "kbm", [_k(KEY_BACKSPACE, true)])).is_equal(["Backspace"])
	assert_array(_capture(s, "ping", "kbm", [_k(KEY_ESCAPE, true)])).is_equal(["MMB"])
	assert_array(s.capturing).is_empty()
	assert_array(_capture(s, "ping", "kbm", [_k(KEY_BACKSPACE, true)])).is_empty()
	var closed: Array = []
	s.closed.connect(func() -> void: closed.append(true))
	s._input(_k(KEY_ESCAPE, true))
	assert_bool(s.visible).is_false()
	assert_array(closed).is_equal([true])


# FT: FT-STN-005
# The settings' Full screen button shows its whole label (a rail button trims to "Full", #28).
func test_fullscreen_button_keeps_its_label() -> void:
	FullscreenButton.forced = 1
	var screen: SettingsScreen = _capture_screen()
	await get_tree().process_frame
	var b: FullscreenButton = screen.find_child("Fullscreen", true, false)
	var font: Font = b.get_theme_font("font")
	var w: float = (
		font
		. get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size"))
		. x
	)
	assert_float(b.get_combined_minimum_size().x).is_greater(w)
	FullscreenButton.forced = -1
