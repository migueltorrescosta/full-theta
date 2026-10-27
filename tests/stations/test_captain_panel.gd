extends GdUnitTestSuite
## The Captain's seat (§5.7) on the station fixture: the mirror, the view buttons and
## keys, the read-only chips and cards, pings on cards and marks into empty slots only.
## The Captain sends nothing that changes the ship (FT-CPT-003).

const SETTINGS: String = "user://test_captain_panel.cfg"
const ALLOWED: Array[String] = ["set_main_view", "ping", "place_mark"]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen() -> StationScreen:
	var ctx: StationContext = StationFixture.context(StationViews.CAPTAIN, SETTINGS)
	CommsFixture.install(ctx)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _captain(s: StationScreen) -> CaptainPanel:
	return s.panels[0] as CaptainPanel


# FT: FT-CPT-001, FT-CPT-004
func test_mirror_buttons_chips_and_cards() -> void:
	var s: StationScreen = await _screen()
	var cap: CaptainPanel = _captain(s)
	assert_object(cap).is_not_null()
	assert_object(cap.mirror).is_not_null()
	assert_bool(cap.mirror.interactive).is_true()
	assert_int(cap.buttons.size()).is_equal(5)
	(
		assert_array(cap.buttons.map(func(b: Button) -> String: return b.text))
		. is_equal(["Forward", "Chase", "Tactical", "Target", "Status"])
	)
	assert_bool(cap.buttons[0].button_pressed).is_true()
	# Read-only lists: no chip before the CHIPS block, and the mission and the contract of the
	# COMMS block (the offer and the hail are Comms' own).
	assert_int(cap.chips.rows.size()).is_equal(0)
	assert_int(CardList.rows(s.ctx.view, [CardList.MISSION, CardList.CONTRACT]).size()).is_equal(2)
	assert_int(cap.cards.card_at(Vector2(10.0, CardList.HEADER_HEIGHT + 5.0))).is_equal(0)
	assert_int(cap.cards.card_at(Vector2(10.0, 2.0))).is_equal(-1)
	# The ship's CHIPS block fills the list: the Captain sees every open chip, read-only.
	s.ctx.view.blocks[StationViews.Section.CHIPS] = {}
	await get_tree().process_frame
	assert_int(cap.chips.rows.size()).is_equal(0)
	var boost: int = NetChips.def().chips.find_custom(
		func(c: ChipDef) -> bool: return c.id == &"boost"
	)
	var tick: int = s.ctx.view.tick
	s.ctx.view.blocks[StationViews.Section.CHIPS] = {
		"chips":
		[
			{
				"id": 1,
				"chip": boost,
				"arg": -1,
				"from": StationViews.CREW.find("helm"),
				"to": StationViews.CREW.find("engineering"),
				"sent": tick,
				"expires": tick + 8 * SimWorld.HZ,
			}
		]
	}
	await get_tree().process_frame
	assert_int(cap.chips.rows.size()).is_equal(1)
	assert_str(ChipList.row_text(cap.chips.rows[0])).is_equal("Helm > Engineering  Boost  8 s")
	assert_array(StationViews.STATION_SECTIONS["captain"]).contains([StationViews.Section.CHIPS])


# FT: FT-CPT-001
func test_buttons_and_keys_send_the_main_view() -> void:
	var s: StationScreen = await _screen()
	var cap: CaptainPanel = _captain(s)
	var rec: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	cap.buttons[2].pressed.emit()
	assert_array(rec.of("set_main_view")[0][1]).is_equal([MainScreen.View.TACTICAL])
	(
		assert_bool(s.dispatch({"id": "captain_view_5", "target": "captain", "pressed": true}))
		. is_true()
	)
	assert_array(rec.of("set_main_view")[1][1]).is_equal([MainScreen.View.STATUS])
	# The d-pad steps through the views and wraps; the view is the server's, so it is
	# read from the last main_view event.
	s.ctx.crew.handle_event(
		{"type": "main_view", "payload": {"ship": 0, "view": 4, "by": "Ana"}}, 1
	)
	s.dispatch({"id": "captain_view_next", "target": "captain", "pressed": true})
	assert_array(rec.of("set_main_view")[2][1]).is_equal([MainScreen.View.FORWARD])
	s.dispatch({"id": "captain_view_prev", "target": "captain", "pressed": true})
	assert_array(rec.of("set_main_view")[3][1]).is_equal([MainScreen.View.TARGET])
	await get_tree().process_frame
	assert_bool(cap.buttons[4].button_pressed).is_true()


# FT: FT-CPT-003
# Whatever the Captain presses, nothing but the view, pings and marks is sent, and the
# alert level stays the crew's.
func test_the_captain_sends_no_mechanics_command() -> void:
	var s: StationScreen = await _screen()
	var rec: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	assert_bool(s.ctx.crew.is_crew()).is_false()
	for row: Dictionary in IntentTable.INTENTS:
		var id: String = row["id"]
		if row["kind"] == IntentTable.AXIS:
			continue
		var target: String = (
			"screen"
			if row["group"] in [IntentTable.COMMON, IntentTable.LIVE]
			else str(row["group"])
		)
		s.dispatch({"id": id, "group": row["group"], "target": target, "pressed": true})
	s._set_alert(2)
	s.top_bar.open_alert_picker()
	for sent: Array in rec.sent:
		assert_array(ALLOWED).contains([sent[0]])
	assert_array(rec.of("set_alert")).is_empty()
	assert_array(rec.of("command")).is_empty()
	assert_array(rec.of("claim")).is_empty()


# FT: FT-CPT-002, FT-SPA-013
# A Captain's mark goes to the first free slot; with all eight used the common action
# only toasts (the Captain never replaces a mark).
func test_marks_only_into_empty_slots() -> void:
	var s: StationScreen = await _screen()
	var rec: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	s.ctx.crew.select("contact", StationFixture.H2)
	s._mark(IntentTable.KBM)
	assert_int(rec.of("place_mark").size()).is_equal(1)
	assert_int(rec.of("place_mark")[0][1][0]).is_equal(-1)
	var marks: Array = []
	for slot: int in CrewState.MAX_MARKS:
		marks.append(
			{"slot": slot, "name": "M%d" % slot, "contact": -1, "x": 0, "y": 0, "z": 0, "by": "Ana"}
		)
	s.ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 1)
	s._mark(IntentTable.KBM)
	assert_int(rec.of("place_mark").size()).is_equal(1)
	assert_array(rec.of("move_mark")).is_empty()
	assert_array(rec.of("delete_mark")).is_empty()


# FT: FT-CPT-005
# A ping on a card in the list is sent as a card ping; the card is on the main screen
# for 10 s or until the next ping.
func test_a_card_ping_shows_the_card_for_ten_seconds() -> void:
	var s: StationScreen = await _screen()
	var cap: CaptainPanel = _captain(s)
	var rec: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	var row: float = cap.cards.global_position.y - cap.global_position.y
	var at: Vector2 = Vector2(
		cap.cards.global_position.x - cap.global_position.x + 20.0,
		row + CardList.HEADER_HEIGHT + CardList.ROW_HEIGHT * 1.0 + 5.0
	)
	assert_dict(cap.item_at(at)).is_equal({"kind": "card", "id": 1})
	s.ctx.ping_item(cap.item_at(at))
	assert_array(rec.of("ping")[0][1].slice(0, 2)).is_equal(["card", 1])
	var crew: CrewState = s.ctx.crew
	var t0: int = StationFixture.NOW_MS
	(
		crew
		. handle_event(
			{
				"type": "ping",
				"payload":
				{
					"ship": 0,
					"kind": "card",
					"id": 2,
					"by": "captain",
					"copy": "",
					"card": {"kind": 2, "title": "comms.card.offer", "detail": "", "expires": -1.0},
				}
			},
			t0
		)
	)
	assert_int(crew.shown_card(t0 + 9900)).is_equal(2)
	assert_str(crew.card_ping["card"]["title"]).is_equal("comms.card.offer")
	assert_int(crew.shown_card(t0 + CrewState.CARD_MS)).is_equal(-1)
	# The main screen draws it while it is shown.
	s.ctx.clock = func() -> int: return t0 + 5000
	cap.mirror.update_view(0.016)
	assert_int(cap.mirror._card_shown).is_equal(2)
	# The next ping, of anything, replaces it.
	crew.handle_event(
		{
			"type": "ping",
			"payload": {"ship": 0, "kind": "contact", "id": 2, "by": "Ana", "copy": ""}
		},
		t0 + 6000
	)
	assert_int(crew.shown_card(t0 + 6001)).is_equal(-1)
	# A card ping is no radar pulse and selects nothing.
	crew.handle_event(
		{
			"type": "ping",
			"payload": {"ship": 0, "kind": "card", "id": 1, "by": "captain", "copy": ""}
		},
		t0 + 7000
	)
	assert_int(crew.shown_card(t0 + 7001)).is_equal(1)
	assert_float(crew.pulse("card", 1, t0 + 7001)).is_equal(0.0)
	assert_bool(s._select("kbm")).is_false()
