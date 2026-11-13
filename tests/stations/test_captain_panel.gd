extends GdUnitTestSuite
## The Captain's seat (§5.7) on the station fixture: the mirror, the view buttons and
## keys, the read-only chips and cards, pings on cards and marks into empty slots only.
## The Captain sends nothing that changes the ship (FT-CPT-003).

const SETTINGS: String = "user://test_captain_panel.cfg"
const ALLOWED: Array[String] = ["set_main_view", "ping", "place_mark"]


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	# gdUnit's 64 x 64 window is a phone on its side; these check the desktop layout (#28).
	LayoutMode.forced = LayoutMode.Kind.DESKTOP


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen() -> StationScreen:
	var ctx: StationContext = StationFixture.context(StationCatalogue.CAPTAIN, SETTINGS)
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
		. is_equal(["Forward", "Chase", "Tactical", "Close-up", "Status"])
	)
	assert_bool(cap.buttons[0].button_pressed).is_true()
	# Read-only lists: no chip before the CHIPS block, and the mission and the contract of the
	# COMMS block (the offer and the hail are Comms' own).
	assert_int(cap.chips.rows.size()).is_equal(0)
	assert_int(CardList.rows(s.ctx.snap, [CardList.MISSION, CardList.CONTRACT]).size()).is_equal(2)
	assert_int(cap.cards.card_at(Vector2(10.0, CardList.HEADER_HEIGHT + 5.0))).is_equal(0)
	assert_int(cap.cards.card_at(Vector2(10.0, 2.0))).is_equal(-1)
	# The ship's CHIPS block fills the list: the Captain sees every open chip, read-only.
	s.ctx.snap.blocks[StationCatalogue.Section.CHIPS] = {}
	await get_tree().process_frame
	assert_int(cap.chips.rows.size()).is_equal(0)
	var boost: int = ChipsReader.def().chips.find_custom(
		func(c: ChipDef) -> bool: return c.id == &"boost"
	)
	var tick: int = s.ctx.snap.tick
	s.ctx.snap.blocks[StationCatalogue.Section.CHIPS] = {
		"chips":
		[
			{
				"id": 1,
				"chip": boost,
				"arg": -1,
				"from": StationCatalogue.CREW.find("helm"),
				"to": StationCatalogue.CREW.find("engineering"),
				"sent": tick,
				"expires": tick + 8 * SimWorld.HZ,
			}
		]
	}
	await get_tree().process_frame
	assert_int(cap.chips.rows.size()).is_equal(1)
	assert_str(ChipList.row_text(cap.chips.rows[0])).is_equal(
		"Helm > Engineering  Boost  waiting, 8 s left"
	)
	# Two lines, the time under the request, so the bar under them crosses no text (w5).
	assert_str(ChipList.head_text(cap.chips.rows[0])).is_equal("Helm > Engineering  Boost")
	assert_str(ChipList.time_text(cap.chips.rows[0])).is_equal("waiting, 8 s left")
	assert_float(cap.chips.custom_minimum_size.y).is_equal(
		ChipList.HEADER_HEIGHT + ChipList.ROW_HEIGHT
	)
	assert_array(StationCatalogue.STATION_SECTIONS["captain"]).contains(
		[StationCatalogue.Section.CHIPS]
	)


# FT: FT-CPT-004
# R23-12: a request that goes shows "Answered", or "Expired" when it ran out, for a few
# seconds, then its row goes.
func test_a_gone_request_shows_answered_or_expired_then_goes() -> void:
	var list: ChipList = auto_free(ChipList.new())
	var row: Callable = func(id: int, left: float) -> Dictionary:
		return {
			"id": id,
			"from": "helm",
			"to": "engineering",
			"label": "Boost",
			"time_left": left,
			"total_time": 20.0
		}
	var both: Array[Dictionary] = [row.call(1, 12.0), row.call(2, 1.0)]
	list.show_rows(both, 0)
	var none: Array[Dictionary] = []
	list.show_rows(none, 100)
	assert_int(list.rows.size()).is_equal(0)
	var shown: Array[Dictionary] = list.shown()
	assert_int(shown.size()).is_equal(2)
	assert_str(ChipList.time_text(shown[0])).is_equal("Answered")
	assert_str(ChipList.time_text(shown[1])).is_equal("Expired, nobody answered")
	assert_float(list.custom_minimum_size.y).is_equal(
		ChipList.HEADER_HEIGHT + 2 * ChipList.ROW_HEIGHT
	)
	list.show_rows(none, 100 + ChipList.DONE_MS)
	assert_array(list.shown()).is_empty()


# FT: FT-CPT-001
func test_buttons_and_keys_send_the_main_view() -> void:
	var s: StationScreen = await _screen()
	var cap: CaptainPanel = _captain(s)
	var rec: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	cap.buttons[2].pressed.emit()
	assert_array(rec.of("set_main_view")[0][1]).is_equal([MainScreen.View.TACTICAL])
	(
		assert_bool(s.dispatch(IntentEvent.of("captain_view_5", true, IntentTable.KBM, "captain")))
		. is_true()
	)
	assert_array(rec.of("set_main_view")[1][1]).is_equal([MainScreen.View.STATUS])
	# The d-pad steps through the views and wraps; the view is the server's, so it is
	# read from the last main_view event.
	s.ctx.crew.handle_event(
		{"type": "main_view", "payload": {"ship": 0, "view": 4, "by": "Ana"}}, 1
	)
	s.dispatch(IntentEvent.of("captain_view_next", true, IntentTable.KBM, "captain"))
	assert_array(rec.of("set_main_view")[2][1]).is_equal([MainScreen.View.FORWARD])
	s.dispatch(IntentEvent.of("captain_view_prev", true, IntentTable.KBM, "captain"))
	assert_array(rec.of("set_main_view")[3][1]).is_equal([MainScreen.View.CLOSE_UP])
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
		s.dispatch(IntentEvent.of(id, true, IntentTable.KBM, target))
	s.common.set_alert(2)
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
	s.common.mark(IntentTable.KBM)
	assert_int(rec.of("place_mark").size()).is_equal(1)
	assert_int(rec.of("place_mark")[0][1][0]).is_equal(-1)
	var marks: Array = []
	for slot: int in CrewState.MAX_MARKS:
		marks.append(
			{"slot": slot, "name": "M%d" % slot, "contact": -1, "x": 0, "y": 0, "z": 0, "by": "Ana"}
		)
	s.ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 1)
	s.common.mark(IntentTable.KBM)
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
	assert_bool(s.common.select("kbm")).is_false()


# FT: FT-CPT-004, FT-CPT-005
# R23-12 (C10): a card shows its state in the list, and the card the Captain pinged opens
# with its detail, reward and who holds it; the rows below it move down.
func test_a_pinged_card_expands_in_the_list() -> void:
	var s: StationScreen = await _screen()
	var cap: CaptainPanel = _captain(s)
	var list: CardList = cap.cards
	var second_before: float = list.row_bottoms()[2]
	assert_int(list.expanded).is_equal(-1)
	(
		s
		. ctx
		. crew
		. handle_event(
			{
				"type": "ping",
				"payload":
				{
					"ship": 0,
					"kind": "card",
					"id": CommsFixture.MISSION,
					"by": "captain",
					"copy": "",
					"card": {"kind": 0, "title": "t", "detail": "", "expires": -1.0},
				}
			},
			StationFixture.NOW_MS
		)
	)
	s.ctx.clock = func() -> int: return StationFixture.NOW_MS + 1000
	cap._process(0.016)
	assert_int(list.expanded).is_equal(CommsFixture.MISSION)
	assert_float(list.row_bottoms()[2]).is_equal(second_before + CardList.EXTRA_HEIGHT)
	# A tap below the open card still finds the next card, shifted down.
	assert_int(list.card_at(Vector2(10.0, second_before + CardList.EXTRA_HEIGHT - 5.0))).is_equal(
		CommsFixture.CONTRACT
	)
