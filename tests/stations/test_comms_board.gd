extends GdUnitTestSuite
## Comms' card board (§5.6, D87): missions, contracts, and offers with hails in three
## columns, a card's conversation as an overlay and back, the claimer on each card, the
## docked flag, credits and reputation, the Comms keys, the hold-fire request, the marks and
## pings of a card's contact, and the real cards in the Captain's and the joint views' lists.

const SETTINGS: String = "user://test_comms_board.cfg"
const BOARD_SIZE: Vector2 = Vector2(1100, 700)


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(entry: String = "comms", code: String = "easy") -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	ctx.crew.toggles = DataToggles.parse(code)
	CommsFixture.install(ctx)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _comms(s: StationScreen) -> CommsPanel:
	return s.panels[s.stations.find("comms")] as CommsPanel


func _ev(id: String, s: StationScreen, device: String = "kbm") -> Dictionary:
	return {
		"id": id,
		"group": IntentTable.row(id)["group"],
		"target": IntentTable.target(id, device, s.focused_station(), s.stations),
		"kind": IntentTable.row(id)["kind"],
		"pressed": true,
		"value": 1.0,
		"device": device,
	}


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


func _click(c: Control, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		c._gui_input(e)


# FT: FT-COM-008, FT-STN-005
# The board sorts the cards into three columns, missions, contracts, and offers with hails,
# each card in its own column, left to right.
func test_cards_sit_in_three_columns() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.board.size = BOARD_SIZE
	var at: Dictionary = {}
	for id: int in 4:
		var r: Rect2 = panel.board.card_rect(id)
		assert_bool(r.size != Vector2.ZERO).override_failure_message("card %d" % id).is_true()
		at[id] = r.position
	assert_float(at[CommsFixture.MISSION].x).is_less(at[CommsFixture.CONTRACT].x)
	assert_float(at[CommsFixture.CONTRACT].x).is_less(at[CommsFixture.OFFER].x)
	assert_float(at[CommsFixture.OFFER].x).is_equal(at[CommsFixture.HAIL].x)
	assert_float(at[CommsFixture.OFFER].y).is_less(at[CommsFixture.HAIL].y)
	# A click or tap on a card finds it; the gap between columns finds none.
	assert_int(panel.board.card_at(panel.board.card_rect(CommsFixture.HAIL).get_center())).is_equal(
		CommsFixture.HAIL
	)
	assert_int(panel.board.card_at(Vector2(1.0, 1.0))).is_equal(-1)


# FT: FT-COM-008, FT-COM-005, FT-COM-001
# The header names the docked site and the credits, the footer the standing with each faction,
# a card its reward and the reputation range the data makes visible, and the hull band is the
# only condition shown.
func test_header_footer_and_card_texts() -> void:
	var s: StationScreen = await _screen()
	var board: CommsBoard = _comms(s).board
	assert_str(board.header_text()).is_equal("Comms   docked: Kappa")
	assert_str(board.status_text()).is_equal("hull ok   cr 1200")
	assert_str(board.rep_text()).is_equal("Reputation  F1 +12   F2 -2")
	var mission: Dictionary = CommsData.card(CommsData.block(s.ctx.view), CommsFixture.MISSION)
	assert_str(CommsData.range_text(mission)).is_equal("rep +4 to +12")
	assert_str(CommsData.range_text(CommsData.card(CommsData.block(s.ctx.view), 1))).is_empty()
	var blk: Dictionary = CommsFixture.block()
	blk["docked"] = false
	blk["credits"] = 30
	blk["hull_band"] = 2
	CommsFixture.install(s.ctx, blk)
	_comms(s).refresh()
	assert_str(board.header_text()).is_equal("Comms   not docked")
	assert_str(board.status_text()).is_equal("hull damaged   cr 30")


# FT: FT-COM-008, FT-COM-006
# Opening a card shows its conversation as an overlay above the board and Esc brings back the
# board without opening the menu; each card with a conversation shows who holds it.
func test_open_a_card_and_close_it_again() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	s.ctx.crew.claims["npc:2"] = {"session": 9, "name": "Bo"}
	panel.refresh()
	assert_str(panel.board.claim_names[2]).is_equal("Bo")
	assert_str(panel.board.claim_names[3]).is_equal("")
	var menus: Array[int] = []
	s.menu_requested.connect(func() -> void: menus.append(1))
	assert_bool(panel.overlay.visible).is_false()
	panel.board.select(CommsFixture.OFFER)
	assert_bool(s.dispatch(_ev("comms_open", s))).is_true()
	assert_bool(panel.overlay.visible).is_true()
	assert_int(panel.overlay.card_id).is_equal(CommsFixture.OFFER)
	assert_str(panel.overlay.holder).is_equal("Bo")
	# Its conversation is open already: nothing to answer.
	assert_array(_commands(s, "comms_answer")).is_empty()
	assert_bool(s.dispatch(_ev("menu", s))).is_true()
	assert_bool(panel.overlay.visible).is_false()
	assert_array(menus).is_empty()
	# With the board showing, Esc opens the menu as before.
	s.dispatch(_ev("menu", s))
	assert_array(menus).has_size(1)


# FT: FT-COM-002, FT-COM-006
# An unanswered hail is answered when opened (the server takes the free claim), and a
# click on the card does the same.
func test_opening_a_hail_answers_it() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.board.size = BOARD_SIZE
	_click(panel.board, panel.board.card_rect(CommsFixture.HAIL).get_center())
	assert_int(panel.overlay.card_id).is_equal(CommsFixture.HAIL)
	assert_array(_commands(s, "comms_answer")).has_size(1)
	assert_int(_commands(s, "comms_answer")[0]["card"]).is_equal(CommsFixture.HAIL)


# FT: FT-COM-007, FT-COM-008, FT-STN-005
# Keys 1 to 4 pick the numbered replies of the open conversation; a controller's A does the
# focused reply and B closes the overlay; a reply the science scan unlocked carries its icon.
func test_replies_by_key_and_by_pad() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.open_card(CommsFixture.OFFER)
	var rows: Array[Dictionary] = panel.overlay.rows()
	assert_str(panel.overlay.row_text(rows[1])).contains("Call the bluff").contains("[scan]")
	s.dispatch(_ev("comms_reply_3", s))
	assert_str(_commands(s, "comms_reply")[0]["option"]).is_equal("o4")
	assert_int(_commands(s, "comms_reply")[0]["card"]).is_equal(CommsFixture.OFFER)
	# 4 has no reply: nothing is sent.
	s.dispatch(_ev("comms_reply_4", s))
	assert_array(_commands(s, "comms_reply")).has_size(1)
	# Controller: down moves the focus, A (the common select) does that row.
	panel.overlay.focus = 0
	s.dispatch(_ev("comms_down", s, "pad"))
	assert_int(panel.overlay.focus).is_equal(1)
	assert_bool(s.dispatch(_ev("select", s, "pad"))).is_true()
	assert_str(_commands(s, "comms_reply")[1]["option"]).is_equal("o3")
	assert_bool(s.dispatch(_ev("comms_close", s, "pad"))).is_true()
	assert_bool(panel.overlay.visible).is_false()


# FT: FT-COM-003, FT-COM-008
# Enter and Backspace accept and decline the selected card, alone (no claim), and A on a
# controller opens the card the d-pad moved to.
func test_accept_decline_and_pad_navigation() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.board.select(CommsFixture.MISSION)
	assert_bool(s.dispatch(_ev("accept", s))).is_true()
	assert_int(_commands(s, "comms_accept")[0]["card"]).is_equal(CommsFixture.MISSION)
	panel.board.select(CommsFixture.CONTRACT)
	assert_bool(s.dispatch(_ev("decline", s))).is_true()
	assert_int(_commands(s, "comms_decline")[0]["card"]).is_equal(CommsFixture.CONTRACT)
	# Tab and the arrows walk the board: columns right, cards down.
	panel.board.select(CommsFixture.MISSION)
	s.dispatch(_ev("comms_next_column", s))
	assert_int(panel.board.selected).is_equal(CommsFixture.CONTRACT)
	s.dispatch(_ev("comms_right", s, "pad"))
	assert_int(panel.board.selected).is_equal(CommsFixture.OFFER)
	s.dispatch(_ev("comms_down", s, "pad"))
	assert_int(panel.board.selected).is_equal(CommsFixture.HAIL)
	assert_bool(s.dispatch(_ev("select", s, "pad"))).is_true()
	assert_int(panel.overlay.card_id).is_equal(CommsFixture.HAIL)


# FT: FT-COM-003, FT-MIS-027
# An information card (kind 4, Q23) hides the Accept button and its binding does nothing,
# while a mission card keeps both; Decline still reaches the server.
func test_an_information_card_cannot_be_accepted() -> void:
	var blk: Dictionary = CommsFixture.block()
	var info: int = 7
	(blk["cards"] as Array).append(
		CommsFixture.card(info, CardList.INFO, "Kappa", {"detail": "card.encounter_pending.detail"})
	)
	var ctx: StationContext = StationFixture.context("comms", SETTINGS)
	CommsFixture.install(ctx, blk)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: CommsPanel = _comms(s)
	var accept: Button = panel._buttons["accept"]
	panel.board.select(CommsFixture.MISSION)
	panel.refresh()
	assert_bool(accept.visible).is_true()
	panel.board.select(info)
	panel.refresh()
	assert_bool(accept.visible).is_false()
	assert_bool(s.dispatch(_ev("accept", s))).is_true()
	assert_array(_commands(s, "comms_accept")).is_empty()
	assert_bool(s.dispatch(_ev("decline", s))).is_true()
	assert_int(_commands(s, "comms_decline")[0]["card"]).is_equal(info)
	panel.board.select(CommsFixture.MISSION)
	panel.refresh()
	assert_bool(accept.visible).is_true()


# FT: FT-COM-006
# K claims the open conversation's NPC (`npc:<card>`), again releases it; a card without a
# conversation has no claim.
func test_claim_key_takes_the_open_conversation() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.board.select(CommsFixture.MISSION)
	assert_str(panel.claim_item()).is_empty()
	panel.open_card(CommsFixture.OFFER)
	assert_str(panel.claim_item()).is_equal("npc:2")
	s.dispatch(_ev("claim", s))
	assert_array(StationFixture.sent(s.ctx).of("claim")[0][1]).is_equal(["npc:2"])
	s.ctx.crew.claims["npc:2"] = {"session": StationFixture.SESSION, "name": "Ana"}
	s.dispatch(_ev("claim", s))
	assert_array(StationFixture.sent(s.ctx).of("release_claim")[0][1]).is_equal(["npc:2"])


# FT: FT-PAIR-021, FT-PAIR-017
# B sends the hold-fire request naming the selected contact; with no contact it asks for one
# and sends nothing; H hails the same contact.
func test_hold_fire_request_and_hail_name_the_selected_contact() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.board.select(CommsFixture.CONTRACT)
	var toasts: Array[String] = []
	s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
	assert_bool(s.dispatch(_ev("request", s))).is_true()
	assert_array(StationFixture.sent(s.ctx).of("send_chip")).is_empty()
	assert_array(toasts).is_equal(["toast.select_first"])
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_bool(s.dispatch(_ev("request", s))).is_true()
	assert_array(StationFixture.sent(s.ctx).of("send_chip")[0][1]).is_equal(
		["hold_fire", StationFixture.H2]
	)
	s.dispatch(_ev("comms_hail", s))
	assert_int(_commands(s, "comms_hail")[0]["target"]).is_equal(StationFixture.H2)
	# With nothing selected the card's own contact is the target.
	s.ctx.crew.select("", -1)
	panel.board.select(CommsFixture.MISSION)
	assert_int(panel.hail_target()).is_equal(StationFixture.H2)


# FT: FT-STN-003, FT-STN-010
# Marks and pings address the contact a card is about: the card under the pointer, the open
# card, the selected card on a controller; a card about nobody gives nothing.
func test_item_at_gives_the_cards_contact() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.board.size = BOARD_SIZE
	var local: Callable = func(id: int) -> Vector2:
		return (
			panel.board.card_rect(id).get_center()
			+ panel.board.global_position
			- panel.global_position
		)
	assert_dict(panel.item_at(local.call(CommsFixture.MISSION))).is_equal(
		{"kind": "contact", "id": StationFixture.H2}
	)
	assert_dict(panel.item_at(local.call(CommsFixture.HAIL))).is_equal(
		{"kind": "contact", "id": StationFixture.U3}
	)
	assert_dict(panel.item_at(local.call(CommsFixture.CONTRACT))).is_empty()
	# On a controller the cursor sits on the selected card.
	panel.board.select(CommsFixture.MISSION)
	assert_dict(panel.item_at(panel.cursor_pos())).is_equal(
		{"kind": "contact", "id": StationFixture.H2}
	)
	# A ping from the screen goes to the contact, a mark attaches to it.
	assert_bool(s.dispatch(_ev("mark", s, "pad"))).is_true()
	assert_int(StationFixture.sent(s.ctx).of("place_mark")[0][1][2]).is_equal(StationFixture.H2)
	s.dispatch(_ev("ping", s, "pad"))
	assert_array(StationFixture.sent(s.ctx).of("ping")[0][1].slice(0, 2)).is_equal(
		["contact", StationFixture.H2]
	)


# FT: FT-STN-009, FT-STN-005
# Every Comms intent has a handler in the panel and a translation.
func test_every_comms_intent_is_handled_and_named() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	for id: String in IntentTable.ids_of("comms"):
		panel.close_overlay()
		if id != "comms_open":
			panel.open_card(CommsFixture.OFFER)
		if IntentTable.row(id)["kind"] == IntentTable.AXIS:
			assert_bool(IntentTable.defaults(id, IntentTable.PAD).is_empty()).is_false()
		else:
			var ev: Dictionary = _ev(id, s)
			ev["target"] = "comms"
			assert_bool(panel.handle_intent(ev)).override_failure_message(id).is_true()
		assert_str(TranslationServer.translate(IntentTable.label_key(id))).is_not_equal(
			IntentTable.label_key(id)
		)


# FT: FT-COM-008
# A narrow board (a phone) shows one column and a swipe changes it; a swipe down closes the
# overlay and a tap outside it too.
func test_touch_swipes() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = _comms(s)
	panel.board.size = Vector2(400, 600)
	assert_bool(panel.board.narrow()).is_true()
	assert_int(panel.board.column_shown()).is_equal(0)
	var swipe: Callable = func(c: Control, from: Vector2, to: Vector2) -> void:
		var down: InputEventMouseButton = InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.position = from
		c._gui_input(down)
		var up: InputEventMouseButton = InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = to
		c._gui_input(up)
	swipe.call(panel.board, Vector2(300, 200), Vector2(100, 200))
	assert_int(panel.board.column_shown()).is_equal(1)
	assert_int(panel.board.selected).is_equal(CommsFixture.CONTRACT)
	panel.overlay.size = Vector2(800, 600)
	panel.open_card(CommsFixture.OFFER)
	swipe.call(panel.overlay, Vector2(400, 100), Vector2(400, 300))
	assert_bool(panel.overlay.visible).is_false()
	panel.open_card(CommsFixture.OFFER)
	_click(panel.overlay, Vector2(2, 2))
	assert_bool(panel.overlay.visible).is_false()


# FT: FT-CPT-004, FT-CPT-005, FT-JNT-004
# The Captain's list and the Comms half of the joint views show the real cards: missions and
# contracts for the Captain, every live card in a Comms view's docked list; a settled card is
# gone from both.
func test_the_lists_show_the_real_cards() -> void:
	var cap: StationScreen = await _screen(StationViews.CAPTAIN)
	var captain: CaptainPanel = cap.panels[0] as CaptainPanel
	await get_tree().process_frame
	assert_int(captain.cards.card_at(Vector2(10.0, CardList.HEADER_HEIGHT + 5.0))).is_equal(0)
	(
		assert_int(
			captain.cards.card_at(Vector2(10.0, CardList.HEADER_HEIGHT + CardList.ROW_HEIGHT + 5.0))
		)
		. is_equal(1)
	)
	(
		assert_int(
			captain.cards.card_at(
				Vector2(10.0, CardList.HEADER_HEIGHT + 2.0 * CardList.ROW_HEIGHT + 5.0)
			)
		)
		. is_equal(-1)
	)
	var parley: StationScreen = await _screen("parley")
	parley.focus(parley.stations.find("weapons"))
	var panel: CommsPanel = _comms(parley)
	panel.refresh(true)
	assert_bool(panel.list.visible).is_true()
	assert_int(CardList.rows(parley.ctx.view).size()).is_equal(4)
	var blk: Dictionary = CommsFixture.block()
	blk["cards"][CommsFixture.MISSION]["state"] = 3
	CommsFixture.install(parley.ctx, blk)
	assert_int(CardList.rows(parley.ctx.view).size()).is_equal(3)
	(
		assert_int(CardList.rows(parley.ctx.view, [CardList.MISSION, CardList.CONTRACT]).size())
		. is_equal(1)
	)
