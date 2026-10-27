extends HelmSuite
## Helm actions on KB/M and controller (T051): chase camera, face, Align, all-stop,
## approach, decoupled, shield faces and track, the radial, and when helm_input and
## helm_select_target are sent.


# FT: FT-HLM-002
func test_chase_camera_toggles_with_c_and_the_controller_radial_and_keeps_the_hud() -> void:
	_tap_key("C")
	_frame()
	assert_bool(_panel.chase).is_true()
	assert_bool(_panel.view3d.own_ship.visible).is_true()
	assert_bool(_panel.view3d.camera.position.length() > 10.0).is_true()
	assert_bool(_panel.hud.compact).is_false()
	assert_bool(_panel.ring.visible).is_true()
	_radial("chase_camera")
	_frame()
	assert_bool(_panel.chase).is_false()
	assert_vector(_panel.view3d.camera.position).is_equal(Vector3.ZERO)


# FT: FT-HLM-005, FT-HLM-006
func test_holding_face_latches_face_into_helm_input_on_both_devices() -> void:
	_key("F")
	_frame()
	assert_bool(_cmds("helm_input").back()["face"]).is_true()
	_key("F", false)
	_frame()
	assert_bool(_cmds("helm_input").back()["face"]).is_false()
	_pad("L3")
	_frame()
	assert_bool(_cmds("helm_input").back()["face"]).is_true()
	_pad("L3", false)
	_frame()
	assert_bool(_cmds("helm_input").back()["face"]).is_false()


# FT: FT-HLM-007
func test_align_needs_a_selection_then_sends_the_target_and_align() -> void:
	var toasts: Array = []
	_ctx().crew.toast.connect(func(key: String, _a: Dictionary) -> void: toasts.append(key))
	_tap_key("L")
	assert_array(_cmds("helm_align")).is_empty()
	assert_array(toasts).contains(["toast.select_first"])
	_ctx().crew.select("contact", StationFixture.H2)
	_tap_key("L")
	assert_int(_cmds("helm_select_target").back()["target_ship"]).is_equal(StationFixture.H2)
	assert_int(_cmds("helm_align").size()).is_equal(1)
	# A second press also faces it (the sim's stage); controller through the radial.
	_radial("align")
	assert_int(_cmds("helm_align").size()).is_equal(2)


# FT: FT-HLM-014
func test_all_stop_from_space_and_view_b() -> void:
	_tap_key("Space")
	_tap_pad("B", "View")
	assert_int(_cmds("helm_all_stop").size()).is_equal(2)
	# View+B is all-stop, not approach.
	_frame()
	for c: Dictionary in _cmds("helm_input"):
		assert_bool(c["approach"]).is_false()


# FT: FT-HLM-015
func test_hold_to_approach_on_x_and_pad_b() -> void:
	_ctx().crew.select("mark", StationFixture.BRAVO_SLOT)
	_key("X")
	_frame()
	assert_bool(_cmds("helm_input").back()["approach"]).is_true()
	assert_bool(_cmds("helm_select_target").back()["point"]).is_true()
	_key("X", false)
	_frame()
	assert_bool(_cmds("helm_input").back()["approach"]).is_false()
	_pad("B")
	_frame()
	assert_bool(_cmds("helm_input").back()["approach"]).is_true()
	_pad("B", false)
	_frame()
	assert_bool(_cmds("helm_input").back()["approach"]).is_false()


# FT: FT-HLM-017
func test_decoupled_from_tab_and_the_radial_sends_the_new_state() -> void:
	_tap_key("Tab")
	assert_bool(_cmds("helm_decoupled").back()["decoupled"]).is_true()
	_ctx().view.blocks[StationViews.Section.HELM]["decoupled"] = true
	_radial("decoupled")
	assert_bool(_cmds("helm_decoupled").back()["decoupled"]).is_false()


# FT: FT-HLM-008
func test_six_face_snap_on_numpad_and_d_pad() -> void:
	for k: String in ["Kp 1", "Kp 2", "Kp 3", "Kp 4", "Kp 5", "Kp 6"]:
		_tap_key(k)
	_tap_pad("Up")
	_tap_pad("Down")
	_tap_pad("Left")
	_tap_pad("Right")
	_tap_pad("Up", "LB")
	_tap_pad("Down", "LB")
	var dirs: Array = _cmds("set_shield_focus").map(
		func(c: Dictionary) -> Vector3: return c["direction"]
	)
	var six: Array = [
		Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN
	]
	assert_array(dirs).is_equal(six + six)


# FT: FT-HLM-010
func test_shield_track_follows_the_selected_contact_and_toggles_off() -> void:
	var h: Dictionary = _ctx().view.blocks[StationViews.Section.HELM]
	# Tracking H2 already: G stops tracking and keeps the direction.
	_tap_key("G")
	var off: Dictionary = _cmds("set_shield_focus").back()
	assert_int(off["track_id"]).is_equal(-1)
	assert_vector(off["direction"]).is_equal_approx(h["shield_focus"], Vector3.ONE * 1e-5)
	h["shield_track"] = -1
	_ctx().crew.select("contact", StationFixture.H2)
	_radial("shield_track")
	assert_int(_cmds("set_shield_focus").back()["track_id"]).is_equal(StationFixture.H2)
	# Only contacts can be tracked.
	_ctx().crew.select("mark", StationFixture.BRAVO_SLOT)
	_tap_key("G")
	assert_int(_cmds("set_shield_focus").size()).is_equal(2)


# FT: FT-HLM-017
func test_helm_input_is_sent_only_when_the_input_changes() -> void:
	assert_array(_cmds("helm_input")).is_empty()
	_stick(JOY_AXIS_LEFT_X, 1.0)
	_frame()
	assert_int(_cmds("helm_input").size()).is_equal(1)
	# Yaw right is nose to starboard: negative yaw.
	assert_float((_cmds("helm_input").back()["rotation"] as Vector3).y).is_equal(-1.0)
	_frame()
	_frame()
	assert_int(_cmds("helm_input").size()).is_equal(1)
	_stick(JOY_AXIS_LEFT_X, 0.0)
	_frame()
	assert_int(_cmds("helm_input").size()).is_equal(2)
	assert_vector(_cmds("helm_input").back()["rotation"]).is_equal(Vector3.ZERO)
	# KB/M translation: W is forward. Moving sticks send at most every INPUT_MS.
	_key("W")
	_frame()
	assert_int(_cmds("helm_input").size()).is_equal(2)
	StationFixture.clock(_ctx()).ms += HelmPanel.INPUT_MS
	_frame()
	assert_float(_cmds("helm_input").back()["throttle"]).is_equal(1.0)


func test_selection_changes_send_helm_select_target_once() -> void:
	var ctx: StationContext = _ctx()
	ctx.crew.select("contact", StationFixture.U3)
	_frame()
	_frame()
	assert_int(_cmds("helm_select_target").size()).is_equal(1)
	ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
	_frame()
	var t: Dictionary = _cmds("helm_select_target").back()
	var pos: Vector3 = ctx.crew.mark_in_slot(StationFixture.BRAVO_SLOT)["pos"]
	assert_int(t["target_ship"]).is_equal(-1)
	assert_vector(Vector3(t["x"], t["y"], t["z"])).is_equal(pos)
	ctx.crew.select("", -1)
	_frame()
	assert_bool(_cmds("helm_select_target").back()["point"]).is_false()
	assert_int(_cmds("helm_select_target").size()).is_equal(3)


# FT: FT-HLM-013, FT-HLM-017
func test_dock_and_jump_are_reserved_and_every_helm_action_has_a_controller_binding() -> void:
	_tap_key("H")
	_tap_key("J")
	_radial("dock")
	assert_array(StationFixture.sent(_ctx()).of("command")).is_empty()
	for id: String in IntentTable.ids_of("helm"):
		var r: Dictionary = IntentTable.row(id)
		if r["kind"] == IntentTable.AXIS or id == "helm_pointer":
			continue
		var bound: bool = not (r["pad"] as Array).is_empty() or id in HelmPanel.RADIAL
		assert_bool(bound).override_failure_message(id + " has no controller binding").is_true()
	for id: String in ["chase_camera", "align", "decoupled", "shield_track", "ping"]:
		assert_array(HelmPanel.RADIAL).contains([id])


func test_radial_ping_pings_the_selection() -> void:
	_ctx().crew.select("contact", StationFixture.H2)
	_radial("ping")
	var pings: Array = StationFixture.sent(_ctx()).of("ping")
	assert_int(pings.size()).is_equal(1)
	assert_int(pings[0][1][1]).is_equal(StationFixture.H2)
