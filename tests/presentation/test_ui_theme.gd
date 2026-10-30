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
