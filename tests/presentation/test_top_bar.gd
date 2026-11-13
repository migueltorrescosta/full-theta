extends GdUnitTestSuite
## TopBar (FT-STN-001): fields, the alert chip's letter and shape, the crew-only picker.

var bar: TopBar
var picked: Array[int] = []


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	picked.clear()
	bar = auto_free(TopBar.new())
	bar.size = Vector2(1280, TopBar.HEIGHT)
	bar.alert_picked.connect(func(level: int) -> void: picked.append(level))
	add_child(bar)


# FT: FT-STN-001
func test_shows_every_field() -> void:
	var status: Dictionary = {"hull": 812.6, "shields": 299.4, "pips_used": 6}
	bar.show_state("Kestrel", status, 0, [], 125.0)
	assert_str(bar._name.text).is_equal("Kestrel")
	assert_str(bar._hull.text).is_equal("Hull 813")
	assert_str(bar._shields.text).is_equal("Shields 299")
	assert_str(bar._pips.text).is_equal("Power 6")
	assert_str(bar._timer.text).is_equal("02:05")
	bar.show_state("Kestrel", {}, 0, [], 0.0)
	assert_str(bar._hull.text).is_equal("Hull -")


# FT: FT-STN-001
# Hull and shields are joules (a corvette's hull is 10^8): the bar shows a percentage of
# the ship's maximum, or a short SI form without one, never "Hull 100000000".
func test_hull_and_shields_are_not_raw_joules() -> void:
	var status: Dictionary = {"hull": 92_000_000.0, "shields": 21_000_000.0, "pips_used": 6}
	bar.show_state(
		"Kestrel", status, 0, [], 0.0, "", {"hull": 100_000_000.0, "shields": 30_000_000.0}
	)
	assert_str(bar._hull.text).is_equal("Hull 92%")
	assert_str(bar._shields.text).is_equal("Shields 70%")
	bar.show_state("Kestrel", {"hull": 100_000_000.0, "shields": 30_000_000.0}, 0, [], 1.0)
	assert_str(bar._hull.text).is_equal("Hull 100M")
	assert_str(bar._shields.text).is_equal("Shields 30M")
	bar.show_state("Kestrel", {"hull": 25_400.0, "shields": 9_999.0}, 0, [], 2.0)
	assert_str(bar._hull.text).is_equal("Hull 25k")
	assert_str(bar._shields.text).is_equal("Shields 9999")


# FT: FT-STN-006
func test_alert_levels_have_their_own_letter_and_shape() -> void:
	var letters: Dictionary = {}
	var shapes: Dictionary = {}
	for level: int in 3:
		bar.show_state("Kestrel", {}, level, [], 0.0)
		letters[bar.alert_style["letter"]] = true
		shapes[bar.alert_style["shape"]] = true
		assert_str(bar.chip.text.strip_edges()).is_equal(tr(Palette.ALERTS[level]["key"]))
	assert_int(letters.size()).is_equal(3)
	assert_int(shapes.size()).is_equal(3)
	assert_str(bar.alert_style["letter"]).is_equal("R")


# FT: FT-STN-008
func test_crew_picks_the_alert_from_the_chip() -> void:
	bar.can_set_alert = true
	bar.chip.pressed.emit()
	assert_bool(bar.picker.visible).is_true()
	var buttons: Array[Node] = bar.picker.get_child(0).get_children()
	assert_int(buttons.size()).is_equal(3)
	(buttons[2] as Button).pressed.emit()
	assert_array(picked).is_equal([2])
	assert_bool(bar.picker.visible).is_false()


# FT: FT-STN-008
func test_captain_and_viewers_see_it_read_only() -> void:
	bar.can_set_alert = false
	bar.chip.pressed.emit()
	bar.open_alert_picker()
	assert_bool(bar.picker.visible).is_false()
	assert_array(picked).is_empty()
	assert_str(bar.chip.tooltip_text).is_equal(tr("alert.readonly"))


# FT: FT-STN-001
# An unchanged frame touches nothing; a change in what is shown (the rounded hull, the
# second) redraws.
func test_unchanged_state_is_skipped() -> void:
	var status: Dictionary = {"hull": 812.6, "shields": 299.4, "pips_used": 6}
	bar.show_state("Kestrel", status, 0, ["helm"], 125.0)
	bar._name.text = "untouched"
	bar.show_state("Kestrel", {"hull": 812.9, "shields": 299.4, "pips_used": 6}, 0, ["helm"], 125.4)
	assert_str(bar._name.text).is_equal("untouched")
	bar.show_state("Kestrel", status, 0, ["helm"], 126.0)
	assert_str(bar._name.text).is_equal("Kestrel")
	assert_str(bar._timer.text).is_equal("02:06")


# FT: FT-STN-001
# R23-10 (C9): a cell the station cannot see (a summary of "—") is left out of the bar, not
# shown as a dash that reads as zero.
func test_cells_the_station_cannot_see_are_hidden() -> void:
	var absent: Dictionary = {"text": tr("topbar.absent"), "band": -1}
	bar.show_state(
		"Kestrel", {"hull": 1.0}, 0, [], 0.0, "", {}, {"shields": absent, "pips_used": absent}
	)
	assert_bool(bar._shields.visible).is_false()
	assert_bool(bar._pips.visible).is_false()
	assert_bool(bar._hull.visible).is_true()
	bar.show_state("Kestrel", {"hull": 1.0, "shields": 2.0, "pips_used": 3}, 0, [], 1.0)
	assert_bool(bar._shields.visible).is_true()
	assert_bool(bar._pips.visible).is_true()


# FT: FT-STN-001
# w5: the phone timer's goal line ("2 foes") is never cut, beside the full-screen icon too.
func test_phone_goal_line_fits_its_cell() -> void:
	bar.apply(LayoutMode.Form.PHONE_LANDSCAPE, false)
	bar.fullscreen.visible = true
	for lang: String in I18n.LANGUAGES:
		I18n.apply(lang)
		var short: String = tr("goal.short_hostiles") % 2
		bar.show_goal(tr("goal.hostiles") % 2, short)
		bar.show_state("Kestrel", {"hull": 1.0}, 0, [], float(I18n.LANGUAGES.find(lang)))
		var timer: Label = bar._phone_timer
		var fs: int = timer.get_theme_font_size("font_size")
		var need: float = (
			timer.get_theme_font("font").get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		)
		assert_float(timer.custom_minimum_size.x).override_failure_message(lang).is_greater_equal(
			need
		)
	I18n.apply("en")


# FT: FT-STN-001
# R13-15: one apply() per layout; a phone turned back into a desktop bar gets its desktop
# fonts and the station names again (the old setters skipped that when called in order).
func test_apply_undoes_the_phone_bar() -> void:
	bar.apply(LayoutMode.Form.PHONE_LANDSCAPE, false, 48.0)
	assert_bool(bar.phone).is_true()
	assert_bool(bar._name.has_theme_font_size_override("font_size")).is_true()
	bar.apply(LayoutMode.Form.DESKTOP, true)
	assert_bool(bar.phone).is_false()
	assert_bool(bar._name.has_theme_font_size_override("font_size")).is_false()
	assert_bool(bar._stations.visible).is_true()
	assert_object(bar._hull.get_parent()).is_same(bar._row2)
	bar.apply(LayoutMode.Form.DESKTOP, false)
	assert_object(bar._hull.get_parent()).is_same(bar._row)


# FT: FT-MIS-030
# R24-18: after a handover the bar names the ship the player watches: in place of the ship
# name on a desktop, under the timer on a phone (whose bar has no name).
func test_names_the_watched_ship() -> void:
	bar.watching = "Heron"
	bar.show_state("Heron", {"hull": 1.0}, 0, [], 0.0)
	assert_str(bar._name.text).is_equal("Watching Heron")
	bar.apply(LayoutMode.Form.PHONE_PORTRAIT, false, 48.0)
	bar.show_goal("Goal: stop the hostiles (2 left)", "2 foes")
	bar.show_state("Heron", {"hull": 1.0}, 0, [], 0.0)
	assert_str(bar._phone_timer.text).is_equal("00:00\nHeron")
	bar.watching = ""
	bar.show_state("Kestrel", {"hull": 1.0}, 0, [], 0.0)
	assert_str(bar._name.text).is_equal("Kestrel")
	assert_str(bar._phone_timer.text).is_equal("00:00\n2 foes")


# FT: FT-STN-004
# w-nk5 (D414): a toast's box keeps clear of the ship's name, hull, shields, power and the
# chip in every desktop and tablet bar; where the free stretch after the station names is
# too narrow it covers the names rather than fall back over the read-outs.
func test_notice_box_never_covers_the_read_outs() -> void:
	var status: Dictionary = {"hull": 0.92, "shields": 0.7, "pips_used": 6}
	for case: Array in [[1920.0, false], [900.0, false], [700.0, true]]:
		bar.size.x = case[0]
		bar.apply(LayoutMode.Form.DESKTOP, case[1])
		bar.show_state("Kestrel", status, 0, ["relay", "comms"], 50.0, "relay")
		await await_idle_frame()
		var box: Rect2 = bar.notice_rect()
		for c: Control in [bar._name, bar._hull, bar._shields, bar._pips, bar.chip, bar._timer]:
			(
				assert_bool(box.intersects(c.get_global_rect()))
				. override_failure_message("%s covers %s at %d" % [box, c, case[0]])
				. is_false()
			)
		assert_float(box.size.x).is_greater(100.0)
		# Only the narrowest one-row bar (900 px) has too little room after the station names
		# and covers them; the others leave them in view.
		var names: float = bar._stations.get_global_rect().position.x
		assert_bool(is_equal_approx(box.position.x, names)).is_equal(case[0] == 900.0)
