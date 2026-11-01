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
		assert_int((report["targets"] as Array).size()).is_greater_equal(9)
		for k: String in ["under_min", "in_band", "outside_safe", "tight"]:
			(
				assert_array(report[k])
				. override_failure_message("%s %s: %s" % [spec[0], k, report[k]])
				. is_empty()
			)
		var upright: bool = (spec[0] as Vector2i).x < (spec[0] as Vector2i).y
		assert_int(m._picker.find_child("Cards", true, false).columns).is_equal(2 if upright else 4)
