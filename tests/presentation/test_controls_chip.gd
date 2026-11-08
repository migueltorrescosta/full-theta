extends GdUnitTestSuite
## The first-visit chip (P28-Help, FT-STN-012): help never opens by itself; a station's
## first visit shows "Controls: ☰ › Controls" for 6 s, once per client and station.
# FT: FT-STN-012

const CFG: String = "user://test_controls_chip.cfg"


func before() -> void:
	I18n.apply("en")


func _settings() -> ClientSettings:
	var s: ClientSettings = ClientSettings.new(CFG)
	s.reset_hints()
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
	assert_bool(saved.hint_seen("helm")).is_true()
	assert_object(ControlsChip.show_once(parent, s, "weapons")).is_not_null()
	# "Show first-run tips again" brings it back; the browser test hooks skip it.
	s.reset_hints()
	assert_object(ControlsChip.show_once(parent, s, "helm")).is_not_null()
	s.reset_hints()
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


# FT: FT-STN-012
# D4: the chip names the way in on the player's device: the key, the pad button or the menu.
func test_the_chip_names_the_overlay_binding_of_the_device() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var kbm: ControlsChip = ControlsChip.show_once(parent, _settings(), "helm", IntentTable.KBM)
	assert_str(kbm.text).is_equal("Controls: press ?")
	var pad: ControlsChip = ControlsChip.show_once(parent, _settings(), "helm", IntentTable.PAD)
	assert_str(pad.text).is_equal("Controls: press View")
	var touch: ControlsChip = ControlsChip.show_once(
		parent, _settings(), "helm", IntentTable.KBM, true
	)
	assert_str(touch.text).is_equal(tr("controls.chip"))
	# A rebound key shows at once.
	var s: ClientSettings = _settings()
	s.bindings.rebind("overlay", IntentTable.KBM, PackedStringArray(["F9"]))
	assert_str(ControlsChip.show_once(parent, s, "helm", IntentTable.KBM).text).is_equal(
		"Controls: press F9"
	)


# FT: FT-STN-012
# D4: the overlay intent opens the page and takes the chip with it.
func test_the_overlay_intent_dismisses_the_chip() -> void:
	var ctx: StationContext = StationFixture.context("helm", CFG)
	ctx.settings.reset_hints()
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	add_child(screen)
	var asked: Array[bool] = []
	screen.help_requested.connect(func() -> void: asked.append(true))
	var chip: Node = screen.find_child("ControlsChip", true, false)
	assert_object(chip).is_not_null()
	screen.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	assert_array(asked).has_size(1)
	assert_bool(chip.is_queued_for_deletion()).is_true()


# FT: FT-STN-012
# D2: the contact label legend shows once per client, below the Controls chip, and opens
# the callout card.
func test_the_legend_chip_shows_once_per_client() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var s: ClientSettings = _settings()
	var legend: ControlsLegendChip = ControlsLegendChip.show_legend(parent, s)
	assert_object(legend).is_not_null()
	assert_str(legend.text).contains("H2 · 4 high · mid")
	assert_object(ControlsLegendChip.show_legend(parent, s)).is_null()
	legend._process(ControlsLegendChip.SHOW_S + 0.1)
	assert_bool(legend.is_queued_for_deletion()).is_true()
	s.reset_hints()
	assert_object(ControlsLegendChip.show_legend(parent, s)).is_not_null()
	# The screen shows both on the first visit.
	var ctx: StationContext = StationFixture.context("helm", CFG)
	ctx.settings.reset_hints()
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	add_child(screen)
	assert_object(screen.find_child("ControlsLegendChip", true, false)).is_not_null()
