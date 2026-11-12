extends GdUnitTestSuite
## The first-visit hint (P28-Help, FT-STN-012): help never opens by itself; a station's
## first visit shows "Controls: ☰ › Controls" for 6 s, once per client and station.
# FT: FT-STN-012

const CFG: String = "user://test_controls_hint.cfg"


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
	var hint: ControlsHint = ControlsHint.show_once(parent, s, "helm")
	assert_object(hint).is_not_null()
	assert_object(hint.get_parent()).is_same(parent)
	assert_str(hint.text).is_equal(tr("controls.hint"))
	assert_float(hint.size.y).is_greater_equal(UiTheme.TOUCH_MIN)
	assert_object(ControlsHint.show_once(parent, s, "helm")).is_null()
	var saved: ClientSettings = ClientSettings.new(CFG)
	saved.load_file()
	assert_bool(saved.hint_seen("helm")).is_true()
	assert_object(ControlsHint.show_once(parent, s, "weapons")).is_not_null()
	# "Show first-run tips again" brings it back; the browser test hooks skip it.
	s.reset_hints()
	assert_object(ControlsHint.show_once(parent, s, "helm")).is_not_null()
	s.reset_hints()
	s.skip_first_visit_help = true
	assert_object(ControlsHint.show_once(parent, s, "helm")).is_null()


func test_goes_after_six_seconds_or_a_tap() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var hint: ControlsHint = ControlsHint.show_once(parent, _settings(), "helm")
	hint._process(5.9)
	assert_bool(hint.is_queued_for_deletion()).is_false()
	hint._process(0.2)
	assert_bool(hint.is_queued_for_deletion()).is_true()
	var tapped: ControlsHint = ControlsHint.show_once(parent, _settings(), "helm")
	var asked: Array[bool] = []
	tapped.pressed.connect(func() -> void: asked.append(true))
	tapped.pressed.emit()
	assert_array(asked).has_size(1)
	assert_bool(tapped.is_queued_for_deletion()).is_true()


# FT: FT-STN-012
# D4: the hint names the way in on the player's device: the key, the pad button or the menu.
func test_the_hint_names_the_overlay_binding_of_the_device() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var kbm: ControlsHint = ControlsHint.show_once(parent, _settings(), "helm", IntentTable.KBM)
	assert_str(kbm.text).is_equal("Controls: press ?")
	var pad: ControlsHint = ControlsHint.show_once(parent, _settings(), "helm", IntentTable.PAD)
	assert_str(pad.text).is_equal("Controls: press View")
	var touch: ControlsHint = ControlsHint.show_once(
		parent, _settings(), "helm", IntentTable.KBM, true
	)
	assert_str(touch.text).is_equal(tr("controls.hint"))
	# A rebound key shows at once.
	var s: ClientSettings = _settings()
	s.bindings.rebind("overlay", IntentTable.KBM, PackedStringArray(["F9"]))
	assert_str(ControlsHint.show_once(parent, s, "helm", IntentTable.KBM).text).is_equal(
		"Controls: press F9"
	)


# FT: FT-STN-012
# D4: the overlay intent opens the page and takes the hint with it.
func test_the_overlay_intent_dismisses_the_hint() -> void:
	var ctx: StationContext = StationFixture.context("helm", CFG)
	ctx.settings.reset_hints()
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	add_child(screen)
	var asked: Array[bool] = []
	screen.help_requested.connect(func() -> void: asked.append(true))
	var hint: Node = screen.find_child("ControlsHint", true, false)
	assert_object(hint).is_not_null()
	screen.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	assert_array(asked).has_size(1)
	assert_bool(hint.is_queued_for_deletion()).is_true()


# FT: FT-STN-012
# D2, D369: the contact label legend shows once per client, below the Controls hint, never
# wider than a phone, and its tap asks for the callout card.
func test_the_legend_hint_shows_once_per_client() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	var s: ClientSettings = _settings()
	var legend: ControlsHint = ControlsHint.show_legend(parent, s)
	assert_object(legend).is_not_null()
	assert_str(legend.text).contains("H2 · 4 high · mid")
	assert_str(legend.name).is_equal("ControlsLegendHint")
	assert_object(ControlsHint.show_legend(parent, s)).is_null()
	legend._process(ControlsHint.LEGEND_S + 0.1)
	assert_bool(legend.is_queued_for_deletion()).is_true()
	s.reset_hints()
	assert_object(ControlsHint.show_legend(parent, s)).is_not_null()
	# The screen shows both on the first visit.
	var ctx: StationContext = StationFixture.context("helm", CFG)
	ctx.settings.reset_hints()
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	add_child(screen)
	var shown: ControlsHint = screen.find_child("ControlsLegendHint", true, false)
	assert_object(shown).is_not_null()
	var asked: Array[bool] = []
	screen.card_requested.connect(func() -> void: asked.append(true))
	shown.pressed.emit()
	assert_array(asked).has_size(1)
	# P4: on a 390 px phone the legend keeps 8 px clear of each side, as the radar legend does.
	var phone: Control = auto_free(Control.new())
	phone.size = Vector2(390, 844)
	add_child(phone)
	s.reset_hints()
	assert_float(ControlsHint.show_legend(phone, s).custom_minimum_size.x).is_equal(374.0)
