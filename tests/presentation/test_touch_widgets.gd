extends GdUnitTestSuite
## The shared touch widgets of presentation/touch/ (#28): rail buttons are primary-sized
## and answer any finger; sticks and the throttle follow their own finger while another
## holds a button; tabs, drawers, rails and the content inset; the fullscreen button
## shows only where offered; TouchInput keeps rail taps from the station's bindings.
# FT: FT-STN-005

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	TouchInput.held = 0
	_vp = auto_free(SubViewport.new())
	_vp.size = Vector2i(844, 390)
	_vp.gui_disable_input = false
	add_child(_vp)
	var holder: Control = Control.new()
	holder.theme = LayoutMode.theme_for(LayoutMode.Kind.PHONE)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.name = "Holder"
	_vp.add_child(holder)


func after_test() -> void:
	SafeArea.simulate([])
	FullscreenButton.forced = -1
	RotateBanner.dismissed_here = false


func _holder() -> Control:
	return _vp.get_node("Holder") as Control


func _put(c: Control, rect: Rect2) -> Control:
	_holder().add_child(c)
	c.position = rect.position
	c.size = rect.size
	return c


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	_vp.push_input(t)


func _drag(index: int, pos: Vector2) -> void:
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.index = index
	d.position = pos
	_vp.push_input(d)


func test_theme_sizes_amend_d218() -> void:
	assert_int(UiTheme.TOUCH_PRIMARY).is_equal(48)
	assert_int(UiTheme.TOUCH_MIN).is_equal(44)
	assert_int(UiTheme.TOUCH_GAP).is_equal(8)
	var b: RailButton = _put(RailButton.make("Approach"), Rect2(0, 0, 0, 0)) as RailButton
	await get_tree().process_frame
	var least: Vector2 = b.get_combined_minimum_size()
	assert_float(least.y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
	assert_float(least.x).is_greater_equal(UiTheme.TOUCH_PRIMARY)
	assert_str(b.theme_type_variation).is_equal("RailButton")
	b.role = RailButton.Role.DANGER
	assert_str(b.theme_type_variation).is_equal("RailDangerButton")
	assert_int(b.focus_mode).is_equal(Control.FOCUS_NONE)


func test_second_finger_presses_a_rail_button_while_a_stick_is_held() -> void:
	var stick: VirtualStick = _put(VirtualStick.new(), Rect2(10, 200, 120, 120)) as VirtualStick
	var fire: RailButton = _put(RailButton.make("FIRE"), Rect2(700, 250, 120, 100)) as RailButton
	fire.hold = true
	var events: Array = []
	fire.pressed.connect(func() -> void: events.append("pressed"))
	fire.held.connect(func(down: bool) -> void: events.append(down))
	var moves: Array = []
	stick.moved.connect(func(v: Vector2) -> void: moves.append(v))
	await get_tree().process_frame
	_touch(0, Vector2(70, 260), true)
	_drag(0, Vector2(130, 260))
	assert_float(stick.value.x).is_greater(0.9)
	assert_float(absf(stick.value.y)).is_less(0.01)
	assert_int(TouchInput.held).is_equal(1)
	_touch(1, Vector2(760, 300), true)
	assert_array(events).is_equal([true])
	assert_int(TouchInput.held).is_equal(2)
	_touch(1, Vector2(760, 300), false)
	assert_array(events).is_equal([true, false, "pressed"])
	# The stick still follows finger 0 and springs back on release.
	_drag(0, Vector2(70, 200))
	assert_float(stick.value.y).is_less(-0.9)
	_touch(0, Vector2(70, 200), false)
	assert_vector(stick.value).is_equal(Vector2.ZERO)
	assert_vector(moves.back()).is_equal(Vector2.ZERO)
	assert_int(TouchInput.held).is_equal(0)


func test_stick_dead_zone_and_scale() -> void:
	assert_vector(VirtualStick.value_for(Vector2(5, 0), 50.0, 0.12)).is_equal(Vector2.ZERO)
	assert_vector(VirtualStick.value_for(Vector2(50, 0), 50.0, 0.12)).is_equal(Vector2(1, 0))
	assert_vector(VirtualStick.value_for(Vector2(0, -80), 50.0, 0.12)).is_equal(Vector2(0, -1))
	var half: Vector2 = VirtualStick.value_for(Vector2(28, 0), 50.0, 0.12)
	assert_float(half.x).is_equal_approx(0.5, 0.001)


func test_emulated_mouse_is_ignored_and_owned() -> void:
	var b: RailButton = _put(RailButton.make("Face"), Rect2(700, 60, 80, 48)) as RailButton
	var n: Array = [0]
	b.pressed.connect(func() -> void: n[0] += 1)
	await get_tree().process_frame
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = Vector2(740, 80)
	mb.pressed = true
	_vp.push_input(mb)
	mb = mb.duplicate()
	mb.pressed = false
	_vp.push_input(mb)
	assert_int(n[0]).is_equal(0)
	assert_bool(TouchInput.owns(get_tree(), mb)).is_true()
	var away: InputEventMouseButton = mb.duplicate()
	away.position = Vector2(400, 200)
	assert_bool(TouchInput.owns(get_tree(), away)).is_false()
	# A real mouse (desktop) is the station's unless it is over a widget.
	var real: InputEventMouseButton = away.duplicate()
	real.device = 0
	assert_bool(TouchInput.owns(get_tree(), real)).is_false()
	# A real mouse still clicks the button.
	b.pressed.emit()
	assert_int(n[0]).is_equal(1)


func test_throttle_follows_its_finger() -> void:
	var t: ThrottleSlider = _put(ThrottleSlider.new(), Rect2(10, 60, 48, 300)) as ThrottleSlider
	var seen: Array = []
	t.value_changed.connect(func(v: float) -> void: seen.append(v))
	await get_tree().process_frame
	var track: Rect2 = t.track()
	assert_float(t.value_at(track.position.y)).is_equal(1.0)
	assert_float(t.value_at(track.end.y)).is_equal(0.0)
	_touch(3, Vector2(30, 60 + track.position.y + track.size.y * 0.5), true)
	assert_float(t.value).is_equal_approx(0.5, 0.05)
	_drag(3, Vector2(30, 60 + track.position.y))
	assert_float(t.value).is_equal(1.0)
	_touch(3, Vector2(30, 60 + track.position.y), false)
	assert_float(t.value).is_equal(1.0)
	assert_float(seen.back()).is_equal(1.0)
	# A reverse range snaps to zero near the middle.
	t.min_value = -1.0
	assert_float(t.value_at(track.position.y + track.size.y * 0.52)).is_equal(0.0)


func test_tabs_show_one_page() -> void:
	var tabs: TouchTabs = TouchTabs.new()
	var a: Control = Control.new()
	var b: Control = Control.new()
	_put(tabs, Rect2(600, 60, 200, 300))
	assert_int(tabs.add_tab("Nav", a)).is_equal(0)
	assert_int(tabs.add_tab("Shield", b)).is_equal(1)
	assert_int(tabs.current).is_equal(0)
	assert_bool(a.visible and not b.visible).is_true()
	var changed: Array = []
	tabs.tab_changed.connect(func(i: int) -> void: changed.append(i))
	await get_tree().process_frame
	var r: Rect2 = tabs.tab_button(1).get_global_rect()
	_touch(0, r.get_center(), true)
	_touch(0, r.get_center(), false)
	assert_int(tabs.current).is_equal(1)
	assert_bool(b.visible and not a.visible).is_true()
	assert_bool(tabs.tab_button(1).button_pressed).is_true()
	assert_bool(tabs.tab_button(0).button_pressed).is_false()
	assert_array(changed).is_equal([1])
	# Tapping the shown tab keeps it.
	_touch(0, r.get_center(), true)
	_touch(0, r.get_center(), false)
	assert_int(tabs.current).is_equal(1)


func test_rails_drawers_and_content_inset() -> void:
	SafeArea.simulate([47, 0, 47, 21])
	var layout: RailLayout = RailLayout.new()
	_holder().add_child(layout)
	var view: Control = Control.new()
	layout.set_content(view)
	var stop: RailButton = RailButton.make("All stop", RailButton.Role.DANGER)
	layout.rail(SIDE_LEFT).add(stop)
	layout.rail(SIDE_RIGHT).add_row([RailButton.make("Face"), RailButton.make("Align")])
	var drawer: TouchDrawer = layout.add_drawer(TouchDrawer.new("Radar", SIDE_LEFT))
	var opener: RailButton = layout.rail(SIDE_LEFT).add(RailButton.make("Radar")) as RailButton
	drawer.bind_opener(opener)
	var rects: Array = []
	layout.content_rect_changed.connect(func(r: Rect2) -> void: rects.append(r))
	for i: int in 3:
		await get_tree().process_frame
	# The holder fills the viewport here, so the layout's tap area is the safe area.
	var tap: Rect2 = layout.tap_area()
	assert_float(tap.position.x).is_equal(47.0)
	assert_float(tap.end.x).is_equal(844.0 - 47.0)
	assert_float(tap.end.y).is_equal(390.0 - SafeArea.GESTURE_BAND)
	var left: Rect2 = layout.left.get_global_rect()
	var right: Rect2 = layout.right.get_global_rect()
	assert_bool(tap.encloses(left) and tap.encloses(right)).is_true()
	# Overlay: the view is full size, its free part between the rails.
	assert_vector(view.size).is_equal(Vector2(844, 390))
	var open_part: Rect2 = layout.content_rect_in(view)
	assert_float(open_part.position.x).is_equal(left.end.x + UiTheme.TOUCH_GAP)
	assert_float(open_part.end.x).is_equal(right.position.x - UiTheme.TOUCH_GAP)
	assert_array(rects).is_not_empty()
	# Docked: the view narrows to the space between the rails.
	layout.docked = true
	await get_tree().process_frame
	assert_float(view.position.x).is_equal(left.end.x)
	assert_float(view.get_global_rect().end.x).is_equal(right.position.x)
	assert_str(layout.left.theme_type_variation).is_equal("DockedRail")
	# The drawer opens beside the left rail from its opener and closes from its own button.
	_touch(0, opener.get_global_rect().get_center(), true)
	_touch(0, opener.get_global_rect().get_center(), false)
	await get_tree().process_frame
	assert_bool(drawer.is_open()).is_true()
	assert_bool(opener.button_pressed).is_true()
	assert_float(drawer.position.x).is_greater_equal(left.end.x)
	drawer.close_button.pressed.emit()
	assert_bool(drawer.is_open()).is_false()
	assert_bool(opener.button_pressed).is_false()
	# Every target passes the touch rules.
	drawer.open()
	await get_tree().process_frame
	var report: Dictionary = TapAudit.check(layout)
	for key: String in ["under_min", "under_primary", "in_band", "outside_safe", "tight"]:
		assert_array(report[key]).override_failure_message("%s: %s" % [key, report[key]]).is_empty()


func test_fullscreen_button_only_where_offered() -> void:
	FullscreenButton.forced = 0
	var b: FullscreenButton = (
		_put(FullscreenButton.new(), Rect2(60, 60, 160, 48)) as FullscreenButton
	)
	await get_tree().process_frame
	assert_bool(b.visible).is_false()
	FullscreenButton.forced = 1
	b._refresh()
	assert_bool(b.visible).is_true()
	assert_str(b.text).is_equal(FullscreenButton.TEXT)
	assert_float(b.get_combined_minimum_size().y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
	assert_bool(b.is_in_group(TouchInput.GROUP)).is_true()
	# Off the web nothing offers it.
	FullscreenButton.forced = -1
	assert_bool(FullscreenButton.offered()).is_false()


func test_rotate_banner_only_upright_on_a_phone() -> void:
	var banner: RotateBanner = _put(RotateBanner.new(), Rect2(0, 0, 300, 56)) as RotateBanner
	await get_tree().process_frame
	assert_bool(banner.visible).is_false()
	_vp.size = Vector2i(390, 844)
	await get_tree().process_frame
	assert_bool(banner.visible).is_true()
	var seen: Array = [false]
	banner.dismissed.connect(func() -> void: seen[0] = true)
	banner.close_button.pressed.emit()
	assert_bool(banner.visible).is_false()
	assert_bool(seen[0]).is_true()
	_vp.size = Vector2i(391, 844)
	await get_tree().process_frame
	assert_bool(banner.visible).is_false()
