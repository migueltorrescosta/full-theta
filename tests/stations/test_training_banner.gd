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
		assert_bool(screen.dispatch({"id": "training_next", "target": "screen", "pressed": true}))
		. is_true()
	)
	assert_array(rec.sent).has_size(1)
	assert_dict(rec.sent[0][1][0]).is_equal({"kind": "training_next", "station": "helm"})
	# The other station of a joint view has its own step.
	screen.focus(1)
	screen.training.refresh()
	assert_bool(screen.training.visible).is_false()
