extends GdUnitTestSuite
## Safe areas and the phone forms (#28, extends D223, amends D218): the form follows the
## orientation; a phone keeps 8 px on each side and the 24 px gesture band clear of taps;
## a station screen at 844 x 390 with an iPhone's insets puts no control under an inset
## or in the band, and upright shows the "turn sideways" banner.
# FT: FT-STN-005

const SETTINGS: String = "user://test_safe_area.cfg"
## The mockups' iPhone in landscape and upright: [left, top, right, bottom].
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func test_form_follows_size_pointer_and_orientation() -> void:
	var f: Callable = LayoutMode.form_for
	assert_int(f.call(Vector2(1920, 1080), false)).is_equal(LayoutMode.Form.DESKTOP)
	assert_int(f.call(Vector2(1024, 768), true)).is_equal(LayoutMode.Form.TABLET)
	assert_int(f.call(Vector2(768, 1024), true)).is_equal(LayoutMode.Form.TABLET)
	assert_int(f.call(Vector2(844, 390), true)).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	assert_int(f.call(Vector2(390, 844), true)).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	# A dpr-3 phone's window, measured in device-independent px (D223).
	var dp: Vector2 = LayoutMode.dp_size(Vector2(2532, 1170), 1.0, 3.0)
	assert_int(f.call(dp, true)).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	assert_bool(LayoutMode.is_phone(LayoutMode.Form.PHONE_PORTRAIT)).is_true()
	assert_bool(LayoutMode.is_phone(LayoutMode.Form.TABLET)).is_false()


func test_margins_floor_on_phones_only() -> void:
	var phone: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE
	var raw: Vector4 = Vector4(47, 0, 47, 21)
	assert_vector(SafeArea._margins(raw, phone, 1.0, 1.0)).is_equal(Vector4(47, 8, 47, 21))
	# UI scale 150 %: viewport px are window px over 1.5; density 2: the floor is 16 window px.
	assert_vector(SafeArea._margins(Vector4.ZERO, phone, 2.0, 1.5)).is_equal_approx(
		Vector4.ONE * 16.0 / 1.5, Vector4.ONE * 0.01
	)
	var desk: LayoutMode.Form = LayoutMode.Form.DESKTOP
	assert_vector(SafeArea._margins(Vector4.ZERO, desk, 1.0, 1.0)).is_equal(Vector4.ZERO)
	assert_float(SafeArea._band(21.0, phone, 1.0, 1.0)).is_equal(SafeArea.GESTURE_BAND)
	assert_float(SafeArea._band(34.0, phone, 1.0, 1.0)).is_equal(34.0)
	assert_float(SafeArea._band(0.0, LayoutMode.Form.TABLET, 1.0, 1.0)).is_equal(0.0)


func _screen(size: Vector2i, seat: String, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(seat, SETTINGS)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	for i: int in 3:
		await get_tree().process_frame
	return s


func test_phone_landscape_screen_keeps_taps_in_the_safe_area() -> void:
	for seat: String in ["engineering", "relay", "comms", "captain"]:
		var s: StationScreen = await _screen(Vector2i(844, 390), seat, LANDSCAPE)
		assert_int(s.form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
		var report: Dictionary = TapAudit.check(s)
		assert_array(report["targets"]).is_not_empty()
		(
			assert_array(report["outside_safe"])
			. override_failure_message("%s: %s under an inset" % [seat, report["outside_safe"]])
			. is_empty()
		)
		(
			assert_array(report["in_band"])
			. override_failure_message("%s: %s in the gesture band" % [seat, report["in_band"]])
			. is_empty()
		)
		assert_float(s.top_bar.custom_minimum_size.y).is_equal(StationScreen.PHONE_BAR_HEIGHT)
		assert_bool(s.rotate_banner.visible).is_false()
		s.get_parent().remove_child(s)
		s.free()


func test_phone_portrait_shows_the_dismissible_banner() -> void:
	var s: StationScreen = await _screen(Vector2i(390, 844), "helm", PORTRAIT)
	assert_int(s.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	assert_bool(s.rotate_banner.visible).is_true()
	assert_str(s.rotate_banner.label.text).is_equal(tr(HelmTouch.ROTATE_KEY))
	var report: Dictionary = TapAudit.check(s)
	assert_array(report["outside_safe"]).is_empty()
	assert_array(report["in_band"]).is_empty()
	# The banner's close button is a primary target.
	var close: Rect2 = s.rotate_banner.close_button.get_global_rect()
	assert_float(minf(close.size.x, close.size.y)).is_greater_equal(UiTheme.TOUCH_PRIMARY)
	s.rotate_banner.dismiss()
	assert_bool(s.rotate_banner.visible).is_false()
	assert_bool(s.ctx.settings.hint_seen(RotateBanner.KEY)).is_true()
	# A later banner with these settings remembers it.
	RotateBanner.dismissed_here = false
	var again: RotateBanner = RotateBanner.new()
	again.settings = s.ctx.settings
	s.add_child(again)
	assert_bool(again.visible).is_false()


func test_desktop_screen_is_unchanged() -> void:
	var s: StationScreen = await _screen(Vector2i(1280, 720), "engineering", [])
	assert_int(s.form).is_equal(LayoutMode.Form.DESKTOP)
	assert_float(s._rows.offset_left).is_equal(0.0)
	# (only the edge gap at the bottom, #12)
	assert_float(s._rows.offset_bottom).is_equal(-StationScreen.EDGE_GAP)
	assert_bool(s.rotate_banner.visible).is_false()


# FT: FT-STN-005
# #12: toasts stack beside a side radar, off its labels; the last row keeps an edge gap.
func test_toasts_stay_out_of_the_radar_rectangle() -> void:
	var s: StationScreen = await _screen(Vector2i(1280, 720), "comms", [])
	s.toasts.push("Hit, 6 level", "warn", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(s.radar.get_global_rect().intersects(s.toasts.get_global_rect())).is_false()
	assert_float(s._rows.get_global_rect().end.y).is_less_equal(720.0 - StationScreen.EDGE_GAP)


# FT: FT-ENG-002
# #12 (D316): at 150 % UI scale (853 x 480) the power board fits the panel without a scroll.
func test_engineering_board_fits_at_150_percent() -> void:
	var s: StationScreen = await _screen(Vector2i(853, 480), "engineering", [])
	var panel: EngineeringPanel = s.focused_panel() as EngineeringPanel
	await get_tree().process_frame
	assert_float(panel.board.content_height()).is_less_equal(panel.size.y)
