extends GdUnitTestSuite
## Phone frame polish (#28 follow-up, design 1.3 and 1.4): a ring under the finger shows when
## a long-press arms and grows, follows a mark drag and goes on release; a swipe down on a
## choice sheet cancels it, a short move or a sideways one doesn't.
# FT: FT-STN-005

const SETTINGS: String = "user://test_frame_polish.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen() -> StationScreen:
	SafeArea.simulate(LANDSCAPE)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(844, 390)
	add_child(vp)
	var s: StationScreen = StationScreen.new()
	s.setup(StationFixture.context("engineering", SETTINGS))
	vp.add_child(s)
	for i: int in 4:
		await get_tree().process_frame
	return s


func _touch(s: StationScreen, at: Vector2, down: bool, ms: int) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = at
	t.pressed = down
	StationFixture.clock(s.ctx).ms = ms
	s._input(t)


func _drag(s: StationScreen, at: Vector2) -> void:
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.position = at
	s._input(d)


# FT: FT-STN-005, FT-SPA-016
func test_armed_long_press_shows_a_growing_ring() -> void:
	var s: StationScreen = await _screen()
	var ring: PhoneFrame.ArmedRing = s.frame.armed_ring
	# Over the view, clear of the board's buttons and the view-top row.
	var at: Vector2 = s.frame.view_top.get_global_rect().get_center() + Vector2(0, 60)
	var t0: int = StationFixture.NOW_MS
	_touch(s, at, true, t0)
	s.frame.process(t0 + 100)
	assert_bool(ring.visible).is_false()
	StationFixture.clock(s.ctx).ms = t0 + LongPress.HOLD_MS
	s.frame.process(t0 + LongPress.HOLD_MS)
	assert_bool(ring.visible).is_true()
	var centre: Vector2 = ring.get_global_rect().get_center()
	assert_float(centre.distance_to(at)).is_less(1.0)
	var r0: float = ring.radius()
	s.frame.process(t0 + LongPress.HOLD_MS + PhoneFrame.ArmedRing.GROW_MS)
	assert_float(ring.radius()).is_greater(r0)
	assert_float(ring.radius()).is_equal(PhoneFrame.ArmedRing.END_R)
	_drag(s, at + Vector2(50, 0))
	assert_float(ring.get_global_rect().get_center().distance_to(at + Vector2(50, 0))).is_less(1.0)
	_touch(s, at + Vector2(50, 0), false, t0 + 1200)
	assert_bool(ring.visible).is_false()
	s.get_parent().remove_child(s)
	s.free()


# FT: FT-STN-005
func test_swipe_down_cancels_a_sheet() -> void:
	var s: StationScreen = await _screen()
	var cancelled: Array[bool] = []
	s.sheet.cancelled.connect(func() -> void: cancelled.append(true))
	s.frame.open_alert_sheet()
	await get_tree().process_frame
	var from: Vector2 = s.sheet.box.get_global_rect().get_center()
	for move: Vector2 in [Vector2(0, 30), Vector2(90, 70)]:
		_sheet_swipe(s.sheet, from, from + move)
		assert_bool(s.sheet.is_open()).override_failure_message(str(move)).is_true()
	_sheet_swipe(s.sheet, from, from + Vector2(10, ChoiceSheet.SWIPE_DOWN + 4))
	assert_bool(s.sheet.is_open()).is_false()
	assert_array(cancelled).is_equal([true])
	# A swipe that starts off the sheet does nothing.
	s.frame.open_alert_sheet()
	_sheet_swipe(s.sheet, Vector2(100, 200), Vector2(100, 300))
	assert_bool(s.sheet.is_open()).is_true()
	s.get_parent().remove_child(s)
	s.free()


func _sheet_swipe(sheet: ChoiceSheet, from: Vector2, to: Vector2) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = from
	t.pressed = true
	sheet._input(t)
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.position = to
	sheet._input(d)
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.position = to
	up.pressed = false
	sheet._input(up)
