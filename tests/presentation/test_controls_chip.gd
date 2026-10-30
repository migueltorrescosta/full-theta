extends GdUnitTestSuite
## The first-visit chip (P28-Help, FT-STN-012): help never opens by itself; a station's
## first visit shows "Controls: ☰ › Controls" for 6 s, once per client and station.
# FT: FT-STN-012

const CFG: String = "user://test_controls_chip.cfg"


func before() -> void:
	I18n.apply("en")


func _settings() -> ClientSettings:
	var s: ClientSettings = ClientSettings.new(CFG)
	s.reset_tooltips()
	return s


func test_shows_once_per_client_and_station() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var s: ClientSettings = _settings()
	var chip: ControlsChip = ControlsChip.show_once(parent, s, "helm")
	assert_object(chip).is_not_null()
	assert_object(chip.get_parent()).is_same(parent)
	assert_str(chip.text).is_equal(tr("controls.chip"))
	assert_float(chip.size.y).is_greater_equal(UiTheme.TOUCH_MIN)
	assert_object(ControlsChip.show_once(parent, s, "helm")).is_null()
	var saved: ClientSettings = ClientSettings.new(CFG)
	saved.load_file()
	assert_bool(saved.tooltip_seen("helm")).is_true()
	assert_object(ControlsChip.show_once(parent, s, "weapons")).is_not_null()
	# "Show first-run tips again" brings it back; the browser test hooks skip it.
	s.reset_tooltips()
	assert_object(ControlsChip.show_once(parent, s, "helm")).is_not_null()
	s.reset_tooltips()
	s.skip_first_visit_help = true
	assert_object(ControlsChip.show_once(parent, s, "helm")).is_null()


func test_goes_after_six_seconds_or_a_tap() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var chip: ControlsChip = ControlsChip.show_once(parent, _settings(), "helm")
	chip._process(5.9)
	assert_bool(chip.is_queued_for_deletion()).is_false()
	chip._process(0.2)
	assert_bool(chip.is_queued_for_deletion()).is_true()
	var tapped: ControlsChip = ControlsChip.show_once(parent, _settings(), "helm")
	var asked: Array[bool] = []
	tapped.pressed.connect(func() -> void: asked.append(true))
	tapped.pressed.emit()
	assert_array(asked).has_size(1)
	assert_bool(tapped.is_queued_for_deletion()).is_true()
