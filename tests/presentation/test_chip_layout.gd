extends GdUnitTestSuite
## ChipLayout (R13-9, G3): the box tests the disc radar, the Relay map and the Helm HUD
## share for placing chips and labels.


func test_gap_is_the_distance_to_the_nearest_point_of_the_box() -> void:
	var box: Rect2 = Rect2(10, 10, 20, 10)
	assert_float(ChipLayout.gap_to(box, Vector2(15, 15))).is_equal(0.0)
	assert_float(ChipLayout.gap_to(box, Vector2(0, 15))).is_equal(10.0)
	assert_float(ChipLayout.gap_to(box, Vector2(33, 24))).is_equal_approx(5.0, 1e-6)


func test_hits_is_any_overlap() -> void:
	var others: Array[Rect2] = [Rect2(0, 0, 5, 5), Rect2(20, 20, 5, 5)]
	assert_bool(ChipLayout.hits(Rect2(4, 4, 3, 3), others)).is_true()
	assert_bool(ChipLayout.hits(Rect2(10, 10, 3, 3), others)).is_false()
	assert_bool(ChipLayout.hits(Rect2(10, 10, 3, 3), [] as Array[Rect2])).is_false()


func test_a_leader_is_blocked_by_a_box_it_crosses_but_not_by_the_box_holding_its_start() -> void:
	var label: Rect2 = Rect2(100, 0, 40, 10)
	var p: Vector2 = Vector2(0, 5)
	var wall: Array[Rect2] = [Rect2(40, -20, 10, 60)]
	assert_bool(ChipLayout.leader_clear(p, label, wall)).is_false()
	var holds_p: Array[Rect2] = [Rect2(-5, 0, 20, 10)]
	assert_bool(ChipLayout.leader_clear(p, label, holds_p)).is_true()
	assert_bool(ChipLayout.leader_clear(p, label, [] as Array[Rect2])).is_true()


func test_chip_forms_shorten_one_part_at_a_time() -> void:
	var font: Font = ThemeDB.fallback_font
	var forms: Array = ChipLayout.chip_forms(font, "H2 · 4 high · mid")
	assert_array(forms[0]).is_equal(["H2 · 4 high · mid", "H2 · 4 high", "H2"])
	assert_int((forms[1] as Array).size()).is_equal(3)
	assert_float((forms[1][0] as Vector2).x).is_greater((forms[1][2] as Vector2).x)


func test_item_glyph_compares_items_by_kind_and_id() -> void:
	var a: Dictionary = {"kind": "contact", "id": 4, "label": "H1"}
	assert_dict(ItemGlyph.ref(a)).is_equal({"kind": "contact", "id": 4})
	assert_bool(ItemGlyph.is_selected({"kind": "contact", "id": 4}, a)).is_true()
	assert_bool(ItemGlyph.is_selected({"kind": "mark", "id": 4}, a)).is_false()
	assert_bool(ItemGlyph.is_selected({}, a)).is_false()


func test_text_size_is_the_font_width_and_line_height_and_is_remembered() -> void:
	var font: Font = ThemeDB.fallback_font
	var want: Vector2 = Vector2(
		font.get_string_size("H2 · 4 high", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x,
		font.get_height(13)
	)
	assert_vector(ChipLayout.text_size(font, "H2 · 4 high", 13)).is_equal(want)
	assert_vector(ChipLayout.text_size(font, "H2 · 4 high", 13)).is_equal(want)
	# Another size is another entry.
	assert_float(ChipLayout.text_size(font, "H2 · 4 high", 26).x).is_greater(want.x)


# The same crowd laid out twice gives the same places (the free-spot lists are found once
# per form, not per step).
func test_declutter_is_repeatable_on_a_crowd() -> void:
	var font: Font = ThemeDB.fallback_font
	var runs: Array = []
	for _r: int in 2:
		var entries: Array[Dictionary] = []
		for i: int in 14:
			var pos: Vector2 = Vector2(120.0 + float(i % 5) * 9.0, 100.0 + float(i / 5) * 7.0)
			var chip: String = "H%d · %d high · mid" % [i, i % 12]
			var forms: Array = ChipLayout.chip_forms(font, chip)
			var sizes: Array[Vector2] = []
			sizes.assign(forms[1])
			var variants: Array[String] = []
			variants.assign(forms[0])
			(
				entries
				. append(
					{
						"pos": pos,
						"foot": pos + Vector2(0, 20),
						"chip": chip,
						"chip_rect": Rect2(pos + Vector2(10, -7), sizes[0]),
						"variants": variants,
						"sizes": sizes,
						"selected": i == 3,
					}
				)
			)
		ChipLayout.declutter(entries, [], Rect2(0, 0, 300, 240), Rect2(40, 30, 220, 160), 9.0)
		runs.append(
			entries.map(func(e: Dictionary) -> String: return "%s %s" % [e["chip"], e["chip_rect"]])
		)
	assert_array(runs[0]).is_equal(runs[1])
