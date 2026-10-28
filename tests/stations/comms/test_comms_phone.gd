extends GdUnitTestSuite
## Comms on a phone (#28 follow-up, D287, design 2.6): the five rail buttons stay put while
## the board's columns, the reputation and the crew actions are pages; every action is
## within reach of rest, every target keeps the touch rules on every page and with the
## conversation open, and the rail sends what the keys send.
# FT: FT-STN-005, FT-COM-008

const Reach = preload("res://tests/stations/wr/phone_reach.gd")

const SETTINGS: String = "user://test_comms_phone.cfg"
const SIDEWAYS: Vector2i = Vector2i(844, 390)
const UPRIGHT: Vector2i = Vector2i(390, 844)
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## The fixture's block with a conversation on the mission too, so Claim has a card at rest.
static func _block() -> Dictionary:
	var blk: Dictionary = CommsFixture.block()
	blk["cards"][CommsFixture.MISSION]["conv"] = true
	blk["cards"][CommsFixture.MISSION]["open"] = true
	return blk


func _screen(size: Vector2i, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context("comms", SETTINGS)
	CommsFixture.install(ctx, _block())
	ctx.crew.select("contact", StationFixture.H2)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	await _frames(4)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _drop(s: StationScreen) -> void:
	s.get_parent().remove_child(s)
	s.free()


## A finger's tap at `at` (the control's own coordinates) on a drawn control.
func _tap(c: Control, at: Vector2) -> void:
	for down: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		c._gui_input(ev)


func _assert_clean(root: Control, what: String) -> void:
	var report: Dictionary = TapAudit.check(root)
	assert_array(report["targets"]).override_failure_message(what + ": no targets").is_not_empty()
	for k: String in AUDIT:
		(
			assert_array(report[k])
			. override_failure_message("%s %s: %s" % [what, k, report[k]])
			. is_empty()
		)


## Taps card `id` on its page from rest: the tab when it is not the first page, then the
## card. Returns the taps.
func _open_from_rest(s: StationScreen, id: int) -> int:
	var p: CommsPanel = s.focused_panel()
	Reach.rest(s)
	var taps: int = 0
	var col: int = p.board.column_of(id)
	if col != CommsPanel.Page.MISSIONS:
		Reach.strip(s).tab(col).pressed.emit()
		taps += 1
	await _frames(2)
	var r: Rect2 = p.board.card_rect(id)
	assert_bool(r.size != Vector2.ZERO).override_failure_message("card %d hidden" % id).is_true()
	var bottom: float = (p.board.get_global_transform() * r.end).y
	assert_float(bottom).is_less_equal(SafeArea.tap_bottom(s) + 0.5)
	_tap(p.board, r.get_center())
	await _frames(2)
	assert_int(p.overlay.card_id).is_equal(id)
	return taps + 1


## Taps the first shown overlay row of `kind`, paging with › when none shows; the taps.
func _tap_row(p: CommsPanel, kind: String) -> int:
	var o: CommsOverlay = p.overlay
	var taps: int = 0
	for _turn: int in 4:
		for i: int in o.rows().size():
			if o.rows()[i]["kind"] == kind and o._rects[i].size != Vector2.ZERO:
				_tap(o, o._rects[i].get_center())
				return taps + 1
		o.next_button.pressed.emit()
		taps += 1
	return 99


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


# The design's reachability table (2.6), walked on a phone either way up.
func _walk_table(size: Vector2i, insets: Array) -> void:
	var s: StationScreen = await _screen(size, insets)
	var p: CommsPanel = s.focused_panel()
	var log: StationFixture.RecordingClient = StationFixture.sent(s.ctx)
	var what: String = "%s" % size
	# The rail: 1 tap each from rest, the mission card and H2 (a contact) selected.
	var rail: Array = [
		["Comms_hail", "command", "comms_hail"],
		["Comms_accept", "command", "comms_accept"],
		["Comms_decline", "command", "comms_decline"],
		["Comms_claim", "claim", ""],
		["Comms_hold_fire", "send_chip", ""],
	]
	for r: Array in rail:
		log.sent.clear()
		var got: Dictionary = Reach.walk(s, {"control": r[0], "taps": 1})
		assert_str(got["error"]).override_failure_message(what + " " + r[0]).is_empty()
		var sent: Array = log.of(r[1])
		(
			assert_int(sent.size())
			. override_failure_message("%s %s: %s" % [what, r[0], log.sent])
			. is_equal(1)
		)
		if r[2] != "":
			assert_str(sent[0][1][0]["kind"]).is_equal(r[2])
	# Next column: the tab, 1 tap.
	Reach.rest(s)
	Reach.strip(s).tab(CommsPanel.Page.CONTRACTS).pressed.emit()
	assert_int(p.board.column_shown()).is_equal(CommsPanel.Page.CONTRACTS)
	assert_int(p.board.selected).is_equal(CommsFixture.CONTRACT)
	# Open a card on its page: 1 tap on the first page, 2 on another.
	assert_int(await _open_from_rest(s, CommsFixture.MISSION)).is_equal(1)
	assert_int(await _open_from_rest(s, CommsFixture.CONTRACT)).is_equal(2)
	# Close: 1 tap.
	p.overlay.close_button.pressed.emit()
	assert_int(p.overlay.card_id).is_equal(-1)
	# Reply: open the card on its page, then the reply (2).
	p.pages.current = CommsPanel.Page.HAILS
	await _frames(1)
	_tap(p.board, p.board.card_rect(CommsFixture.OFFER).get_center())
	await _frames(2)
	log.sent.clear()
	assert_int(_tap_row(p, "reply")).is_equal(1)
	assert_array(_commands(s, "comms_reply")).is_equal(
		[{"kind": "comms_reply", "card": CommsFixture.OFFER, "option": "o5"}]
	)
	# Buy while docked: the trader card, then a line (2; 3 when the list pages).
	log.sent.clear()
	var buy: int = 1 + _tap_row(p, "buy")
	assert_int(buy).override_failure_message(what).is_less_equal(3)
	assert_int(_commands(s, "comms_trade").size()).is_equal(1)
	p.overlay.close_button.pressed.emit()
	# Ping on the Crew page: 2 taps.
	log.sent.clear()
	var ping: Dictionary = Reach.walk(
		s,
		{
			"page": CommsPanel.Page.CREW,
			"control": func(_s: StationScreen) -> BaseButton: return p.crew_page.button("ping"),
		}
	)
	assert_str(ping["error"]).is_empty()
	assert_int(ping["taps"]).is_equal(2)
	assert_int(log.of("ping").size()).is_equal(1)
	# Reputation: the Rep tab, 1 tap.
	Reach.rest(s)
	Reach.strip(s).tab(CommsPanel.Page.REP).pressed.emit()
	await _frames(2)
	assert_bool(p.rep_view.is_visible_in_tree()).is_true()
	assert_bool(p.board.is_visible_in_tree()).is_false()
	var texts: PackedStringArray = PackedStringArray()
	for l: Label in p.rep_view.get_children():
		texts.append(l.text)
	assert_str(" | ".join(texts)).contains("F1 +12").contains("F2 -2").contains("Kappa")
	_drop(s)


# FT: FT-STN-005, FT-COM-002, FT-COM-003, FT-COM-004, FT-COM-005, FT-COM-006, FT-COM-007
func test_reachability_on_its_side() -> void:
	await _walk_table(SIDEWAYS, LANDSCAPE)


# FT: FT-STN-005, FT-COM-002, FT-COM-003, FT-COM-004, FT-COM-005, FT-COM-006, FT-COM-007
func test_reachability_upright() -> void:
	await _walk_table(UPRIGHT, PORTRAIT)


# FT: FT-STN-005
# Every page keeps the touch rules either way up; the rail never pages away. (Upright with
# the "Turn sideways" banner dismissed: the frame's selection chip sits 4 px under its ×.)
func test_every_page_keeps_the_touch_rules() -> void:
	RotateBanner.dismissed_here = true
	for c: Array in [[SIDEWAYS, LANDSCAPE], [UPRIGHT, PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], c[1])
		var p: CommsPanel = s.focused_panel()
		assert_int(p.pages.count()).is_equal(5)
		for i: int in p.pages.count():
			p.pages.current = i
			await _frames(3)
			var what: String = "%s page %d" % [c[0], i]
			_assert_clean(s, what)
			for b: Button in p._buttons.values():
				assert_bool(b.is_visible_in_tree()).override_failure_message(what).is_true()
				assert_float(b.size.y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
		_drop(s)


# FT: FT-STN-005, FT-COM-004, FT-COM-007
# The conversation: rows 48 px in two columns on its side, ‹ › paging a long trade list, a
# 48 px Close; on its side it covers the board and the radar column and leaves the rail live.
func test_overlay_keeps_the_touch_rules() -> void:
	for c: Array in [[SIDEWAYS, LANDSCAPE], [UPRIGHT, PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], c[1])
		var p: CommsPanel = s.focused_panel()
		var o: CommsOverlay = p.overlay
		p.open_card(CommsFixture.OFFER)
		await _frames(3)
		_assert_clean(p, "%s trade" % c[0])
		assert_bool(o.close_button.is_visible_in_tree()).is_true()
		for i: int in o.rows().size():
			if o._rects[i].size != Vector2.ZERO:
				assert_float(o._rects[i].size.y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
		if c[0] == SIDEWAYS:
			# Two columns; the list pages; the rail beside it stays live.
			assert_float(o._rects[1].position.x).is_greater(o._rects[0].end.x)
			var box: Rect2 = o.get_global_rect()
			assert_float(box.position.x).is_greater_equal(
				p._buttons["hail"].get_global_rect().end.x + UiTheme.TOUCH_GAP
			)
			assert_float(box.end.x).is_greater(s.radar.get_global_rect().position.x)
			assert_bool(o.next_button.is_visible_in_tree()).is_true()
			p._buttons["hail"].pressed.emit()
			assert_int(_commands(s, "comms_hail").size()).is_equal(1)
			assert_int(o.card_id).is_equal(CommsFixture.OFFER)
		if o.next_button.is_visible_in_tree():
			assert_bool(o.prev_button.disabled).is_true()
			o.next_button.pressed.emit()
			await _frames(2)
			assert_bool(o.prev_button.disabled).is_false()
			_assert_clean(p, "%s trade, next page" % c[0])
		p.open_card(CommsFixture.HAIL)
		await _frames(3)
		_assert_clean(p, "%s conversation" % c[0])
		_drop(s)


# FT: FT-STN-005, FT-COM-002, FT-COM-003, FT-COM-006, FT-STN-010
# Each rail button sends exactly what its key sends.
func test_rail_buttons_send_the_key_intents() -> void:
	var cases: Array = [
		["hail", {"id": "comms_hail", "target": "comms"}],
		["accept", {"id": "accept", "target": "screen"}],
		["decline", {"id": "decline", "target": "screen"}],
		["claim", {"id": "claim", "target": "screen"}],
		["hold_fire", {"id": "request", "target": "screen"}],
	]
	for c: Array in cases:
		var touch: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
		(touch.focused_panel() as CommsPanel)._buttons[c[0]].pressed.emit()
		var keys: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
		var ev: Dictionary = c[1].duplicate()
		ev.merge({"pressed": true, "device": IntentTable.KBM})
		keys.dispatch(ev)
		var by_touch: Array = StationFixture.sent(touch.ctx).sent
		assert_array(by_touch).override_failure_message("%s: %s" % [c[0], by_touch]).is_not_empty()
		assert_array(by_touch).is_equal(StationFixture.sent(keys.ctx).sent)
		_drop(touch)
		_drop(keys)


# FT: FT-SPA-016, FT-COM-008
# A long-press on a card pings the card's contact (H2 for the rescue mission).
func test_long_press_on_a_card_pings_its_contact() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: CommsPanel = s.focused_panel()
	s.ctx.crew.select("contact", StationFixture.U3)
	var r: Rect2 = p.board.card_rect(CommsFixture.MISSION)
	s.ping_at(p.board.get_global_transform() * r.get_center())
	var pings: Array = StationFixture.sent(s.ctx).of("ping")
	assert_int(pings.size()).is_equal(1)
	assert_array([pings[0][1][0], pings[0][1][1]]).is_equal(["contact", StationFixture.H2])
	_drop(s)


# FT: FT-COM-002, FT-COM-008
# The pages follow the keys and a swipe; the Hails tab shows a dot while a hail waits.
func test_pages_follow_the_selection_and_badge_a_waiting_hail() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: CommsPanel = s.focused_panel()
	assert_bool(p.pages.badge(CommsPanel.Page.HAILS)).is_true()
	s.dispatch({"id": "comms_next_column", "target": "comms", "pressed": true})
	assert_int(p.pages.current).is_equal(CommsPanel.Page.CONTRACTS)
	assert_int(p.board.column_shown()).is_equal(CommsPanel.Page.CONTRACTS)
	p.board._swipe(1)
	assert_int(p.pages.current).is_equal(CommsPanel.Page.HAILS)
	# A tab closes an open conversation.
	p.open_card(CommsFixture.OFFER)
	Reach.strip(s).tab(CommsPanel.Page.MISSIONS).pressed.emit()
	assert_int(p.overlay.card_id).is_equal(-1)
	var blk: Dictionary = _block()
	blk["cards"][CommsFixture.HAIL]["state"] = 1
	CommsFixture.install(s.ctx, blk)
	p.refresh(true)
	assert_bool(p.pages.badge(CommsPanel.Page.HAILS)).is_false()
	_drop(s)


# FT: FT-STN-005, FT-COM-008
# Tablets and desktops keep the three-column board with its header and footer; a phone
# turned into a desktop window gets it back.
func test_desktop_keeps_the_board() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: CommsPanel = s.focused_panel()
	p.pages.current = CommsPanel.Page.REP
	await _frames(2)
	SafeArea.simulate([])
	(s.get_parent() as SubViewport).size = Vector2i(1280, 720)
	await _frames(4)
	assert_int(p.board.page_column).is_equal(-1)
	assert_bool(p.board.is_visible_in_tree()).is_true()
	assert_bool(p.rep_view.visible or p.crew_page.visible).is_false()
	assert_bool(p._bar.is_visible_in_tree()).is_true()
	assert_bool(p.overlay.top_level).is_false()
	assert_bool(p._top_gap.visible or p._foot_gap.visible).is_false()
	_drop(s)


# FT: FT-STN-012
# The touch help: one entry per page titled as its tab, the rail on the first page only,
# each rail box where the button sits on a phone on its side.
func test_touch_help_matches_the_pages() -> void:
	var help: Array = CommsPanel.touch_help()
	assert_int(help.size()).is_equal(5)
	var titles: Array[String] = CommsPanel.page_titles()
	for i: int in help.size():
		assert_str(help[i]["page"]).is_equal(titles[i])
		assert_array(help[i]["boxes"]).is_not_empty()
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: CommsPanel = s.focused_panel()
	var ids: Array[String] = ["hail", "accept", "decline", "claim", "hold_fire"]
	for i: int in ids.size():
		var box: Rect2 = help[0]["boxes"][i][0]
		var real: Rect2 = p._buttons[ids[i]].get_global_rect()
		assert_vector(box.position).is_equal_approx(real.position, Vector2.ONE)
		assert_vector(box.size).is_equal_approx(real.size, Vector2.ONE)
	var card: Rect2 = help[0]["boxes"][5][0]
	var drawn: Rect2 = p.board.card_rect(CommsFixture.MISSION)
	drawn.position = p.board.get_global_transform() * drawn.position
	assert_vector(card.position).is_equal_approx(drawn.position, Vector2.ONE)
	for e: Dictionary in help.slice(1):
		for b: Array in e["boxes"]:
			assert_bool((b[0] as Rect2).intersects(Rect2(47, 64, 136, 300))).is_false()
	_drop(s)
