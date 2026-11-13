extends GdUnitTestSuite
## The Shakedown's banner (FT-MIS-039, D235): the latest step per station from the
## shakedown subtitles, and Next for the focused station.


func _pairs(id: String) -> Array:
	return ["engineering", "helm"] if id == "pair_p1" else []


# FT: FT-MIS-039
func test_a_station_line_is_kept_for_its_station() -> void:
	var t: Dictionary = {}
	TrainingBanner.note(
		t, {"line": "shakedown.helm.face", "text": "Face the drone. {binding:face}"}, _pairs
	)
	assert_array(t.keys()).is_equal(["helm"])
	assert_str(t["helm"]["example"]).is_equal("train.ex.face")
	assert_bool(t["helm"]["done"]).is_false()
	TrainingBanner.note(t, {"line": "computer.hull_critical", "text": "x"}, _pairs)
	assert_array(t.keys()).is_equal(["helm"])


# FT: FT-MIS-039
func test_a_pair_line_reaches_both_stations_and_the_end_lines_all() -> void:
	var t: Dictionary = {}
	TrainingBanner.note(t, {"line": "shakedown.pair_p1", "text": "Boost together."}, _pairs)
	assert_array(t.keys()).contains_exactly_in_any_order(["engineering", "helm"])
	assert_str(t["helm"]["example"]).is_equal("train.ex.pair_p1")
	TrainingBanner.note(t, {"line": "shakedown.helm.track_done", "text": "Done."}, _pairs)
	assert_bool(t["helm"]["done"]).is_true()
	assert_str(t["helm"]["example"]).is_empty()
	TrainingBanner.note(t, {"line": "shakedown.all_done", "text": "Fly free."}, _pairs)
	assert_int(t.size()).is_equal(7)


# FT: FT-MIS-039
func test_next_sends_the_command_for_the_focused_station_and_the_key_presses_it() -> void:
	I18n.apply("en")
	var ctx: StationContext = StationFixture.context("tactical")
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	add_child(screen)
	var rec: StationFixture.RecordingClient = ctx.intents.client
	# Nothing to press outside a training run.
	assert_bool(screen.training.press()).is_false()
	assert_bool(screen.training.visible).is_false()
	TrainingBanner.note(
		ctx.training,
		{"line": "shakedown.helm.chase_camera", "text": "Chase. {binding:chase_camera}"},
		_pairs
	)
	screen.training.refresh()
	assert_bool(screen.training.visible).is_true()
	(
		assert_bool(
			screen.dispatch(IntentEvent.of("training_next", true, IntentTable.KBM, "screen"))
		)
		. is_true()
	)
	assert_array(rec.sent).has_size(1)
	assert_dict(rec.sent[0][1][0]).is_equal({"kind": "training_next", "station": "helm"})
	# The other station of a joint view has its own step.
	screen.focus(1)
	screen.training.refresh()
	assert_bool(screen.training.visible).is_false()


# FT: FT-MIS-039
# R25-15: the card shows the step's worked example once (with the player's binding); the
# line it repeats is the voice's.
func test_the_card_shows_the_example_not_the_voice_line_too() -> void:
	I18n.apply("en")
	var ctx: StationContext = StationFixture.context("helm")
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	add_child(screen)
	TrainingBanner.note(
		ctx.training,
		{"line": "shakedown.helm.face", "text": "Face the drone. {binding:face}"},
		_pairs
	)
	screen.training.refresh()
	var device: String = ctx.matcher.device
	var want: String = BindingText.fill_markers(tr("train.ex.face"), ctx.settings.bindings, device)
	if screen.training.touch_wording():
		want = TrainingBanner.touch_text("helm", "face")
	assert_str(screen.training._text.text).is_equal(want)
	assert_str(screen.training._text.text).not_contains("Face the drone. ")


# FT: FT-MIS-039
# R25-19: a control with no binding on the device drops its "press -" clause; the list of a
# grouped step keeps the bound ones, and a pad keeps a Helm-radial marker (its route).
func test_an_unbound_control_drops_its_clause_instead_of_a_dash() -> void:
	var b: Bindings = Bindings.new()
	var kbm: String = IntentTable.KBM
	var pad: String = IntentTable.PAD
	# (pinned here, whatever the table's defaults become)
	for id: String in ["ammo_prev", "mount_prev", "mount_next"]:
		b.rebind(id, kbm, [])
		b.rebind(id, pad, ["Down"])
	for id: String in ["mount_1", "mount_2"]:
		b.rebind(id, kbm, ["1"])
		b.rebind(id, pad, [])
	var one: String = "Ammo back: press {binding:ammo_prev}."
	assert_str(TrainingBanner.drop_unbound(one, b, kbm)).is_equal("Ammo back.")
	assert_str(TrainingBanner.drop_unbound(one, b, pad)).is_equal(one)
	var mounts: String = (
		"Pick a mount: {binding:mount_1}, {binding:mount_2}, back {binding:mount_prev},"
		+ " on {binding:mount_next}."
	)
	assert_str(TrainingBanner.drop_unbound(mounts, b, kbm)).is_equal(
		"Pick a mount: {binding:mount_1}, {binding:mount_2}."
	)
	assert_str(TrainingBanner.drop_unbound(mounts, b, pad)).is_equal(
		"Pick a mount: back {binding:mount_prev}, on {binding:mount_next}."
	)
	var radial: String = "Align: select the drone, press {binding:align}."
	assert_str(TrainingBanner.drop_unbound(radial, b, pad)).is_equal(radial)
	for key: String in ["train.ex.mount_1", "train.ex.shield_fore", "train.ex.comms_reply_1"]:
		for device: String in [kbm, pad]:
			var text: String = TrainingBanner.drop_unbound(tr(key), b, device)
			assert_str(BindingText.fill_markers(text, b, device)).not_contains(" -")
