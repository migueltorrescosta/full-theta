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
	assert_str(bar._pips.text).is_equal("RX 6")
	assert_str(bar._timer.text).is_equal("02:05")
	bar.show_state("Kestrel", {}, 0, [], 0.0)
	assert_str(bar._hull.text).is_equal("Hull -")


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
