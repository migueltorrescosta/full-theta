extends GdUnitTestSuite
## Layout choice (FT-STN-005, D194, D195, D216): the viewport size and the pointer pick
## desktop, touch or phone at runtime; touch buttons are tap-sized; a station screen
## stacks its radar column below the main area in portrait and shrinks it on a phone.

const SETTINGS: String = "user://test_layout_mode.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	LayoutMode.forced = -1
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


# FT: FT-STN-005
func test_kind_follows_size_and_pointer() -> void:
	assert_int(LayoutMode.kind_for(Vector2(1920, 1080), false)).is_equal(LayoutMode.Kind.DESKTOP)
	assert_int(LayoutMode.kind_for(Vector2(1024, 768), true)).is_equal(LayoutMode.Kind.TOUCH)
	assert_int(LayoutMode.kind_for(Vector2(768, 1024), true)).is_equal(LayoutMode.Kind.TOUCH)
	assert_int(LayoutMode.kind_for(Vector2(390, 844), true)).is_equal(LayoutMode.Kind.PHONE)
	assert_int(LayoutMode.kind_for(Vector2(844, 390), true)).is_equal(LayoutMode.Kind.PHONE)
	assert_bool(LayoutMode.portrait(Vector2(768, 1024))).is_true()
	assert_bool(LayoutMode.portrait(Vector2(1024, 768))).is_false()


# FT: FT-STN-005
# D223: the UI scale never changes the layout. A 1280 x 720 desktop at 150 % shows an
# 853 x 480 viewport; a 390 x 844 CSS-px phone at dpr 3 is a 1170 x 2532 px window.
func test_kind_is_independent_of_ui_scale_and_density() -> void:
	var desktop: Vector2 = LayoutMode.dp_size(Vector2(1280, 720) / 1.5, 1.5, 1.0)
	assert_vector(desktop).is_equal_approx(Vector2(1280, 720), Vector2(0.01, 0.01))
	assert_int(LayoutMode.kind_for(desktop, false)).is_equal(LayoutMode.Kind.DESKTOP)
	var phone: Vector2 = LayoutMode.dp_size(Vector2(1170, 2532), 1.0, 3.0)
	assert_vector(phone).is_equal_approx(Vector2(390, 844), Vector2(0.01, 0.01))
	assert_int(LayoutMode.kind_for(phone, true)).is_equal(LayoutMode.Kind.PHONE)
	var scaled_phone: Vector2 = LayoutMode.dp_size(Vector2(1170, 2532) / 1.25, 1.25, 3.0)
	assert_int(LayoutMode.kind_for(scaled_phone, true)).is_equal(LayoutMode.Kind.PHONE)


# FT: FT-STN-005
func test_touch_theme_makes_every_button_tap_sized() -> void:
	var heights: Dictionary = {}
	for kind: LayoutMode.Kind in LayoutMode.Kind.values():
		var holder: Control = auto_free(Control.new())
		holder.theme = LayoutMode.theme_for(kind)
		add_child(holder)
		var b: Button = Button.new()
		b.text = "Ag"
		holder.add_child(b)
		heights[kind] = b.get_combined_minimum_size().y
	assert_float(heights[LayoutMode.Kind.TOUCH]).is_greater_equal(float(UiTheme.TOUCH_MIN))
	assert_float(heights[LayoutMode.Kind.PHONE]).is_greater_equal(float(UiTheme.TOUCH_MIN))
	assert_float(heights[LayoutMode.Kind.DESKTOP]).is_less(float(UiTheme.TOUCH_MIN))


func _screen(size: Vector2i, entry: String) -> StationScreen:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


# FT: FT-STN-005
# A phone upright: the radar column sits below the main area, with a smaller disc and a
# two-row top bar; a desktop window keeps the column on the right.
func test_screen_arranges_for_orientation_and_phone() -> void:
	var phone: StationScreen = await _screen(Vector2i(390, 844), "engineering")
	assert_bool(phone._body.vertical).is_true()
	assert_float(phone.radar.custom_minimum_size.x).is_equal(StationScreen.PHONE_RADAR)
	assert_float(phone.top_bar.custom_minimum_size.y).is_greater(StationScreen.TOP_BAR_HEIGHT)
	var wide: StationScreen = await _screen(Vector2i(1280, 720), "engineering")
	assert_bool(wide._body.vertical).is_false()
	assert_float(wide.radar.custom_minimum_size.x).is_equal(StationScreen.SIDE_WIDTH)
	assert_float(wide.top_bar.custom_minimum_size.y).is_equal(StationScreen.TOP_BAR_HEIGHT)
