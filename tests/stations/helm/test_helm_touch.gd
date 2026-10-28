extends GdUnitTestSuite
## Helm's phone layouts (#28 and its follow-up, owner picks P28-Rails, P28-Shield,
## P28-Chase): two sticks on overlay rails with the pages Fly, Shield, Nav, Radar and Crew
## in the shared frame, and the portrait reduced layout under the banner with the bottom
## tab bar. Every target on every page is at least 48 px with 8 px gaps, clear of the insets
## and the gesture band; every action is within 2 taps of rest (design 2.1); every touch
## control yields the intents its key or stick yields (FT §5.1 touch); desktop and tablet
## keep no rails.
# FT: FT-STN-005

const SETTINGS: String = "user://test_helm_touch.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]

var _vp: SubViewport
var _screen: StationScreen
var _panel: HelmPanel


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## A Helm screen in a viewport of `size` with the simulated `insets`.
func _open(size: Vector2i, insets: Array) -> void:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("helm", SETTINGS)
	ctx.settings.mark_tooltip_seen("helm")
	_screen = StationScreen.new()
	_screen.setup(ctx)
	_vp.add_child(_screen)
	_panel = _screen.panels[0] as HelmPanel
	await _frames()


func _frames(n: int = 3) -> void:
	for i: int in n:
		await get_tree().process_frame
	_panel._process(0.016)


func _ctx() -> StationContext:
	return _screen.ctx


func _ui() -> HelmTouch:
	return _panel.touch_ui


func _cmds(kind: String) -> Array:
	var out: Array = []
	for s: Array in StationFixture.sent(_ctx()).of("command"):
		if s[1][0]["kind"] == kind:
			out.append(s[1][0])
	return out


func _clear_sent() -> void:
	StationFixture.sent(_ctx()).sent.clear()


func _touch(c: Control, at: Vector2, down: bool, index: int = 0) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = down
	c._gui_input(t)


func _drag(c: Control, at: Vector2, index: int = 0) -> void:
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.index = index
	d.position = at
	c._gui_input(d)


func _tap(b: Control) -> void:
	_touch(b, b.size / 2.0, true)
	_touch(b, b.size / 2.0, false)


func _key(name: String, pressed: bool = true) -> void:
	var k: InputEventKey = InputEventKey.new()
	k.physical_keycode = OS.find_keycode_from_string(name)
	k.pressed = pressed
	_screen.feed(k)


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var m: InputEventJoypadMotion = InputEventJoypadMotion.new()
	m.axis = axis
	m.axis_value = value
	_screen.feed(m)


func _audit_ok(report: Dictionary, what: String) -> void:
	# The screen's portrait banner (its ×) ends where the view-top row starts (the frame puts
	# the row at the top of the main area): a request to the frame strand, not Helm's.
	report["tight"] = report["tight"].filter(func(t: String) -> bool: return t != "× | ›")
	for list: String in ["under_min", "under_primary", "in_band", "outside_safe", "tight"]:
		(
			assert_array(report[list])
			. override_failure_message("%s: %s %s" % [what, list, report[list]])
			. is_empty()
		)


## The tab of page `i` in the screen's strip (the top bar on its side, the bottom bar upright).
func _tab(i: int) -> RailButton:
	var strip: PageTabs = _screen.top_bar.tabs if not _ui().portrait else _screen.frame.bottom_tabs
	return strip.tab(i)


## Every target on every page clears the touch rules (48 px, 8 px gaps, safe area, band).
func _audit_pages(what: String) -> void:
	for p: int in _ui().pages.count():
		_ui().pages.current = p
		await _frames()
		_audit_ok(TapAudit.check(_screen), "%s page %s" % [what, _ui().pages.title(p)])
	_ui().pages.current = HelmTouch.PAGE_FLY
	await _frames()


# FT: FT-STN-005, FT-HLM-001
# On its side: two overlay rails, the persistent zone (throttle, All stop, Approach, both
# sticks) on every page, the five pages Fly, Shield, Nav, Radar, Crew in the top bar, and
# the panel in the shared frame; no drawers cover the view.
func test_landscape_pages_and_persistent_zone() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	assert_int(_screen.form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	assert_bool(_ui().portrait).is_false()
	assert_bool(_panel.in_frame).is_true()
	assert_object(_panel.pages).is_same(_ui().pages)
	assert_object(_screen.top_bar.tabs.host).is_same(_ui().pages)
	assert_array(_ui().pages.titles()).is_equal(["Fly", "Shield", "Nav", "Radar", "Crew"])
	# The radar column gives way to the Radar page; the pointer never steers.
	assert_bool(_screen._side.visible).is_false()
	assert_bool(_panel.steering()).is_false()
	assert_array(_ui().layout.drawers).is_empty()
	var persistent: Array[Control] = [
		_ui().turn,
		_ui().slide,
		_ui().throttle,
		_ui().buttons["all_stop"],
		_ui().buttons["approach"]
	]
	for p: int in _ui().pages.count():
		_ui().pages.current = p
		await _frames(1)
		for c: Control in persistent:
			(
				assert_bool(c.is_visible_in_tree())
				. override_failure_message("%s p%d" % [c, p])
				. is_true()
			)
	await _audit_pages("landscape")
	# The ring: tappable with its caption on the Shield page, a glyph without taps elsewhere,
	# hidden on Crew; the radar only on Radar.
	assert_bool(_panel.ring.label).is_false()
	assert_int(_panel.ring.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	_ui().pages.current = HelmTouch.PAGE_SHIELD
	await _frames()
	assert_bool(_panel.ring.label).is_true()
	assert_int(_panel.ring.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_float(_panel.ring.radius()).is_greater_equal(60.0)
	assert_bool(_ui().radar_box.is_visible_in_tree()).is_false()
	_ui().pages.current = HelmTouch.PAGE_RADAR
	await _frames()
	var radar: Rect2 = _ui().radar.get_global_rect()
	assert_float(minf(radar.size.x, radar.size.y)).is_greater_equal(200.0)
	_ui().pages.current = HelmTouch.PAGE_CREW
	await _frames()
	assert_bool(_panel.ring.is_visible_in_tree()).is_false()
	assert_bool(_ui().crew.is_visible_in_tree()).is_true()


# FT: FT-STN-005
# Upright: the reduced layout under the banner, the same five pages in the bottom tab bar,
# every page clean.
func test_portrait_reduced_layout_with_bottom_tabs() -> void:
	await _open(Vector2i(390, 844), PORTRAIT)
	assert_int(_screen.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	assert_bool(_ui().portrait).is_true()
	assert_bool(_screen.rotate_banner.visible).is_true()
	assert_str(_screen.rotate_banner.label.text).is_equal(HelmTouch.ROTATE_TEXT)
	assert_object(_screen.frame.bottom_tabs.host).is_same(_ui().pages)
	assert_bool(_screen.frame.bottom_tabs.is_visible_in_tree()).is_true()
	await _audit_pages("portrait")
	# The view stops above the controls, so the reticle is in sight.
	var block: Rect2 = _ui().block.get_global_rect()
	assert_float(_panel.hud.get_global_rect().end.y).is_less_equal(block.position.y + 0.5)
	# One stick: Turn or Slide.
	_ui().mode_slide.button_pressed = true
	_ui().mode_slide.pressed.emit()
	assert_bool(_ui().stick_slides).is_true()
	assert_str(_ui().turn.label).is_equal("Slide")


# FT: FT-STN-005
func test_rotation_rebuilds_and_desktop_keeps_no_rails() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	_ui().pages.current = HelmTouch.PAGE_SHIELD
	await _frames()
	_vp.size = Vector2i(390, 844)
	SafeArea.simulate(PORTRAIT)
	await _frames()
	assert_bool(_ui().portrait).is_true()
	# The new layout's pages are the ones the screen shows.
	assert_object(_screen.frame.bottom_tabs.host).is_same(_ui().pages)
	_vp.size = Vector2i(844, 390)
	SafeArea.simulate(LANDSCAPE)
	await _frames()
	assert_bool(_ui().portrait).is_false()
	assert_object(_screen.top_bar.tabs.host).is_same(_ui().pages)
	_vp.size = Vector2i(1280, 720)
	SafeArea.simulate([])
	await _frames()
	assert_int(_screen.form).is_equal(LayoutMode.Form.DESKTOP)
	assert_object(_ui()).is_null()
	assert_object(_panel.pages).is_null()
	assert_object(_panel.ring.get_parent()).is_same(_panel)
	assert_bool(_panel.ring.visible).is_true()
	assert_bool(_panel.ring.label).is_true()
	assert_bool(_screen._side.visible).is_true()
	assert_float(_panel.hud.offset_bottom).is_equal(0.0)


## The page holding Helm button `id` (-1 for the persistent zone).
func _page_of(id: String) -> int:
	for p: int in HelmTouch.PAGE_IDS.size():
		if id in HelmTouch.PAGE_IDS[p]:
			return p
	return -1


# FT: FT-HLM-014, FT-HLM-007, FT-HLM-010, FT-HLM-013, FT-HLM-016, FT-HLM-002, FT-HLM-006
func test_rail_taps_send_what_their_keys_send() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	_ctx().crew.select("contact", StationFixture.H2)
	await _frames(1)
	var keys: Dictionary = {
		"all_stop": "Space",
		"align": "L",
		"dock": "H",
		"jump": "J",
		"shield_track": "G",
		"decoupled": "Tab",
		"chase_camera": "C",
	}
	for id: String in keys:
		_ui().pages.current = _page_of(id)
		await _frames(1)
		_clear_sent()
		var chase: bool = _panel.chase
		_key(keys[id])
		_key(keys[id], false)
		var by_key: Array = StationFixture.sent(_ctx()).of("command")
		var chase_by_key: bool = _panel.chase
		_panel.chase = chase
		_clear_sent()
		_tap(_ui().buttons[id])
		var by_touch: Array = StationFixture.sent(_ctx()).of("command")
		assert_array(by_touch).override_failure_message(id).is_equal(by_key)
		assert_bool(_panel.chase).override_failure_message(id).is_equal(chase_by_key)
	_clear_sent()
	_tap(_ui().buttons["all_stop"])
	assert_int(_cmds("helm_all_stop").size()).is_equal(1)


# FT: FT-HLM-005, FT-HLM-015
func test_face_and_approach_are_held_like_their_keys() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	_ctx().crew.select("contact", StationFixture.H2)
	for id: String in ["approach", "face"]:
		var b: RailButton = _ui().buttons[id]
		_touch(b, b.size / 2.0, true)
		await _frames(1)
		assert_bool(_cmds("helm_input").back()[id]).override_failure_message(id).is_true()
		_touch(b, b.size / 2.0, false)
		await _frames(1)
		assert_bool(_cmds("helm_input").back()[id]).override_failure_message(id).is_false()


# FT: FT-STN-005
func test_stick_drags_match_the_pad_sticks() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	var turn: VirtualStick = _ui().turn
	var slide: VirtualStick = _ui().slide
	# Turn: right and down; Slide: right and up.
	_touch(turn, turn.size / 2.0, true, 0)
	_drag(turn, turn.size / 2.0 + Vector2(0.5, 0.3) * turn.radius(), 0)
	_touch(slide, slide.size / 2.0, true, 1)
	_drag(slide, slide.size / 2.0 + Vector2(0.4, -0.6) * slide.radius(), 1)
	var by_touch: Dictionary = _panel.input_command()
	assert_float(absf(by_touch["rotation"].y)).is_greater(0.1)
	assert_float(by_touch["lift"]).is_greater(0.1)
	var t: Vector2 = turn.value
	var s: Vector2 = slide.value
	_touch(turn, turn.size / 2.0, false, 0)
	_touch(slide, slide.size / 2.0, false, 1)
	assert_dict(_panel.input_command()).is_equal(HelmPanel._neutral())
	# The same deflections on a pad (left stick turns, right stick slides).
	# A radial dead zone: put the whole stick at the length that reads |t|.
	var raw: Vector2 = t.normalized() * (InputMatcher.STICK_DEAD_ZONE + t.length() * 0.8)
	_pad_axis(JOY_AXIS_LEFT_X, raw.x)
	_pad_axis(JOY_AXIS_LEFT_Y, raw.y)
	var rs: Vector2 = s.normalized() * (InputMatcher.STICK_DEAD_ZONE + s.length() * 0.8)
	_pad_axis(JOY_AXIS_RIGHT_X, rs.x)
	_pad_axis(JOY_AXIS_RIGHT_Y, rs.y)
	var by_pad: Dictionary = _panel.input_command()
	assert_vector(by_pad["rotation"]).is_equal_approx(by_touch["rotation"], Vector3.ONE * 0.021)
	assert_float(by_pad["strafe"]).is_equal_approx(by_touch["strafe"], 0.021)
	assert_float(by_pad["lift"]).is_equal_approx(by_touch["lift"], 0.021)


# FT: FT-STN-005, FT-SIM-004
func test_throttle_ramps_the_setpoint_like_w_then_lets_go() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	var th: ThrottleSlider = _ui().throttle
	var def: ShipDef = _ctx().ship_def()
	var setpoint: float = float(_panel.helm_block().get("throttle_setpoint", 0.0))
	# Shows the setpoint while untouched.
	assert_float(th.value).is_equal_approx(setpoint / def.assist.speed_max, 0.001)
	# Full throttle asks for more speed: the same helm_surge as holding W.
	_touch(th, Vector2(th.size.x / 2.0, th.track().position.y), true)
	_touch(th, Vector2(th.size.x / 2.0, th.track().position.y), false)
	await _frames(1)
	var by_touch: float = _panel.input_command()["throttle"]
	assert_float(by_touch).is_equal(1.0)
	_ui()._target = NAN
	_ui().touch.axis("helm_surge", 0.0)
	_key("W")
	assert_float(_panel.input_command()["throttle"]).is_equal(by_touch)
	_key("W", false)
	# Reached (the snapshot's setpoint): the throttle lets go and shows the setpoint again.
	_ui()._on_throttle(setpoint / def.assist.speed_max)
	await _frames(1)
	assert_float(_panel.input_command()["throttle"]).is_equal(0.0)
	assert_bool(is_nan(_ui()._target)).is_true()


# FT: FT-HLM-009, FT-HLM-008
# On the Shield page a tap on the ring's 3 o'clock level cell sends what Kp 4 (starboard)
# sends; the glyph on the other pages takes no taps.
func test_tapping_the_ring_on_the_shield_page_sets_the_focus() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	var ring: ShieldRing = _panel.ring
	assert_bool(TouchInput.over(get_tree(), ring.get_global_rect().get_center())).is_true()
	_ui().pages.current = HelmTouch.PAGE_SHIELD
	await _frames()
	_key("Kp 4")
	var by_key: Array = _cmds("set_shield_focus")
	_clear_sent()
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = ring.centre() + Vector2(ring.radius() * 0.6, 0.0)
	ring._gui_input(mb)
	var focus: Array = _cmds("set_shield_focus")
	assert_int(focus.size()).is_equal(1)
	assert_float((focus[0]["direction"] as Vector3).x).is_greater(0.9)
	assert_vector(focus[0]["direction"]).is_equal_approx(by_key[0]["direction"], Vector3.ONE * 1e-4)
	# A finger on the ring belongs to it, not to the screen's select.
	assert_bool(TouchInput.over(get_tree(), ring.get_global_rect().get_center())).is_true()


# FT: FT-STN-003
func test_a_tap_on_the_radar_page_selects() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	_ui().pages.current = HelmTouch.PAGE_RADAR
	await _frames()
	var radar: DiscRadar = _ui().radar
	_ctx().crew.selection = {}
	var target: Dictionary = {}
	var at: Vector2 = Vector2.ZERO
	for x: int in range(0, int(radar.size.x), 4):
		for y: int in range(0, int(radar.size.y), 4):
			var item: Dictionary = radar.item_at(Vector2(x, y))
			if not item.is_empty() and item["kind"] == "contact":
				target = item
				at = Vector2(x, y)
				break
		if not target.is_empty():
			break
	assert_dict(target).is_not_empty()
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	_ui()._on_radar_input(mb)
	assert_bool(_ctx().crew.is_selected("contact", target["id"])).is_true()


# FT: FT-HLM-003, FT-HLM-004, FT-HLM-012
# The HUD keeps clear of the rails and the view-top row (P28-Common).
func test_hud_keeps_its_read_outs_and_arrows_clear_of_the_rails() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	var hud: HelmHud = _panel.hud
	var free: Rect2 = hud.area()
	var left: Rect2 = _ui().layout.left.get_global_rect()
	var right: Rect2 = _ui().layout.right.get_global_rect()
	var row: Rect2 = _screen.frame.selection_chip.get_global_rect()
	var to_global: Transform2D = hud.get_global_transform()
	for r: Rect2 in [hud.readout_rect(), hud.thrust_rect()] + hud.compass_boxes():
		var g: Rect2 = to_global * r
		(
			assert_bool(g.intersects(left) or g.intersects(right) or g.intersects(row))
			. override_failure_message("%s over a rail or the view-top row" % g)
			. is_false()
		)
	# An arrow that would land on the flight read-out moves along the edge, off it.
	var tip: Vector2 = Vector2(
		free.grow(-HelmHud.EDGE).position.x, hud.readout_rect().get_center().y
	)
	var moved: Vector2 = hud.arrow_tip(tip)
	assert_bool(hud.readout_rect().grow(HelmHud.ARROW_CLEAR).has_point(moved)).is_false()
	assert_float(moved.x).is_equal(tip.x)
	# Off-screen arrows sit inside the clear view.
	assert_bool(free.has_point(hud._edge_point(Vector2.LEFT))).is_true()
	assert_bool(free.has_point(hud._edge_point(Vector2(1.0, -0.3)))).is_true()


# FT: FT-STN-005, FT-STN-014
func test_matcher_touch_intents_follow_focus_toggles_and_release() -> void:
	var m: InputMatcher = InputMatcher.new()
	m.set_context(["helm", "weapons"], "helm")
	assert_array(m.touch_press("all_stop")).has_size(1)
	assert_str(m.touch_press("all_stop")[0]["target"]).is_equal("helm")
	assert_str(m.touch_press("all_stop")[0]["device"]).is_equal(IntentTable.TOUCH)
	# Another station's intent reaches nobody while Helm has the focus.
	assert_array(m.touch_press("mount_1")).is_empty()
	m.touch_axis("helm_yaw", 0.5)
	assert_float(m.axis("helm_yaw")).is_equal(0.5)
	m.touch_axis("aim_x", 0.5)
	assert_float(m.axis("aim_x")).is_equal(0.0)
	var down: Array[Dictionary] = m.touch_hold("approach", true)
	assert_bool(down[0]["pressed"]).is_true()
	assert_bool(m.is_held("approach")).is_true()
	assert_bool(m.touch_hold("approach", false)[0]["pressed"]).is_false()
	assert_bool(m.is_held("approach")).is_false()
	# A player's hold-to-toggle choice applies to the touch button too.
	m.bindings.set_toggle("approach", true)
	m.touch_hold("approach", true)
	m.touch_hold("approach", false)
	assert_bool(m.is_held("approach")).is_true()
	m.touch_hold("approach", true)
	assert_bool(m.is_held("approach")).is_false()
	m.touch_hold("face", true)
	m.release_all()
	assert_bool(m.is_held("face")).is_false()
	assert_float(m.axis("helm_yaw")).is_equal(0.0)


# FT: FT-HLM-004, FT-STN-006
# Upright (the l5_ph_helm_portrait fixture: H2 selected and pinged), marker and arrow labels
# keep clear of each other, the shield ring, the compass and the read-outs (#28).
func test_portrait_labels_do_not_collide() -> void:
	await _open(Vector2i(390, 844), PORTRAIT)
	_ctx().crew.select("contact", StationFixture.H2)
	var p: Dictionary = {"ship": 0, "kind": "contact", "id": StationFixture.H2, "by": "Bo"}
	_ctx().crew.handle_event({"type": "ping", "payload": p}, StationFixture.NOW_MS - 1000)
	await _frames()
	var hud: HelmHud = _panel.hud
	assert_int(hud._labels.size()).is_greater(1)
	for label: Rect2 in hud._labels:
		for o: Rect2 in hud._placed:
			if o != label:
				(
					assert_bool(label.intersects(o))
					. override_failure_message("%s over %s" % [label, o])
					. is_false()
				)
		for r: Rect2 in hud.reserved():
			var cover: float = label.intersection(r).get_area()
			assert_float(cover).is_less_equal(HelmHud.SLIGHT * label.get_area())
