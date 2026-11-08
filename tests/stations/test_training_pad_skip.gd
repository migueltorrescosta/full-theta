extends GdUnitTestSuite
## The Shakedown card for a controller player (D1, R25-1): a step whose action is only in the
## Helm radial says the radial route, and a command step offers Skip, which sends the skip
## command (Next on a command step still does nothing).

const SETTINGS: String = "user://test_training_pad_skip.cfg"


func before() -> void:
	I18n.apply("en")


func _screen(device: String) -> StationScreen:
	# A desktop-sized window: a phone's card reads in touch words.
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(1280, 720)
	add_child(vp)
	var ctx: StationContext = StationFixture.context("helm", SETTINGS)
	ctx.matcher.device = device
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	vp.add_child(screen)
	return screen


func _step(screen: StationScreen, intent: String, text: String) -> void:
	TrainingBanner.note(
		screen.ctx.training,
		{"line": "shakedown.helm." + intent, "text": text},
		func(_id: String) -> Array: return []
	)
	screen.training.refresh()


# FT: FT-MIS-039, FT-HLM-017
func test_a_radial_only_step_teaches_the_radial_on_a_pad() -> void:
	var screen: StationScreen = _screen(IntentTable.PAD)
	_step(screen, "align", "Align a mount to the target. {binding:align}")
	var card: TrainingBanner = screen.training
	var texts: Array = card.find_children("*", "Label", true, false).map(
		func(l: Label) -> String: return l.text
	)
	assert_array(texts).contains(["Align a mount to the target. Helm menu › Align"])
	assert_array(texts).contains(["Helm menu: hold View+Right stick, flick to Align, then let go."])
	# The keyboard reads its key.
	var kbm: StationScreen = _screen(IntentTable.KBM)
	_step(kbm, "align", "Align a mount to the target. {binding:align}")
	var kbm_texts: Array = kbm.training.find_children("*", "Label", true, false).map(
		func(l: Label) -> String: return l.text
	)
	assert_array(kbm_texts).contains(["Align a mount to the target. L"])


# FT: FT-MIS-039
func test_skip_shows_on_command_steps_only_and_sends_the_skip_command() -> void:
	assert_bool(TrainingBanner.is_command_step("helm", "align")).is_true()
	assert_bool(TrainingBanner.is_command_step("helm", "chase_camera")).is_false()
	assert_bool(TrainingBanner.is_command_step("helm", "nothing")).is_false()
	var screen: StationScreen = _screen(IntentTable.PAD)
	var skip: Button = screen.training.find_child("Skip", true, false)
	_step(screen, "align", "Align. {binding:align}")
	assert_bool(skip.visible).is_true()
	assert_str(skip.text).is_equal("Skip this step")
	_step(screen, "chase_camera", "Chase. {binding:chase_camera}")
	assert_bool(skip.visible).is_false()
	_step(screen, "align", "Align. {binding:align}")
	var rec: StationFixture.RecordingClient = screen.ctx.intents.client
	skip.pressed.emit()
	assert_array(rec.sent).has_size(1)
	assert_dict(rec.sent[0][1][0]).is_equal(
		{"kind": "training_next", "station": "helm", "skip": true}
	)
