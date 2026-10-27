extends GdUnitTestSuite
## Relay on a phone (#28, overlay rails A): the map fills the screen (no radar column)
## under translucent rails, probe tools and the mark left, the inbox actions right,
## Contacts and Share in drawers; upright the same buttons sit in rows under the map. The
## keyboard-and-mouse hint never shows on a phone, only an armed probe's or hazard's.
## Taps stay at least 48 px, 8 px apart and clear of the insets and the bottom 24 px; a
## tap on a rail button does what the HUD button and the key do.
# FT: FT-STN-005

const SETTINGS: String = "user://test_relay_phone.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("relay", SETTINGS)
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	_vp.add_child(s)
	await _frames(4)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _relay(s: StationScreen) -> RelayPanel:
	return s.panels[0] as RelayPanel


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


# FT: FT-STN-005, FT-RLY-004, FT-RLY-008
func test_landscape_overlay_rails_over_the_full_map() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: RelayPanel = _relay(s)
	assert_object(p.phone).is_not_null()
	assert_bool(p.full_screen()).is_true()
	assert_bool(s.radar.is_visible_in_tree()).is_false()
	assert_bool(p.hud.visible).is_false()
	# The map is full size; its centre sits in the uncovered part between the rails.
	assert_vector(p.map.size).is_equal(p.phone.layout.size)
	assert_float(p.map.size.x).is_equal(p.size.x)
	var free: Rect2 = p.phone.layout.content_rect_in(p.map)
	assert_object(p.map.view_rect).is_equal(free)
	assert_vector(p.map.project(Vector3.ZERO)).is_equal_approx(free.get_center(), Vector2.ONE)
	var left: TouchRail = p.phone.layout.left
	var right: TouchRail = p.phone.layout.right
	for b: Control in [p.phone.launch, p.phone.hazard, p.phone.lanes, p.phone.mark]:
		assert_bool(left.is_ancestor_of(b)).is_true()
	for b: Control in [p.phone.accept, p.phone.decline, p.hud.send_to, p.phone.send]:
		assert_bool(right.is_ancestor_of(b)).is_true()
	_assert_taps_ok(s, "landscape")
	# Each drawer open in turn keeps the rules too.
	for d: TouchDrawer in [p.phone.contacts, p.phone.share]:
		d.open()
		await _frames(2)
		_assert_taps_ok(s, "drawer " + d.title.text)
		d.close()


# FT: FT-STN-005
func test_phone_shows_no_mouse_hint_only_the_armed_one() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: RelayPanel = _relay(s)
	assert_bool(p._hint.visible).is_false()
	_tap(p.phone.hazard)
	assert_str(p.armed).is_equal("hazard")
	p.refresh()
	assert_bool(p._hint.visible).is_true()
	assert_str(p._hint.text).is_equal(tr("relay.armed_hazard"))
	# The armed hint stays between the rails.
	var free: Rect2 = p.phone.layout.content_rect_in(p)
	assert_float(p._hint.get_rect().position.x).is_greater_equal(free.position.x)
	assert_float(p._hint.get_rect().end.x).is_less_equal(free.end.x)


# FT: FT-STN-005, FT-RLY-002, FT-RLY-008, FT-RLY-009
func test_rail_taps_do_what_the_hud_and_keys_do() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: RelayPanel = _relay(s)
	var sent: Callable = func(kind: String) -> Array:
		return StationFixture.sent(s.ctx).of("command").filter(
			func(c: Array) -> bool: return c[1][0]["kind"] == kind
		)
	_tap(p.phone.lanes)
	assert_int(sent.call("flag_lanes").size()).is_equal(1)
	p.handle_intent({"id": "flag_lanes", "pressed": true})
	assert_int(sent.call("flag_lanes").size()).is_equal(2)
	_tap(p.phone.hazard)
	assert_str(p.armed).is_equal("hazard")
	# No probes in stock: Launch is disabled, as the HUD's.
	assert_bool(p.phone.launch.disabled).is_equal(p.hud.launch.disabled)
	# The mark button walks the marks, for Send.
	var given: Array = []
	for k: int in 2:
		var m: Dictionary = {"slot": k, "name": CrewState.MARK_NAMES[k], "contact": -1}
		m.merge({"x": 100.0 * k, "y": 0.0, "z": 0.0, "by": "Bo"})
		given.append(m)
	s.ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": given}}, 0)
	await _frames(1)
	var crew: CrewState = s.ctx.crew
	assert_int(crew.marks.size()).is_equal(2)
	_tap(p.phone.mark)
	assert_bool(crew.is_selected("mark", int(crew.marks[0]["slot"]))).is_true()
	await _frames(1)
	assert_str(p.phone.mark.text).is_equal(str(crew.marks[0]["name"]))
	_tap(p.phone.mark)
	assert_bool(crew.is_selected("mark", int(crew.marks[1]["slot"]))).is_true()
	# A contact in the drawer selects it.
	p.phone.contacts.open()
	await _frames(1)
	var first: RailButton = p.phone._contact_box.get_child(0) as RailButton
	_tap(first)
	assert_str(str(crew.selection.get("kind", ""))).is_equal("contact")


# FT: FT-STN-005
func test_portrait_reduced_layout_and_turning_back() -> void:
	var s: StationScreen = await _screen(Vector2i(390, 844), PORTRAIT)
	var p: RelayPanel = _relay(s)
	assert_int(p.phone.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	assert_bool(s.rotate_banner.visible).is_true()
	assert_bool(p.hud.visible).is_false()
	assert_float(p.map.size.y).is_greater(200.0)
	_assert_taps_ok(s, "portrait")
	SafeArea.simulate(LANDSCAPE)
	_vp.size = Vector2i(844, 390)
	await _frames(4)
	assert_int(p.phone.form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	_assert_taps_ok(s, "turned")
	SafeArea.simulate([])
	_vp.size = Vector2i(1280, 720)
	await _frames(4)
	assert_object(p.phone).is_null()
	assert_bool(p.hud.visible).is_true()
	assert_object(p.map.get_parent()).is_same(p)
	assert_object(p.hud.send_to.get_parent()).is_same(p.hud._mail_buttons)
	assert_object(p.map.view_rect).is_equal(Rect2())
	assert_bool(s.radar.is_visible_in_tree()).is_true()
