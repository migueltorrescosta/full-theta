extends HelmSuite
## Helm panel (T051): cockpit, HUD, compass, off-screen arrows, shield ring, envelope,
## pointer and comfort.


# FT: FT-HLM-001, FT-STN-002, FT-M1-004
func test_helm_defaults_to_the_cockpit_with_hud_compass_radar_and_ring() -> void:
	assert_object(_panel).is_not_null()
	assert_bool(_panel.focused).is_true()
	assert_bool(_panel.chase).is_false()
	assert_bool(_panel.view3d.camera.current).is_true()
	assert_vector(_panel.view3d.camera.position).is_equal(Vector3.ZERO)
	assert_bool(_panel.view3d.own_ship.visible).is_false()
	assert_bool(_panel.hud.compact).is_false()
	assert_bool(_panel.ring.visible).is_true()
	assert_object(_screen.radar).is_not_null()
	# The other ships are drawn (the approved procedural ship, D107).
	assert_array(_panel.view3d.ships.keys()).contains([StationFixture.H2, StationFixture.U3])


# FT: FT-HLM-001, FT-JNT-001
func test_docked_helm_shows_the_compact_view() -> void:
	_panel.set_mode(false, true)
	assert_bool(_panel.hud.compact).is_true()
	assert_bool(_panel.ring.label).is_false()
	assert_array(_panel.hud.markers()).is_empty()
	assert_bool(_panel.steering()).is_false()


# FT: FT-HLM-003
func test_compass_dot_is_filled_ahead_and_hollow_behind() -> void:
	var ctx: StationContext = _ctx()
	ctx.crew.select("contact", StationFixture.U3)
	var ahead: Vector3 = ctx.selection_local()
	assert_bool(HelmHud.compass_filled(ahead)).is_true()
	ctx.crew.select("contact", StationFixture.H2)
	var behind: Vector3 = ctx.selection_local()
	assert_bool(HelmHud.compass_filled(behind)).is_false()
	# 4 o'clock high: right and up on the compass.
	var p: Vector2 = HelmHud.compass_point(behind, 40.0)
	assert_bool(p.x > 0.0 and p.y < 0.0).is_true()
	# Marks are selectable targets too.
	ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
	assert_bool(HelmHud.compass_filled(ctx.selection_local())).is_false()
	assert_str(_panel.hud.selection_label()).is_equal("Bravo")


# FT: FT-HLM-004
func test_off_screen_arrows_for_the_selection_and_pinged_items() -> void:
	var ctx: StationContext = _ctx()
	ctx.crew.select("contact", StationFixture.H2)
	var p: Dictionary = {"ship": 0, "kind": "contact", "id": StationFixture.F4, "by": "Bo"}
	ctx.crew.handle_event({"type": "ping", "payload": p}, StationFixture.NOW_MS - 500)
	_frame()
	var arrows: Array = []
	var on_screen: Array = []
	for e: Dictionary in _panel.hud.markers():
		if e["arrow"]:
			arrows.append(e["id"])
		if e["on_screen"]:
			on_screen.append(e["id"])
	assert_array(arrows).contains_exactly_in_any_order([StationFixture.H2, StationFixture.F4])
	assert_array(on_screen).contains([StationFixture.U3])


# FT: FT-HLM-009
func test_a_click_on_a_ring_sector_sets_focus_to_that_clock_and_height() -> void:
	var ring: ShieldRing = _panel.ring
	var c: Vector2 = ring.centre()
	var r: float = ring.radius()
	# 4 o'clock, outer band = high.
	var a: float = deg_to_rad(120.0)
	var at: Vector2 = c + Vector2(sin(a), -cos(a)) * r * 0.87
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	ring._gui_input(click)
	var dir: Vector3 = _cmds("set_shield_focus").back()["direction"]
	assert_int(Callout.clock(dir)).is_equal(4)
	assert_str(Callout.height_word(dir)).is_equal("high")
	assert_vector(ring.direction_at(c + Vector2(0, -r * 0.1))).is_equal(Vector3.UP)
	assert_vector(ring.direction_at(c + Vector2(0, r * 0.1))).is_equal(Vector3.DOWN)
	assert_str(Callout.height_word(ring.direction_at(c + Vector2(0, -r * 0.6)))).is_equal("level")
	assert_str(Callout.height_word(ring.direction_at(c + Vector2(0, -r * 0.3)))).is_equal("low")
	assert_vector(ring.direction_at(c + Vector2(r * 1.2, 0))).is_equal(Vector3.ZERO)


# FT: FT-HLM-011
func test_ring_shows_helm_focus_with_engineering_tightness_and_power() -> void:
	var ring: ShieldRing = _panel.ring
	var h: Dictionary = _ctx().view.blocks[StationViews.Section.HELM]
	assert_vector(ring.focus).is_equal(h["shield_focus"])
	assert_float(ring.tightness).is_equal(2.0)
	assert_float(ring.power).is_equal(1.0)
	assert_bool(ring.tracking).is_true()
	var side: Vector3 = (h["shield_focus"] as Vector3).cross(Vector3.UP).normalized()
	var spread: float = ring.coverage(side)
	h["shield_tightness"] = 6.0
	h["shield_power"] = 0.5
	_frame()
	assert_float(ring.coverage(h["shield_focus"])).is_equal_approx(1.0, 1e-5)
	assert_bool(ring.coverage(side) < spread).is_true()
	assert_float(ring.power).is_equal(0.5)


# FT: FT-HLM-012
func test_thrust_envelope_and_propellant_come_from_the_snapshot() -> void:
	var fields: Array = StationViews.def("helm").fields[StationViews.Section.HELM]
	assert_array(fields).contains(["thrust_scale", "torque_scale", "shield_power"])
	assert_float(float(_panel.helm_block()["torque_scale"])).is_equal(0.8)
	# 8000 kg of the corvette's 10 t.
	assert_float(_panel.propellant_share()).is_equal_approx(0.8, 1e-6)


# FT: FT-STN-003, FT-STN-009
func test_select_takes_the_item_under_the_reticle_while_steering() -> void:
	_frame()
	var u3: Dictionary = {}
	for e: Dictionary in _panel.hud.markers():
		if e["id"] == StationFixture.U3:
			u3 = e
	assert_bool(_panel.steering()).is_true()
	assert_dict(_panel.item_at(u3["pos"])).is_empty()
	# Ctrl shows the pointer: then the item under it.
	_key("Ctrl")
	assert_bool(_panel.steering()).is_false()
	assert_dict(_panel.item_at(u3["pos"])).is_equal({"kind": "contact", "id": StationFixture.U3})
	_key("Ctrl", false)
	assert_str(_panel.claim_item()).is_equal("flight")


func test_mouse_motion_steers_only_while_the_pointer_is_captured() -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(40, 0)
	_key("Ctrl")
	_screen.feed(motion)
	assert_vector(_ctx().matcher.mouse_stick.value).is_equal(Vector2.ZERO)
	_key("Ctrl", false)
	_screen.feed(motion)
	assert_bool(_ctx().matcher.mouse_stick.value.x > 0.0).is_true()


# FT: FT-HLM-001, FT-M1-012
# The outcome card (the run is over, D178) frees the pointer, like a pause (D183).
func test_the_end_of_the_run_frees_the_pointer() -> void:
	_frame()
	assert_bool(_panel.steering()).is_true()
	_ctx().crew.run_over[StationFixture.SHIP] = {"ship": StationFixture.SHIP, "outcome": "win"}
	_frame()
	assert_bool(_panel.steering()).is_false()


# FT: FT-HLM-001
# The menu on any tab (the help is its Controls tab), the alert picker and a pause free the
# pointer, a click on Close works, and only a new left click in the view captures it (D183).
func test_every_overlay_frees_the_pointer_until_a_new_click_in_the_view() -> void:
	_frame()
	assert_int(_panel.mouse_mode_wanted()).is_equal(Input.MOUSE_MODE_CAPTURED)
	var menu: SettingsScreen = auto_free(SettingsScreen.new())
	menu.setup(_ctx().settings, true)
	menu.visible = false
	add_child(menu)
	_screen.blockers = [menu]
	for tab: String in [
		SettingsScreen.TAB_CONTROLS, SettingsScreen.TAB_SETTINGS, SettingsScreen.TAB_KEYS
	]:
		_panel._captured = true
		menu.open(tab)
		_frame()
		assert_int(_panel.mouse_mode_wanted()).is_equal(Input.MOUSE_MODE_VISIBLE)
		# A click that reaches the view while the menu is up doesn't capture it.
		_click_view()
		assert_int(_panel.mouse_mode_wanted()).is_equal(Input.MOUSE_MODE_VISIBLE)
		var close: Button = menu.find_child("Close", true, false) as Button
		close.pressed.emit()
		assert_bool(menu.visible).is_false()
		_frame()
		assert_int(_panel.mouse_mode_wanted()).is_equal(Input.MOUSE_MODE_VISIBLE)
	_click_view()
	assert_int(_panel.mouse_mode_wanted()).is_equal(Input.MOUSE_MODE_CAPTURED)
	_screen.top_bar.picker.visible = true
	_frame()
	assert_int(_panel.mouse_mode_wanted()).is_equal(Input.MOUSE_MODE_VISIBLE)
	_screen.top_bar.picker.visible = false
	_click_view()
	_ctx().crew.host_paused = true
	_frame()
	assert_int(_panel.mouse_mode_wanted()).is_equal(Input.MOUSE_MODE_VISIBLE)


func _click_view() -> void:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_panel._on_gui_input(click)


## Sets the own velocity from ship-frame metres per second (x starboard, y up, -z ahead).
func _drift(local: Vector3) -> void:
	_ctx().view.kin["vel"] = NetCodec.quant_vel(_ctx().interp.own_rotation() * local)
	_frame()


func _marker(kind: String) -> Dictionary:
	for m: Dictionary in _panel.hud.velocity_markers():
		if m["kind"] == kind:
			return m
	return {}


# FT: FT-HLM-001
# Heave up is invisible against the stars, so the drift shows as a marker: on the nose when
# going ahead, clamped to the edge toward the drift when it points out of the view.
func test_velocity_markers_sit_off_the_nose_by_the_drift_direction() -> void:
	var centre: Vector2 = _panel.hud.size / 2.0
	_drift(Vector3(0.0, 0.0, -80.0))
	assert_bool(_marker("pro")["edge"]).is_false()
	assert_float((_marker("pro")["pos"] as Vector2).distance_to(centre)).is_less(2.0)
	assert_dict(_marker("retro")).is_empty()
	# 12 m/s straight up (full heave): off the top edge, above the nose.
	_drift(Vector3(0.0, 12.0, 0.0))
	var up: Dictionary = _marker("pro")
	assert_bool(up["edge"]).is_true()
	assert_float((up["pos"] as Vector2).y).is_less(centre.y)
	assert_float(absf((up["pos"] as Vector2).x - centre.x)).is_less(2.0)
	# Strafing to starboard: toward the right.
	_drift(Vector3(6.0, 0.0, 0.0))
	assert_float((_marker("pro")["pos"] as Vector2).x).is_greater(centre.x)
	# Backwards: the retrograde marker is on the nose, the prograde one behind (bottom edge).
	_drift(Vector3(0.0, 0.0, 10.0))
	assert_float((_marker("retro")["pos"] as Vector2).distance_to(centre)).is_less(2.0)
	assert_bool(_marker("pro")["edge"]).is_true()
	assert_float((_marker("pro")["pos"] as Vector2).y).is_greater(centre.y)
	# Nearly still: none.
	_drift(Vector3(0.0, 0.1, 0.0))
	assert_array(_panel.hud.velocity_markers()).is_empty()


# FT: FT-HLM-001
func test_speed_read_outs_are_per_axis_in_the_ship_frame() -> void:
	_drift(Vector3(2.5, -12.0, -8.0))
	var l: Vector3 = _panel.hud.local_velocity()
	assert_float(-l.z).is_equal_approx(8.0, 0.1)
	assert_float(l.x).is_equal_approx(2.5, 0.1)
	assert_float(l.y).is_equal_approx(-12.0, 0.1)
	assert_str(HelmHud.speed_text(8.04)).is_equal("+8.0 m/s")
	assert_str(HelmHud.speed_text(-3.46)).is_equal("-3.5 m/s")
	assert_str(HelmHud.speed_text(-12.4)).is_equal("-12 m/s")


# FT: FT-HLM-001
func test_thrust_arrows_follow_the_translation_input() -> void:
	assert_vector(_panel.hud.thrust_input()).is_equal(Vector3.ZERO)
	_key("D")
	_key("R")
	_key("W")
	assert_float(_panel.hud.thrust_input().x).is_greater(0.0)
	assert_float(_panel.hud.thrust_input().y).is_greater(0.0)
	assert_float(_panel.hud.thrust_input().z).is_greater(0.0)
	_key("D", false)
	_key("R", false)
	_key("W", false)
	_key("A")
	_key("V")
	_key("S")
	var t: Vector3 = _panel.hud.thrust_input()
	assert_bool(t.x < 0.0 and t.y < 0.0 and t.z < 0.0).is_true()
	assert_bool(_panel.hud.reserved().has(_panel.hud.thrust_rect())).is_true()


# FT: FT-STN-017
func test_comfort_locks_the_cockpit_roll_and_narrows_the_view() -> void:
	var s: ClientSettings = _ctx().settings
	var cam: Camera3D = _panel.view3d.camera
	var own: Quaternion = _ctx().interp.own_rotation()
	assert_bool(cam.quaternion.is_equal_approx(own)).is_true()
	assert_float(cam.fov).is_equal(HelmView.FOV_DEG)
	s.comfort = true
	s.roll_lock = "target"
	s.reduced_fov = true
	_ctx().crew.select("contact", StationFixture.H2)
	_frame()
	assert_float(cam.fov).is_equal_approx(HelmView.FOV_DEG * ComfortCamera.REDUCED_FOV, 1e-4)
	# No orientation known for H2: our deck.
	assert_bool(cam.quaternion.is_equal_approx(own)).is_true()
	# H2 rolled 0.6 rad: the view rolls with H2's deck; the bow stays the view axis.
	var h2_rot: Quaternion = Quaternion(Vector3.FORWARD, 0.6)
	_ctx().view.near[StationFixture.H2] = [NetCodec.pack_quat(h2_rot), Vector3i.ZERO, 0]
	_frame()
	assert_vector(cam.basis.z).is_equal_approx(own * Vector3.BACK, Vector3.ONE * 1e-4)
	var sent: Quaternion = NetCodec.unpack_quat(NetCodec.pack_quat(h2_rot))
	var h2_up: Vector3 = cam.basis.inverse() * (sent * Vector3.UP)
	assert_float(h2_up.x).is_equal_approx(0.0, 1e-4)
	assert_bool(h2_up.y > 0.0).is_true()
	# Reference plane: its up projects straight up on the view.
	s.roll_lock = "reference"
	s.reference_plane = Quaternion(Vector3.FORWARD, 0.7)
	_frame()
	var up: Vector3 = cam.basis.inverse() * (s.reference_plane * Vector3.UP)
	assert_float(up.x).is_equal_approx(0.0, 1e-3)
	assert_bool(up.y > 0.0).is_true()
	# Comfort off: the deck plane again.
	s.comfort = false
	_frame()
	assert_bool(cam.quaternion.is_equal_approx(own)).is_true()


# FT: FT-HLM-004, FT-STN-006
# A marker's label stays clear of the shield ring, its caption, the compass and the read-out
# (the "Kappa 4.7 km" marker sat on the caption), wherever the marker is.
func test_marker_labels_stay_clear_of_the_shield_ring() -> void:
	_frame()
	var font: Font = _panel.hud.get_theme_default_font()
	var reserved: Array[Rect2] = _panel.hud.reserved()
	var inside: Rect2 = Rect2(Vector2.ZERO, _panel.hud.size)
	for text: String in ["Kappa 4.7 km", "U3 8.0 km"]:
		for fx: float in [0.1, 0.35, 0.5, 0.65, 0.8, 0.95]:
			for fy: float in [0.1, 0.3, 0.5, 0.7, 0.9]:
				var p: Vector2 = _panel.hud.size * Vector2(fx, fy)
				var box: Rect2 = _panel.hud.label_rect(font, text, p, 10.0)
				# A marker so deep in a reserved area that no clear spot fits keeps the default.
				if inside.encloses(box):
					for area: Rect2 in reserved:
						assert_bool(box.intersects(area)).is_false()
