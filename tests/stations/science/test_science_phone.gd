extends GdUnitTestSuite
## Science on a phone (#28, overlay rails A): landscape keeps the radar between the rails
## (it used to vanish), the list and card left, the eight actions right; a scan puts its
## axis chips left and Cancel and Submit right, a hack its hint left and Cancel right,
## all real buttons. Upright is the reduced layout under the "turn sideways" banner. Every
## form keeps its taps at least 48 px (44 for list rows), 8 px apart, clear of the insets
## and the bottom 24 px; a tap on a rail button sends what the key sends.
# FT: FT-STN-005

const SETTINGS: String = "user://test_science_phone.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const H2: int = StationFixture.H2

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## A Science screen in a phone-sized viewport with the given insets and SCIENCE block.
func _screen(size: Vector2i, insets: Array, kind: String = "cards") -> StationScreen:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("science", SETTINGS)
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	ctx.view.blocks[StationViews.Section.SCIENCE] = ScienceShotBlocks.block(kind)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	_vp.add_child(s)
	await _frames(4)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _sci(s: StationScreen) -> SciencePanel:
	return s.panels[0] as SciencePanel


func _cmds(s: StationScreen, kind: String) -> Array:
	return StationFixture.sent(s.ctx).of("command").filter(
		func(c: Array) -> bool: return c[1][0]["kind"] == kind
	)


## A finger's tap on a rail button.
func _tap(b: RailButton) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = 0
	t.position = b.size / 2.0
	t.pressed = true
	b._gui_input(t)
	t.pressed = false
	b._gui_input(t)


func _assert_taps_ok(s: StationScreen, what: String) -> void:
	var report: Dictionary = TapAudit.check(s)
	assert_array(report["targets"]).is_not_empty()
	for rule: String in ["under_min", "under_primary", "in_band", "outside_safe", "tight"]:
		(
			assert_array(report[rule])
			. override_failure_message("%s %s: %s" % [what, rule, report[rule]])
			. is_empty()
		)


# FT: FT-STN-005, FT-STN-002, FT-SCI-001
func test_landscape_overlay_rails_keep_the_radar_between_them() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: SciencePanel = _sci(s)
	assert_object(p.phone).is_not_null()
	assert_int(p.phone.form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	assert_bool(p.full_screen()).is_true()
	# The radar is drawn, full size under the rails, its disc in the uncovered part.
	assert_bool(p.radar.is_visible_in_tree()).is_true()
	assert_float(p.radar.size.y).is_greater(250.0)
	var free: Rect2 = p.phone.layout.content_rect_in(p.radar)
	assert_bool(free.has_area()).is_true()
	assert_object(p.radar.view_rect).is_equal(free)
	assert_bool(free.has_point(p.radar.disc_centre())).is_true()
	assert_float(p.radar.disc_radius() * 2.0).is_less_equal(free.size.x)
	# List and card on the left rail, the actions on the right.
	var left: TouchRail = p.phone.layout.left
	var right: TouchRail = p.phone.layout.right
	assert_bool(left.is_ancestor_of(p._list)).is_true()
	assert_bool(left.is_ancestor_of(p.card_view)).is_true()
	assert_int(p.phone.actions.size()).is_equal(8)
	for b: RailButton in p.phone.actions.values():
		assert_bool(right.is_ancestor_of(b) and b.is_visible_in_tree()).is_true()
	_assert_taps_ok(s, "landscape")


# FT: FT-STN-005, FT-SCI-004
func test_landscape_scan_puts_axes_left_and_submit_right() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE, "scan")
	var p: SciencePanel = _sci(s)
	assert_bool(p.scan_game.footer).is_false()
	var open: int = p.scan_game.open_axes().size()
	var shown: Array = p.phone.axis_buttons.filter(
		func(b: RailButton) -> bool: return b.is_visible_in_tree()
	)
	assert_int(shown.size()).is_equal(open)
	assert_bool(p.phone.layout.left.is_ancestor_of(shown[0])).is_true()
	assert_bool(p.phone.submit.is_visible_in_tree()).is_true()
	assert_bool(p.phone.layout.right.is_ancestor_of(p.phone.submit)).is_true()
	assert_bool(p.phone.actions["scan"].is_visible_in_tree()).is_false()
	assert_bool(p._list.is_visible_in_tree()).is_false()
	# The minigame sits between the rails.
	var free: Rect2 = p.phone.layout.content_rect_in(p._stage)
	assert_object(Rect2(p.scan_game.position, p.scan_game.size)).is_equal(free)
	_assert_taps_ok(s, "scan")
	# A tap on an axis chip picks the axis, Submit and Cancel send what Enter and
	# Backspace send.
	_tap(shown[1])
	assert_int(p.scan_game.selected).is_equal(1)
	_tap(p.phone.submit)
	assert_int(_cmds(s, "science_scan_submit").size()).is_equal(1)
	p.handle_intent({"id": "accept", "pressed": true})
	assert_int(_cmds(s, "science_scan_submit").size()).is_equal(2)
	_tap(p.phone.cancel)
	assert_int(_cmds(s, "science_cancel").size()).is_equal(1)


# FT: FT-STN-005, FT-SCI-006
func test_landscape_hack_nodes_are_tap_sized_and_apart() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE, "hack")
	var p: SciencePanel = _sci(s)
	var g: HackGame = p.hack_game
	assert_bool(g.footer).is_false()
	assert_bool(p.phone.cancel.is_visible_in_tree()).is_true()
	assert_bool(p.phone.submit.is_visible_in_tree()).is_false()
	# Rows and columns at least a primary target plus the gap apart (the rows overlapped).
	assert_float(g.node_centre(g.cols).y - g.node_centre(0).y).is_greater_equal(
		UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP
	)
	assert_float(g.node_centre(1).x - g.node_centre(0).x).is_greater_equal(
		UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP
	)
	var nodes: Array = TapAudit.targets(s).filter(
		func(t: Dictionary) -> bool: return str(t["text"]).begins_with("Control Node")
	)
	assert_int(nodes.size()).is_equal(g.cols * g.rows)
	_assert_taps_ok(s, "hack")
	_tap(p.phone.cancel)
	assert_int(_cmds(s, "science_cancel").size()).is_equal(1)


# FT: FT-STN-005, FT-SCI-003, FT-SCI-009, FT-SCI-010
func test_rail_taps_send_what_the_keys_send() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: SciencePanel = _sci(s)
	s.ctx.crew.select("contact", H2)
	await _frames(1)
	for pair: Array in [
		["mode", "sci_mode", "science_sensor_mode"],
		["ping", "sci_ping", "science_ping"],
		["mark", "sci_scan_mark", "science_scan_mark"],
		["self", "sci_self_scan", "science_self_scan"],
		["scan", "sci_scan", "science_scan"],
		["hack", "sci_hack", "science_hack"],
	]:
		_tap(p.phone.actions[pair[0]])
		var by_tap: Array = _cmds(s, pair[2])
		assert_int(by_tap.size()).override_failure_message(pair[0]).is_equal(1)
		p.handle_intent({"id": pair[1], "pressed": true})
		var both: Array = _cmds(s, pair[2])
		assert_int(both.size()).is_equal(2)
		assert_dict(both[0][1][0]).is_equal(both[1][1][0])
	var before: String = p.phone.actions["sub"].text
	_tap(p.phone.actions["sub"])
	await _frames(1)
	assert_str(p.phone.actions["sub"].text).is_not_equal(before)


# FT: FT-STN-005
func test_portrait_reduced_layout_keeps_taps_safe() -> void:
	for kind: String in ["cards", "scan", "hack"]:
		var s: StationScreen = await _screen(Vector2i(390, 844), PORTRAIT, kind)
		var p: SciencePanel = _sci(s)
		assert_int(p.phone.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
		assert_bool(s.rotate_banner.visible).is_true()
		assert_float(p._stage.size.y).is_greater_equal(SciencePhone.STAGE_MIN_H)
		_assert_taps_ok(s, "portrait " + kind)
		_vp.queue_free()
		await _frames(1)


# FT: FT-STN-005
func test_turning_the_phone_rebuilds_and_a_desktop_gets_the_wide_layout() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: SciencePanel = _sci(s)
	SafeArea.simulate(PORTRAIT)
	_vp.size = Vector2i(390, 844)
	await _frames(4)
	assert_int(p.phone.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	_assert_taps_ok(s, "turned")
	SafeArea.simulate([])
	_vp.size = Vector2i(1280, 720)
	await _frames(4)
	assert_object(p.phone).is_null()
	assert_bool(p._rows.visible).is_true()
	assert_object(p._list.get_parent()).is_same(p._top)
	assert_object(p._stage.get_parent()).is_same(p._top)
	assert_object(p.card_view.get_parent()).is_same(p._top)
	assert_bool(p.scan_game.footer).is_true()
	assert_object(p.radar.view_rect).is_equal(Rect2())
	assert_float(p.radar.touch_min).is_equal(0.0)
