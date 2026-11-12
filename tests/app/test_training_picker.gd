extends GdUnitTestSuite
## The Training picker and its entry from the main menu (D303, FT-MIS-039, FT-STN-005):
## seven station cards and a crew drill card, ticks kept on the device, replay, a lesson two
## taps from the main menu, touch rules on a phone in both orientations, the busy note.

const TOKEN: String = "user://test_picker_token.json"
const PID: String = "user://test_picker_pid.json"
const SETTINGS: String = "user://test_picker_settings.cfg"


func after_test() -> void:
	for p: String in [TOKEN, PID, SETTINGS]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	get_tree().root.content_scale_factor = 1.0
	SafeArea.simulate([])


func _menu(size: Vector2i = Vector2i(1280, 720), insets: Array = [], web: bool = true) -> MainMenu:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var m: MainMenu = MainMenu.new()
	m.web = web
	m.token_path = TOKEN
	m.pid_path = PID
	m.settings = ClientSettings.new(SETTINGS)
	vp.add_child(m)
	for i: int in 3:
		await get_tree().process_frame
	return m


# FT: FT-MIS-039
# Any lesson is two taps from the main menu: Training, then the card.
func test_a_lesson_is_two_taps_from_the_main_menu() -> void:
	var m: MainMenu = await _menu()
	m.web = true
	(m.find_child("Address", true, false) as LineEdit).text = "127.0.0.1:1"
	var picker: TrainingPicker = m._picker
	assert_bool(picker.visible).is_false()
	(m.find_child("Training", true, false) as Button).pressed.emit()
	assert_bool(picker.visible).is_true()
	for station: String in TrainingPicker.LESSONS:
		assert_object(picker.card(station)).is_not_null()
		assert_bool(picker.card(station).visible).is_true()
	assert_object(picker.crew_drill()).is_not_null()
	picker.card("weapons").pressed.emit()
	# The browser joins the server for it and asks for the lesson once welcomed.
	assert_bool(m._lesson_on).is_true()
	assert_str(m._lesson).is_equal("weapons")
	assert_object(m.joining).is_not_null()
	assert_bool(picker.card("helm").disabled).is_true()


# FT: FT-MIS-039
# The drill card is the empty station.
func test_the_crew_drill_card_asks_for_no_station() -> void:
	var m: MainMenu = await _menu()
	(m.find_child("Address", true, false) as LineEdit).text = "127.0.0.1:1"
	m.open_training()
	m._picker.crew_drill().pressed.emit()
	assert_bool(m._lesson_on).is_true()
	assert_str(m._lesson).is_empty()


# FT: FT-MIS-039
# Ticks are kept on the device: set when a lesson ends, shown on its card, saved and read back,
# and a done card can be played again.
func test_ticks_persist_and_a_done_lesson_can_be_replayed() -> void:
	var m: MainMenu = await _menu()
	var picker: TrainingPicker = m._picker
	assert_str(_text(picker, "Helm", "Tick")).is_empty()
	assert_str((picker.find_child("Count", true, false) as Label).text).contains("0 ")
	m._lesson_on = true
	m._lesson = "helm"
	m._on_lesson_line({"line": "shakedown.helm.track_done"})
	assert_bool(m.settings.lesson_done("helm")).is_false()
	m._on_lesson_line({"line": "shakedown.all_done"})
	assert_bool(m.settings.lesson_done("helm")).is_true()
	assert_str(_text(picker, "Helm", "Tick")).is_equal("✓")
	assert_str(_text(picker, "Helm", "State")).is_equal(tr("train.picker.again"))
	assert_str(_text(picker, "Weapons", "State")).is_equal(tr("train.picker.start"))
	assert_bool(picker.card("helm").disabled).is_false()
	var again: ClientSettings = ClientSettings.new(SETTINGS)
	again.load_file()
	assert_bool(again.lesson_done("helm")).is_true()
	assert_bool(again.lesson_done("weapons")).is_false()
	# The crew drill never ticks a station.
	m._lesson = ""
	m._on_lesson_line({"line": "shakedown.all_done"})
	assert_int(m.settings.lessons_done.size()).is_equal(1)


func _text(picker: TrainingPicker, card_name: String, label: String) -> String:
	return (picker.find_child(card_name, true, false).find_child(label, true, false) as Label).text


# FT: FT-MIS-039
func test_the_busy_note_names_the_players() -> void:
	var m: MainMenu = await _menu()
	var picker: TrainingPicker = m._picker
	picker.show_busy(3)
	var note: Label = picker.find_child("Note", true, false)
	assert_bool(note.visible).is_true()
	assert_str(note.text).is_equal(tr("train.picker.busy_many") % 3)
	picker.show_busy(1)
	assert_str(note.text).is_equal(tr("train.picker.busy_one") % 1)
	picker.show_note("")
	assert_bool(note.visible).is_false()


# FT: FT-MIS-039
# A refusal from the server brings the picker back with the note, and nothing is left running.
func test_a_busy_refusal_shows_in_the_picker() -> void:
	var m: MainMenu = await _menu()
	m.web = true
	var shell: ClientShell = auto_free(ClientShell.new())
	var client: NetClient = NetClient.new()
	m.add_child(shell)
	shell.setup(client, m.settings)
	m.shell = shell
	shell.left.connect(m._on_left)
	m._lesson_on = true
	m._lesson = "relay"
	(
		m
		. _on_lesson_event(
			{
				"type": NetProtocol.EVENT_REQUEST_REJECTED,
				"payload": {"request": NetProtocol.Type.TRAINING, "reason": "busy", "players": 2},
			}
		)
	)
	assert_object(m.shell).is_null()
	assert_bool(m._picker.visible).is_true()
	assert_str((m._picker.find_child("Note", true, false) as Label).text).is_equal(
		tr("train.picker.busy_many") % 2
	)
	assert_bool(m._lesson_on).is_false()


# FT: FT-MIS-039, FT-STN-005
# On a phone, upright and on its side, the cards are touch targets inside the safe area and
# the lesson list needs no more than two taps.
func test_the_picker_obeys_the_touch_rules_on_a_phone() -> void:
	for spec: Array in [
		[Vector2i(390, 844), [0, 47, 0, 34]], [Vector2i(844, 390), [47, 0, 47, 21]]
	]:
		var m: MainMenu = await _menu(spec[0], spec[1], true)
		m.open_training()
		for i: int in 2:
			await get_tree().process_frame
		var report: Dictionary = TapAudit.check(m._picker)
		# Back, the crew drill and at least the first row of lessons above the fold.
		assert_int((report["targets"] as Array).size()).is_greater_equal(6)
		# A card cut by the scroll's edge is a sliver of a full-size card, not a small target.
		var clip: Rect2 = m._picker._scroll.get_global_rect()
		for t: Dictionary in report["targets"]:
			var r: Rect2 = t["rect"]
			if minf(r.size.x, r.size.y) < UiTheme.TOUCH_MIN - 2.0:
				assert_float(r.end.y).is_equal_approx(clip.end.y, 1.0)
		report["under_min"] = []
		for k: String in ["under_min", "in_band", "outside_safe", "tight"]:
			(
				assert_array(report[k])
				. override_failure_message("%s %s: %s" % [spec[0], k, report[k]])
				. is_empty()
			)
		var upright: bool = (spec[0] as Vector2i).x < (spec[0] as Vector2i).y
		assert_int(m._picker.find_child("Cards", true, false).columns).is_equal(2 if upright else 4)


# FT: FT-MIS-039
# ux-05, R26-12: the crew drill is listed first, for a group, with Start; the solo lessons say
# they are solo, and Helm is the one to start with until it is done.
func test_the_crew_drill_comes_first_and_helm_is_the_first_lesson() -> void:
	var m: MainMenu = await _menu()
	var picker: TrainingPicker = m._picker
	var drill: Button = picker.crew_drill()
	var cards: Control = picker.find_child("Cards", true, false)
	assert_int(drill.get_index()).is_less(cards.get_index())
	assert_object(drill.get_parent()).is_same(cards.get_parent())
	assert_str((drill.find_child("Name", true, false) as Label).text).is_equal(
		tr("train.picker.drill")
	)
	assert_str((drill.find_child("Blurb", true, false) as Label).text).contains(
		tr("train.picker.drill_hint")
	)
	assert_str((drill.find_child("State", true, false) as Label).text).is_equal(
		tr("train.picker.start")
	)
	var solo: Label = picker.find_child("SoloHeading", true, false)
	assert_str(solo.text).is_equal(tr("train.picker.solo"))
	assert_int(solo.get_index()).is_less(cards.get_index())
	assert_str(_text(picker, "Helm", "State")).is_equal(tr("train.picker.start_here"))
	assert_str(_text(picker, "Weapons", "State")).is_equal(tr("train.picker.start"))
	m.settings.mark_lesson_done("helm")
	picker.refresh()
	assert_str(_text(picker, "Helm", "State")).is_equal(tr("train.picker.again"))


# FT: FT-MIS-039
# R25-16: the cards count the grouped steps: Helm's track is under 40 steps.
func test_the_cards_count_the_grouped_steps() -> void:
	var m: MainMenu = await _menu()
	var steps: int = m._picker.steps["helm"]
	assert_int(steps).is_less(40)
	assert_str(_text(m._picker, "Helm", "Size")).is_equal(tr("train.picker.steps") % steps)


# FT: FT-STN-012, FT-MIS-039
# ux-11 (D45 unchanged): the Callouts card opens a quiz on the client, with no server: a
# callout as the game writes it, then three picks (clock, height, range) each answered at
# once; Next shows only after an answer; the last one ticks the lesson on the device.
func test_the_callouts_quiz_runs_on_the_client_and_ticks_the_lesson() -> void:
	var m: MainMenu = await _menu(Vector2i(1280, 720), [], false)
	m.open_training()
	var card: Button = m._picker.card(TrainingPicker.CALLOUTS)
	assert_str((card.find_child("Size", true, false) as Label).text).is_equal(
		tr("train.picker.questions") % 3
	)
	card.pressed.emit()
	var quiz: CalloutsQuiz = m._quiz
	assert_bool(quiz.visible).is_true()
	assert_bool(m._lesson_on).is_false()
	assert_object(m.host_session).is_null()
	assert_object(m.joining).is_null()
	assert_str(quiz.callout_text()).is_equal("H2 · 4 high · mid")
	assert_str((quiz.find_child("Callout", true, false) as Label).text).is_equal(
		"H2 · 4 high · mid"
	)
	var next: Button = quiz.find_child("Next", true, false)
	var feedback: Label = quiz.find_child("Feedback", true, false)
	var answers: Array[String] = []
	for q: int in CalloutsQuiz.QUESTIONS:
		assert_bool(next.visible).is_false()
		var opts: Array = quiz.options()
		answers.append(str(opts[0][opts[1]]))
		# The first is answered wrong: the card names the right answer and locks the options.
		var pick: int = (int(opts[1]) + 1) % 3 if q == 0 else int(opts[1])
		(quiz.find_child("Option%d" % pick, true, false) as Button).pressed.emit()
		assert_bool(next.visible).is_true()
		assert_bool((quiz.find_child("Option0", true, false) as Button).disabled).is_true()
		if q == 0:
			assert_str(feedback.text).is_equal(tr("train.quiz.wrong") % answers[0])
		else:
			assert_str(feedback.text).is_equal(tr("train.quiz.right"))
		if q < CalloutsQuiz.QUESTIONS - 1:
			assert_bool(m.settings.lesson_done(TrainingPicker.CALLOUTS)).is_false()
		next.pressed.emit()
	assert_array(answers).is_equal(["4 o'clock", tr("callout.high"), tr("train.quiz.mid")])
	assert_int(quiz.right).is_equal(2)
	assert_bool(m.settings.lesson_done(TrainingPicker.CALLOUTS)).is_true()
	assert_str(_text(m._picker, "Callouts", "Tick")).is_equal("✓")
	assert_str((m._picker.find_child("Count", true, false) as Label).text).is_equal(
		tr("train.picker.done_count") % [1, 8]
	)
	# Again reads the next sample callout; Back returns to the picker.
	next.pressed.emit()
	assert_int(quiz.question).is_equal(0)
	assert_str(quiz.callout_text()).is_equal("Bravo · 9 low · far")
	(quiz.find_child("Back", true, false) as Button).pressed.emit()
	assert_bool(quiz.visible).is_false()
	assert_bool(m._picker.visible).is_true()
