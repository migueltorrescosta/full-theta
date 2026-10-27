extends GdUnitTestSuite
## Phone layouts of Engineering, Comms, Captain and the Viewer (#28, strand PR): on a phone
## on its side every control sits in a thumb rail, at least 44 px (48 for rail buttons) with
## 8 px gaps, never under an inset or in the gesture band; the rail buttons send what the
## keys send; upright the reduced layouts stay operable; tablets and desktops keep theirs.
# FT: FT-STN-005

const SETTINGS: String = "user://test_phone_rest_layouts.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "in_band", "outside_safe", "tight"]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, entry: String, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	CommsFixture.install(ctx)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	await _frames(4)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _assert_clean(root: Control, what: String) -> void:
	var report: Dictionary = TapAudit.check(root)
	assert_array(report["targets"]).override_failure_message(what + ": no targets").is_not_empty()
	for k: String in AUDIT:
		(
			assert_array(report[k])
			. override_failure_message("%s %s: %s" % [what, k, report[k]])
			. is_empty()
		)


func _drop(s: StationScreen) -> void:
	s.get_parent().remove_child(s)
	s.free()


# FT: FT-STN-005, FT-NET-018
func test_landscape_panels_keep_taps_in_the_safe_area() -> void:
	for entry: String in ["engineering", "comms", "captain", "viewer", "systems"]:
		var s: StationScreen = await _screen(Vector2i(844, 390), entry, LANDSCAPE)
		assert_int(s.form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
		# The panel's own controls (the screen's share column is the shell's).
		if entry != "viewer":
			_assert_clean(s.focused_panel(), entry)
		_drop(s)


# FT: FT-STN-005
func test_portrait_panels_stay_operable() -> void:
	for entry: String in ["engineering", "comms", "captain"]:
		var s: StationScreen = await _screen(Vector2i(390, 844), entry, PORTRAIT)
		assert_int(s.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
		assert_bool(s.rotate_banner.visible).is_true()
		_assert_clean(s.focused_panel(), entry)
		_drop(s)


# FT: FT-ENG-002, FT-ENG-003, FT-ENG-008, FT-STN-005
# Each rail button sends exactly what its key sends.
func test_engineering_rail_buttons_send_the_key_intents() -> void:
	for a: Array in EngineeringPanel.TOUCH_ACTIONS:
		var id: String = a[0]
		var touch: StationScreen = await _screen(Vector2i(844, 390), "engineering", LANDSCAPE)
		var tp: EngineeringPanel = touch.focused_panel()
		assert_object(tp.touch_layout).is_not_null()
		assert_bool(tp.touch_layout.visible).is_true()
		var b: RailButton = tp.touch_buttons[id]
		assert_bool(b.is_visible_in_tree()).override_failure_message(id).is_true()
		b.pressed.emit()
		var keys: StationScreen = await _screen(Vector2i(1280, 720), "engineering", [])
		var kp: EngineeringPanel = keys.focused_panel()
		assert_object(kp.touch_layout).is_null()
		kp.handle_intent({"id": id, "pressed": true, "device": IntentTable.KBM})
		var by_touch: Array = StationFixture.sent(touch.ctx).sent
		assert_array(by_touch).override_failure_message("%s: %s" % [id, by_touch]).is_equal(
			StationFixture.sent(keys.ctx).sent
		)
		_drop(touch)
		_drop(keys)


# FT: FT-STN-005
# Rotating back to a desktop-sized window restores the desktop arrangement.
func test_engineering_and_comms_return_to_the_desktop_arrangement() -> void:
	for entry: String in ["engineering", "comms"]:
		var s: StationScreen = await _screen(Vector2i(844, 390), entry, LANDSCAPE)
		var p: StationPanel = s.focused_panel()
		var layout: RailLayout = p.get("touch_layout")
		assert_bool(layout.visible).is_true()
		SafeArea.simulate([])
		(s.get_parent() as SubViewport).size = Vector2i(1280, 720)
		await _frames(4)
		assert_bool(layout.visible).override_failure_message(entry).is_false()
		for b: Node in p.find_children("*", "Button", true, false):
			assert_bool(layout.is_ancestor_of(b) and b.is_visible_in_tree()).is_false()
		_drop(s)
	var e: StationScreen = await _screen(Vector2i(1280, 720), "engineering", [])
	var ep: EngineeringPanel = e.focused_panel()
	assert_object(ep.cutaway.get_parent()).is_not_null()
	assert_bool(ep.cutaway.is_visible_in_tree()).is_true()
	assert_bool(ep.board.is_visible_in_tree()).is_true()
	_drop(e)


# FT: FT-COM-003, FT-STN-005
func test_comms_buttons_sit_in_the_left_rail() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "comms", LANDSCAPE)
	var p: CommsPanel = s.focused_panel()
	assert_int(p.touch_layout.left.box.get_child_count()).is_equal(5)
	for b: Button in p.touch_layout.left.box.get_children():
		assert_float(b.size.y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
	_drop(s)


# FT: FT-COM-004, FT-STN-005
# A trade offer's rows don't fit a phone on its side: they show a page at a time, touch-sized.
func test_comms_overlay_pages_its_rows_on_a_phone() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "comms", LANDSCAPE)
	var p: CommsPanel = s.focused_panel()
	p.open_card(CommsFixture.OFFER)
	await _frames(2)
	var o: CommsOverlay = p.overlay
	assert_bool(o.more_below()).is_true()
	var shown: Array[int] = []
	for i: int in o.rows().size():
		var r: Rect2 = o._rects[i]
		if r.size != Vector2.ZERO:
			shown.append(i)
			assert_float(r.size.y).is_greater_equal(CommsOverlay.PHONE_ROW_H)
			assert_float((o.get_global_transform() * r.end).y).is_less_equal(SafeArea.tap_bottom(o))
	assert_bool(shown.size() < o.rows().size()).is_true()
	assert_bool(o.page(true)).is_true()
	for i: int in 10:
		if o.more_below():
			o.page(true)
	assert_int(o.row_at(o._rects[o.rows().size() - 1].get_center())).is_equal(o.rows().size() - 1)
	_drop(s)


# FT: FT-CPT-001, FT-STN-005
func test_captain_view_buttons_sit_in_the_left_rail() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "captain", LANDSCAPE)
	var p: CaptainPanel = s.focused_panel()
	assert_bool(p.touch_layout.left.is_ancestor_of(p.buttons[2])).is_true()
	assert_bool(p.touch_layout.right.is_ancestor_of(p.cards)).is_true()
	p.buttons[2].pressed.emit()
	assert_array(StationFixture.sent(s.ctx).of("set_main_view")).is_equal([["set_main_view", [2]]])
	_drop(s)


# FT: FT-MSC-001, FT-STN-005
# A phone on its side shows the Viewer's radar as a square beside the view; upright under it.
func test_viewer_radar_goes_beside_the_view_on_its_side() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "viewer", LANDSCAPE)
	var p: ViewerPanel = s.focused_panel()
	assert_bool(p.radar_beside()).is_true()
	assert_float(p.radar.size.x).is_greater_equal(p.radar.size.y - 1.0)
	_drop(s)
	var up: StationScreen = await _screen(Vector2i(390, 844), "viewer", PORTRAIT)
	assert_bool((up.focused_panel() as ViewerPanel).radar_beside()).is_false()
	_drop(up)
