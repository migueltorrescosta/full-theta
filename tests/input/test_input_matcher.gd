extends MatcherSuite
## InputMatcher: chords, taps and long presses, sequences, toggles and focus routing,
## driven by synthetic InputEvents with explicit times.


# FT: FT-STN-005, FT-STN-009, FT-SPA-009
func test_plain_key_fires_on_press_with_target_and_device() -> void:
	var events: Array[Dictionary] = _m.feed(_key("T", true), 0)
	assert_array(_ids(events)).is_equal(["cycle_target"])
	assert_str(events[0]["target"]).is_equal("screen")
	assert_str(events[0]["group"]).is_equal("common")
	assert_str(events[0]["device"]).is_equal("kbm")
	assert_array(_feed(_key("T", false), 10)).is_empty()
	# D175: Z toggles the radar side strip.
	assert_array(_feed(_key("Z", true), 20)).is_equal(["radar_strip"])


# FT: FT-STN-005, FT-STN-009, FT-SPA-009
func test_longest_chord_wins_view_x_over_x() -> void:
	assert_array(_feed(_pad("View", true), 0)).is_empty()
	assert_array(_feed(_pad("X", true), 50)).is_equal(["claim"])
	assert_array(_feed(_pad("X", false), 80)).is_empty()
	assert_array(_feed(_pad("View", false), 100)).is_empty()
	assert_array(_feed(_pad("X", true), 200)).is_equal(["accept"])
	_feed(_pad("View", true), 300)
	assert_array(_feed(_pad("Left", true), 310)).is_equal(["radar_strip"])
	assert_str(_m.device).is_equal("pad")


# FT: FT-STN-005
func test_view_tap_opens_overlay_and_hold_alone_does_nothing() -> void:
	_feed(_pad("View", true), 0)
	assert_array(_feed(_pad("View", false), 150)).is_equal(["overlay"])
	_feed(_pad("View", true), 1000)
	assert_array(_ids(_m.update(1500, 0.0))).is_empty()
	assert_array(_feed(_pad("View", false), 1600)).is_empty()


# FT: FT-STN-005, FT-STN-009
func test_rb_tap_cycles_and_long_selects_pinged() -> void:
	assert_array(_feed(_pad("RB", true), 0)).is_empty()
	assert_array(_feed(_pad("RB", false), 100)).is_equal(["cycle_target"])
	_feed(_pad("RB", true), 1000)
	assert_array(_ids(_m.update(1300, 0.0))).is_empty()
	assert_array(_ids(_m.update(1400, 0.0))).is_equal(["select_pinged"])
	assert_array(_feed(_pad("RB", false), 1500)).is_empty()


# FT: FT-STN-005, FT-STN-009
func test_view_rb_switches_panel_without_rb_gestures() -> void:
	_feed(_pad("View", true), 0)
	assert_array(_feed(_pad("RB", true), 10)).is_equal(["focus_2"])
	assert_array(_ids(_m.update(900, 0.0))).is_empty()
	assert_array(_feed(_pad("RB", false), 950)).is_empty()
	assert_array(_feed(_pad("View", false), 960)).is_empty()


# FT: FT-STN-005, FT-STN-009
func test_r3_tap_pings_and_long_marks() -> void:
	_feed(_pad("R3", true), 0)
	assert_array(_feed(_pad("R3", false), 120)).is_equal(["ping"])
	_feed(_pad("R3", true), 1000)
	# A release past LONG_MS completes the long press even without update().
	assert_array(_feed(_pad("R3", false), 1450)).is_equal(["mark"])


# FT: FT-STN-005, FT-STN-009
func test_shift_middle_click_marks_and_middle_click_pings() -> void:
	assert_array(_feed(_mouse(MOUSE_BUTTON_MIDDLE, true), 0)).is_equal(["ping"])
	_feed(_mouse(MOUSE_BUTTON_MIDDLE, false), 10)
	assert_array(_feed(_mouse(MOUSE_BUTTON_MIDDLE, true, true), 20)).is_equal(["mark"])


# FT: FT-STN-005, FT-JNT-007
func test_alt_a_cycles_alert_and_suppresses_strafe() -> void:
	assert_array(_feed(_key("A", true, "alt"), 0)).is_equal(["alert_cycle"])
	assert_float(_m.axis("helm_sway")).is_equal(0.0)
	_feed(_key("A", false), 10)
	assert_array(_feed(_key("A", true), 20)).is_empty()
	assert_float(_m.axis("helm_sway")).is_equal(-1.0)


# FT: FT-STN-005
func test_question_mark_opens_overlay() -> void:
	var k: InputEventKey = _key("Slash", true, "shift")
	k.unicode = "?".unicode_at(0)
	assert_array(_feed(k, 0)).is_equal(["overlay"])


# FT: FT-STN-005, FT-STN-007
func test_sequence_b_then_2() -> void:
	_m.bindings.rebind("claim", "kbm", PackedStringArray(["B,2"]))
	_m.set_context(["weapons"], "weapons")
	assert_array(_feed(_key("B", true), 0)).is_empty()
	_feed(_key("B", false), 50)
	assert_array(_feed(_key("2", true), 300)).is_equal(["claim"])
	_feed(_key("2", false), 350)
	# B alone fires its own binding once the sequence times out.
	_feed(_key("B", true), 1000)
	assert_array(_ids(_m.update(1500, 0.0))).is_empty()
	assert_array(_ids(_m.update(1701, 0.0))).is_equal(["request"])
	_feed(_key("B", false), 1750)
	# Another key cuts the wait short.
	_feed(_key("B", true), 2000)
	assert_array(_feed(_key("3", true), 2100)).is_equal(["request", "mount_3"])


# FT: FT-STN-014
func test_hold_and_toggle_modes() -> void:
	assert_array(_feed(_key("F", true), 0)).is_equal(["face"])
	assert_bool(_m.is_held("face")).is_true()
	assert_array(_feed(_key("F", false), 100)).is_equal(["face/up"])
	assert_bool(_m.is_held("face")).is_false()
	_m.bindings.set_toggle("face", true)
	assert_array(_feed(_key("F", true), 200)).is_equal(["face"])
	assert_array(_feed(_key("F", false), 300)).is_empty()
	assert_bool(_m.is_held("face")).is_true()
	assert_array(_feed(_key("F", true), 400)).is_equal(["face/up"])
	assert_bool(_m.is_held("face")).is_false()


# FT: FT-STN-005, FT-STN-014
func test_chord_hold_ends_when_the_modifier_is_released() -> void:
	_feed(_pad("View", true), 0)
	assert_array(_feed(_motion(JOY_AXIS_RIGHT_X, 0.8), 10)).is_equal(["helm_radial"])
	# The chord owns the stick: Helm strafe doesn't read it meanwhile.
	assert_float(_m.axis("helm_sway")).is_equal(0.0)
	assert_array(_feed(_pad("View", false), 200)).is_equal(["helm_radial/up"])


# FT: FT-JNT-007, FT-STN-005
func test_focus_routes_station_intents_but_keeps_the_live_set() -> void:
	_m.set_context(["helm", "engineering"], "engineering")
	# Pad sticks and buttons belong to the focused panel.
	_feed(_motion(JOY_AXIS_LEFT_X, 1.0), 0)
	assert_float(_m.axis("helm_yaw")).is_equal(0.0)
	assert_float(_m.axis("eng_cursor_x")).is_equal(1.0)
	assert_array(_feed(_pad("B", true), 10)).is_equal(["dispatch_nearest"])
	assert_array(_feed(_motion(JOY_AXIS_TRIGGER_RIGHT, 1.0), 20)).is_equal(["pip_add"])
	assert_float(_m.axis("helm_surge")).is_equal(0.0)
	# Helm translation is live on KB/M only; face on both devices.
	_feed(_key("W", true), 30)
	assert_float(_m.axis("helm_surge")).is_equal(1.0)
	var face: Array[Dictionary] = _m.feed(_key("F", true), 40)
	assert_array(_ids(face)).is_equal(["face"])
	assert_str(face[0]["target"]).is_equal("helm")
	_feed(_key("F", false), 45)
	var pad_face: Array[Dictionary] = _m.feed(_pad("L3", true), 50)
	assert_array(_ids(pad_face)).is_equal(["face"])
	assert_str(pad_face[0]["target"]).is_equal("helm")
	# A Helm key that isn't live reaches nothing; the always-live keys still work.
	assert_array(_feed(_key("C", true), 60)).is_empty()
	assert_array(_feed(_key("Space", true), 70)).is_equal(["all_stop"])
	assert_array(_feed(_key("F1", true), 80)).is_equal(["focus_1"])


# FT: FT-STN-009
func test_identical_bindings_emit_both_in_table_order() -> void:
	_m.set_context(["weapons"], "weapons")
	var events: Array[Dictionary] = _m.feed(_mouse(MOUSE_BUTTON_LEFT, true), 0)
	assert_array(_ids(events)).is_equal(["select", "fire"])
	assert_str(events[1]["target"]).is_equal("weapons")
	assert_array(_feed(_mouse(MOUSE_BUTTON_LEFT, false), 50)).is_equal(["fire/up"])


# FT: FT-STN-007
func test_rebinding_changes_routing() -> void:
	_m.bindings.rebind("cycle_target", "kbm", PackedStringArray(["U"]))
	assert_array(_feed(_key("T", true), 0)).is_empty()
	assert_array(_feed(_key("U", true), 10)).is_equal(["cycle_target"])
	_m.bindings.rebind("dock", "pad", PackedStringArray(["View+A"]))
	_feed(_pad("View", true), 20)
	assert_array(_feed(_pad("A", true), 30)).is_equal(["dock"])
	_m.bindings.reset()
	_feed(_key("T", false), 40)
	assert_array(_feed(_key("T", true), 50)).is_equal(["cycle_target"])


# FT: FT-STN-014
func test_context_change_releases_intents_that_leave() -> void:
	_m.bindings.set_toggle("fire", true)
	_m.set_context(["helm", "weapons"], "helm")
	_feed(_key("X", true), 0)
	assert_bool(_m.is_held("approach")).is_true()
	_m.set_context(["helm", "weapons"], "weapons")
	_m.feed(_mouse(MOUSE_BUTTON_LEFT, true), 10)
	assert_bool(_m.is_held("fire")).is_true()
	# Approach left the active set when Weapons took focus.
	assert_bool(_m.is_held("approach")).is_false()
	_m.set_context(["helm"], "helm")
	assert_array(_ids(_m.update(20, 0.0))).is_equal(["fire/up"])
	assert_bool(_m.is_held("fire")).is_false()


# FT: FT-STN-014
func test_release_all() -> void:
	_feed(_key("F", true), 0)
	_feed(_key("X", true), 10)
	assert_array(_ids(_m.release_all())).is_equal(["face/up", "approach/up"])
	assert_bool(_m.is_held("face")).is_false()
	assert_array(_feed(_key("F", true), 20)).is_equal(["face"])
