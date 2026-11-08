extends MatcherSuite
## Second keyboard defaults and safer destructive pad actions (D3, D5, R25-2, R25-6, R25-7,
## R25-8, R25-18): ping, mark, the six shield faces and the repair dispatch work without a
## middle button, a numpad or the mouse; the Alt shortcuts browsers swallow have a plain
## alternate; Engineering's probe and Relay's mark delete need a held d-pad button.


func _dpad(name: String, pressed: bool) -> InputEventJoypadButton:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_DPAD_UP if name == "Up" else JOY_BUTTON_DPAD_DOWN
	b.pressed = pressed
	return b


# FT: FT-STN-005, FT-STN-009
func test_ping_mark_shields_and_repair_have_a_key_without_a_mouse_button_or_numpad() -> void:
	for id: String in ["ping", "mark"]:
		var keys: PackedStringArray = IntentTable.defaults(id, IntentTable.KBM)
		assert_int(keys.size()).is_equal(2)
		assert_bool(keys[0].contains("MMB")).is_true()
		assert_bool(keys[1].contains("MMB")).is_false()
	for face: String in HelmPanel.FACES:
		var keys: PackedStringArray = IntentTable.defaults(face, IntentTable.KBM)
		assert_int(keys.size()).is_equal(2)
		assert_bool(keys[0].begins_with("Kp ")).is_true()
		assert_bool(keys[1].begins_with("Shift+")).is_true()
	assert_array(Array(IntentTable.defaults("dispatch_nearest", IntentTable.KBM))).is_equal(["N"])


# FT: FT-STN-005, FT-STN-009
func test_the_second_keys_fire_the_intent() -> void:
	assert_array(_feed(_key("P", true, "shift"), 0)).is_equal(["ping"])
	_feed(_key("P", false), 10)
	assert_array(_feed(_key("M", true, "shift"), 20)).is_equal(["mark"])
	_feed(_key("M", false), 30)
	assert_array(_feed(_key("1", true, "shift"), 40)).is_equal(["shield_fore"])
	_feed(_key("6", true, "shift"), 50)
	assert_array(_feed(_key("6", false), 60)).is_empty()
	_m.set_context(["engineering"], "engineering")
	assert_array(_feed(_key("N", true), 100)).is_equal(["dispatch_nearest"])
	_feed(_key("N", false), 110)
	# Shift+P pings on Engineering too and does not build a probe (P).
	assert_array(_feed(_key("P", true, "shift"), 200)).is_equal(["ping"])


# FT: FT-STN-009
func test_the_shakedown_names_both_keys() -> void:
	I18n.apply("en")
	var b: Bindings = Bindings.new()
	assert_str(BindingText.fill_markers("{binding:ping}", b, IntentTable.KBM)).is_equal(
		"Middle click / Shift+P"
	)
	assert_str(BindingText.fill_markers("{binding:shield_fore}", b, IntentTable.KBM)).is_equal(
		"Kp 1 / Shift+1"
	)
	assert_str(BindingText.fill_markers("{binding:dispatch_nearest}", b, IntentTable.KBM)).is_equal(
		"N"
	)


# FT: FT-STN-009, FT-STN-005
func test_every_alt_shortcut_has_a_plain_alternate() -> void:
	var seen: int = 0
	for r: Dictionary in IntentTable.INTENTS:
		var keys: Array = r["kbm"]
		if keys.any(func(k: String) -> bool: return k.begins_with("Alt+")):
			seen += 1
			var plain: Array = keys.filter(
				func(k: String) -> bool: return not k.begins_with("Alt+")
			)
			assert_bool(plain.is_empty()).override_failure_message(r["id"]).is_false()
	# Main views 1 to 5, alert cycle, share and the Shakedown's Next.
	assert_int(seen).is_equal(8)


# FT: FT-STN-005, FT-STN-009
func test_the_plain_alternates_fire_too() -> void:
	assert_array(_feed(_key("Tab", true, "shift"), 0)).is_equal(["alert_cycle"])
	_feed(_key("Tab", false), 10)
	assert_array(_feed(_key("N", true, "shift"), 20)).is_equal(["training_next"])
	_feed(_key("N", false), 30)
	assert_array(_feed(_key("B", true, "shift"), 40)).is_equal(["share"])
	_feed(_key("B", false), 50)
	_m.set_context(["relay"], "relay")
	assert_array(_feed(_key("3", true), 60)).is_equal(["main_view_3"])


# FT: FT-STN-005, FT-STN-009
func test_destructive_dpad_actions_need_a_hold() -> void:
	for id: String in ["fabricate_probe", "mark_delete"]:
		var pad: PackedStringArray = IntentTable.defaults(id, IntentTable.PAD)
		assert_int(pad.size()).is_equal(1)
		assert_bool(pad[0].begins_with("long ")).override_failure_message(id).is_true()
	_m.set_context(["engineering"], "engineering")
	# A tap on Up does nothing; a hold past LONG_MS builds the probe.
	_feed(_dpad("Up", true), 0)
	assert_array(_feed(_dpad("Up", false), 100)).is_empty()
	_feed(_dpad("Up", true), 1000)
	assert_array(_ids(_m.update(1450, 0.0))).is_equal(["fabricate_probe"])
	_feed(_dpad("Up", false), 1500)
	_m.set_context(["relay"], "relay")
	_feed(_dpad("Down", true), 2000)
	assert_array(_feed(_dpad("Down", false), 2100)).is_empty()
	_feed(_dpad("Down", true), 3000)
	assert_array(_ids(_m.update(3450, 0.0))).is_equal(["mark_delete"])
