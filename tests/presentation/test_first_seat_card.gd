extends GdUnitTestSuite
## The first-seat card (C7, ux-15, FT-STN-012): on a player's first seat at a station, once
## per client and station, the station's three core lesson actions in the device's words, a
## pointer to Training › Callouts, and Got it; help never opens by itself.
# FT: FT-STN-012, FT-M1-019

const CFG: String = "user://test_first_seat_card.cfg"


func before() -> void:
	I18n.apply("en")


func _settings() -> ClientSettings:
	var s: ClientSettings = ClientSettings.new(CFG)
	s.reset_hints()
	return s


func _parent() -> Control:
	var parent: Control = auto_free(Control.new())
	parent.size = Vector2(1280, 720)
	add_child(parent)
	return parent


func test_shows_once_per_client_and_station() -> void:
	var parent: Control = _parent()
	var s: ClientSettings = _settings()
	var card: FirstSeatCard = FirstSeatCard.show_once(parent, s, "helm", IntentTable.KBM)
	assert_object(card).is_not_null()
	assert_object(card.get_parent()).is_same(parent)
	assert_object(FirstSeatCard.show_once(parent, s, "helm", IntentTable.KBM)).is_null()
	var saved: ClientSettings = ClientSettings.new(CFG)
	saved.load_file()
	assert_bool(saved.hint_seen("helm")).is_true()
	assert_object(FirstSeatCard.show_once(parent, s, "weapons")).is_not_null()
	# "Show first-visit hints again" brings it back; the browser test hooks skip it.
	s.reset_hints()
	assert_object(FirstSeatCard.show_once(parent, s, "helm")).is_not_null()
	s.reset_hints()
	s.skip_first_visit_help = true
	assert_object(FirstSeatCard.show_once(parent, s, "helm")).is_null()


# The station's first three lesson steps: its core actions (D232), in the device's words.
func test_the_three_core_actions_in_the_devices_words() -> void:
	var s: ClientSettings = _settings()
	var b: Bindings = s.bindings
	assert_array(FirstSeatCard.action_lines("helm", b, IntentTable.KBM, false)).is_equal(
		["Face selection: F", "Approach selection: X", "All stop: Space"]
	)
	assert_array(FirstSeatCard.action_lines("helm", b, IntentTable.PAD, false)).is_equal(
		["Face selection: L3", "Approach selection: B", "All stop: View+B"]
	)
	var touch: Array[String] = FirstSeatCard.action_lines("helm", b, IntentTable.KBM, true)
	assert_int(touch.size()).is_equal(3)
	for line: String in touch:
		# Touch words name the controls, never a key, and a real run has no drone.
		assert_str(line).not_contains("drone").not_contains("{")
	assert_str(touch[0]).starts_with("Select a contact")
	# A rebound key shows at once.
	b.rebind("face", IntentTable.KBM, PackedStringArray(["G"]))
	assert_str(FirstSeatCard.action_lines("helm", b, IntentTable.KBM, false)[0]).is_equal(
		"Face selection: G"
	)
	# Every crew station and the Captain have three; the Viewer has no lesson and no card.
	for station: String in StationCatalogue.CREW + [StationCatalogue.CAPTAIN]:
		for touch_words: bool in [false, true]:
			var lines: Array[String] = FirstSeatCard.action_lines(
				station, b, IntentTable.KBM, touch_words
			)
			assert_int(lines.size()).override_failure_message(station).is_equal(3)
			for line: String in lines:
				assert_str(line).override_failure_message(station).not_contains("drone")
	assert_object(FirstSeatCard.show_once(_parent(), s, StationCatalogue.VIEWER)).is_null()


func test_the_card_points_to_callouts_and_closes() -> void:
	var parent: Control = _parent()
	var card: FirstSeatCard = FirstSeatCard.show_once(parent, _settings(), "weapons", "kbm")
	var title: Label = card.find_child("Title", true, false)
	assert_str(title.text).is_equal("Weapons: start here")
	var callouts: Label = card.find_child("Callouts", true, false)
	assert_str(callouts.text).contains("Training › Callouts")
	assert_str(card.controls().text).is_equal("Controls: press ?")
	assert_str(card.got_it().text).is_equal("Got it  (Escape)")
	var asked: Array[bool] = []
	card.controls_requested.connect(func() -> void: asked.append(true))
	card.controls().pressed.emit()
	assert_array(asked).has_size(1)
	card.got_it().pressed.emit()
	assert_bool(card.is_queued_for_deletion()).is_true()
	# Touch: the menu route, no key.
	var touch: FirstSeatCard = FirstSeatCard.show_once(
		parent, _settings(), "weapons", IntentTable.KBM, true
	)
	assert_str(touch.controls().text).is_equal(tr("controls.hint"))
	assert_str(touch.got_it().text).is_equal("Got it")
	# P4: on a 390 px phone the card keeps 8 px clear of each side.
	var phone: Control = auto_free(Control.new())
	phone.size = Vector2(390, 844)
	add_child(phone)
	var narrow: FirstSeatCard = FirstSeatCard.show_once(phone, _settings(), "helm", "", true)
	await get_tree().process_frame
	assert_float(narrow.custom_minimum_size.x).is_equal(374.0)


# D4: the overlay intent opens the Controls page and takes the card with it; Esc closes it
# before it opens the menu.
func test_the_overlay_and_menu_intents_close_the_card() -> void:
	var ctx: StationContext = StationFixture.context("helm", CFG)
	ctx.settings.reset_hints()
	var screen: StationScreen = auto_free(StationScreen.new())
	screen.setup(ctx)
	add_child(screen)
	var asked: Array[bool] = []
	screen.help_requested.connect(func() -> void: asked.append(true))
	var card: FirstSeatCard = screen.first_seat_card()
	assert_object(card).is_not_null()
	screen.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	assert_array(asked).has_size(1)
	assert_bool(card.is_queued_for_deletion()).is_true()
	ctx.settings.reset_hints()
	var again: StationScreen = auto_free(StationScreen.new())
	again.setup(ctx)
	add_child(again)
	var menus: Array[bool] = []
	again.menu_requested.connect(func() -> void: menus.append(true))
	var second: FirstSeatCard = again.first_seat_card()
	again.dispatch({"id": "menu", "target": "screen", "pressed": true})
	assert_bool(second.is_queued_for_deletion()).is_true()
	assert_array(menus).is_empty()
	again.dispatch({"id": "menu", "target": "screen", "pressed": true})
	assert_array(menus).has_size(1)
