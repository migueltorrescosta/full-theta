extends HelmSuite
## Helm panel (T051): cockpit, HUD, compass, off-screen arrows, shield ring, envelope,
## pointer and comfort.


# FT: FT-HLM-001, FT-STN-002
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
	var p: Dictionary = {
		"ship": 0, "kind": "contact", "id": StationFixture.F4, "site": 0, "by": "Bo"
	}
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
