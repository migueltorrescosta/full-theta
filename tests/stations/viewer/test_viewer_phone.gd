extends GdUnitTestSuite
## The Viewer on a phone (#28 follow-up, design 2.8, D287): one page, no tabs, no touch
## controls but the top bar's menu (Leave, Sound, Full screen); the main screen fills the
## rest, under the top bar and above the bottom band, the radar beside the view on its side.
## It stays out of the phone frame: a viewer is read-only (FT-MSC-004), so no view-top row
## and no long-press ping.
# FT: FT-STN-005, FT-MSC-004

const SETTINGS: String = "user://test_viewer_phone.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(StationViews.VIEWER, SETTINGS)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	for i: int in 4:
		await get_tree().process_frame
	return s


func _drop(s: StationScreen) -> void:
	s.get_parent().remove_child(s)
	s.free()


# FT: FT-MSC-004, FT-STN-005
# Both ways up: one page and no tabs, the menu button is there (the Viewer's only control),
# the view starts under the top bar and ends above the band, the frame's view-top row and
# long-press stay off, and the touch rules hold.
func test_one_page_menu_only_both_ways_up() -> void:
	for f: Array in [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]:
		var s: StationScreen = await _screen(f[0], f[1])
		var what: String = str(f[0])
		var p: ViewerPanel = s.focused_panel()
		assert_bool(p.in_frame).override_failure_message(what).is_false()
		assert_object(p.pages).override_failure_message(what).is_null()
		assert_bool(s.frame.framed()).override_failure_message(what).is_false()
		assert_bool(s.frame.view_top.visible).override_failure_message(what).is_false()
		assert_int(s.top_bar.tabs.tab_count()).is_equal(0)
		assert_bool(s.frame.bottom_tabs.visible).override_failure_message(what).is_false()
		var menu: RailButton = s.top_bar.menu_button
		assert_bool(menu.is_visible_in_tree()).override_failure_message(what).is_true()
		var seen: Array[bool] = [false]
		s.menu_requested.connect(func() -> void: seen[0] = true)
		menu.pressed.emit()
		assert_bool(seen[0]).override_failure_message(what).is_true()
		# No tap target in the panel itself.
		assert_array(TapAudit.check(p)["targets"]).override_failure_message(what).is_empty()
		var view: Rect2 = p.get_global_rect()
		assert_float(view.position.y).is_greater_equal(s.top_bar.get_global_rect().end.y - 0.5)
		assert_float(view.end.y).is_less_equal(SafeArea.tap_bottom(s) + 0.5)
		var report: Dictionary = TapAudit.check(s)
		for k: String in AUDIT:
			(
				assert_array(report[k])
				. override_failure_message("%s %s: %s" % [what, k, report[k]])
				. is_empty()
			)
		_drop(s)


# FT: FT-MSC-004
# A long press on the Viewer's view sends nothing (the server would refuse a viewer's ping).
func test_long_press_sends_nothing() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = Vector2(300, 200)
	t.pressed = true
	StationFixture.clock(s.ctx).ms = StationFixture.NOW_MS
	s._input(t)
	StationFixture.clock(s.ctx).ms = StationFixture.NOW_MS + 900
	s._process(0.016)
	t = InputEventScreenTouch.new()
	t.position = Vector2(300, 200)
	s._input(t)
	assert_array(StationFixture.sent(s.ctx).sent).is_empty()
	_drop(s)
