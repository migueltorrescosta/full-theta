extends GdUnitTestSuite
## UiTheme pieces the #28 visual check found wanting: check boxes that read on the panels and
## dialog frames that hold their title bar.
# FT: FT-STN-005


## WCAG contrast ratio of two colours.
static func _contrast(a: Color, b: Color) -> float:
	var la: float = a.get_luminance()
	var lb: float = b.get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_check_box_reads_at_three_to_one_on_its_backgrounds() -> void:
	var t: Theme = UiTheme.build(true)
	for variation: String in ["CheckBox", "TouchCheckBox"]:
		for state: String in ["unchecked", "checked"]:
			var img: Image = t.get_icon(state, variation).get_image()
			var edge: Color = img.get_pixel(0, img.get_height() / 2)
			for bg: String in ["panel", "background", "panel_focus"]:
				(
					assert_float(_contrast(edge, Palette.color(bg)))
					. override_failure_message("%s %s on %s" % [variation, state, bg])
					. is_greater_equal(3.0)
				)
	# Checked and unchecked differ inside the box.
	var on: Image = t.get_icon("checked", "CheckBox").get_image()
	var off: Image = t.get_icon("unchecked", "CheckBox").get_image()
	var mid: int = UiTheme.CHECK_ICON / 2
	assert_bool(on.get_pixel(4, 4).is_equal_approx(off.get_pixel(4, 4))).is_false()
	assert_float(off.get_pixel(mid, mid).a).is_equal(0.0)


# The frame of an embedded dialog reaches over its title bar (the mode dialog drew its title
# and × on a transparent strip over the lobby).
func test_dialog_frame_covers_the_title_bar() -> void:
	var t: Theme = UiTheme.build()
	var title: int = t.get_constant("title_height", "Window")
	for name: String in ["embedded_border", "embedded_unfocused_border"]:
		var frame: StyleBox = t.get_stylebox(name, "Window")
		assert_float((frame as StyleBoxFlat).expand_margin_top).is_greater_equal(title)
		assert_float((frame as StyleBoxFlat).expand_margin_left).is_greater(0.0)


# FT: FT-STN-006
# W2: the resting border of a control reads at 3:1 on the surface around it (WCAG 1.4.11).
func test_control_borders_read_at_three_to_one() -> void:
	var t: Theme = UiTheme.build(false)
	for type: String in ["Button", "OptionButton", "LineEdit"]:
		var box: StyleBoxFlat = t.get_stylebox("normal", type) as StyleBoxFlat
		for bg: String in ["panel", "background"]:
			(
				assert_float(_contrast(box.border_color, Palette.color(bg)))
				. override_failure_message("%s border on %s" % [type, bg])
				. is_greater_equal(3.0)
			)
	for tag: String in UiTheme.LOAD_VARIANTS:
		var cell: StyleBoxFlat = t.get_stylebox("normal", "LoadCell_" + tag) as StyleBoxFlat
		assert_float(_contrast(cell.border_color, Palette.color("panel"))).is_greater_equal(3.0)


# R05-8: an overlay box keeps the panel's colour at a lower alpha, and a row box may widen its
# left margin alone (the others keep Godot's default, -1).
func test_box_alpha_and_left_margin() -> void:
	var plain: StyleBoxFlat = UiTheme.box("panel", "line_strong", 6, 4)
	assert_that(plain.bg_color).is_equal(Palette.color("panel"))
	assert_float(plain.content_margin_left).is_equal(6.0)
	assert_float(plain.content_margin_top).is_equal(4.0)
	var overlay: StyleBoxFlat = UiTheme.box("panel", "accent", -1, -1, UiTheme.OVERLAY_ALPHA, 8)
	assert_that(overlay.bg_color).is_equal(Color(Palette.color("panel"), UiTheme.OVERLAY_ALPHA))
	assert_that(overlay.border_color).is_equal(Palette.color("accent"))
	assert_int(overlay.corner_radius_top_left).is_equal(UiTheme.RADIUS)
	assert_float(overlay.content_margin_left).is_equal(8.0)
	for m: float in [
		overlay.content_margin_right, overlay.content_margin_top, overlay.content_margin_bottom
	]:
		assert_float(m).is_equal(-1.0)
	var rail: StyleBoxFlat = UiTheme.build().get_stylebox("panel", "OverlayRail") as StyleBoxFlat
	assert_float(rail.bg_color.a).is_equal_approx(UiTheme.OVERLAY_ALPHA, 0.001)
