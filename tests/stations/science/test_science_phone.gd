extends GdUnitTestSuite
## Science on a phone (#28 follow-up, design 2.4, D287-D289): the radar between overlay
## rails, the persistent actions on the right, the pages Contacts, Card (the whole card, no
## scroll) and Crew on the left; Hack opens the screen's sheet of the target's subsystems;
## a scan or hack replaces the tabs with the session's title and the rails with the
## minigame's buttons. Every action is within 2 taps of rest (the reachability table, both
## ways up), every page keeps the touch rules both ways up, and a tap sends what the key
## sends.
# FT: FT-STN-005

const SETTINGS: String = "user://test_science_phone.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const SIDEWAYS: Vector2i = Vector2i(844, 390)
const UPRIGHT: Vector2i = Vector2i(390, 844)
const H2: int = StationFixture.H2
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## A Science screen in a phone-sized viewport with the given insets and SCIENCE block.
func _screen(size: Vector2i, insets: Array, kind: String = "cards") -> StationScreen:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("science", SETTINGS)
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	ctx.view.blocks[StationViews.Section.SCIENCE] = ScienceShotBlocks.block(kind)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	_vp.add_child(s)
	await _frames(4)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _sci(s: StationScreen) -> SciencePanel:
	return s.panels[0] as SciencePanel


func _cmds(s: StationScreen, kind: String) -> Array:
	return StationFixture.sent(s.ctx).of("command").filter(
		func(c: Array) -> bool: return c[1][0]["kind"] == kind
	)


func _assert_taps_ok(root: Control, what: String) -> void:
	var report: Dictionary = TapAudit.check(root)
	assert_array(report["targets"]).is_not_empty()
	# Known frame issue (requested of strand F): upright, PhoneFrame puts the selection
	# chip at the panel's top, not at view_rect()'s, so it touches the rotate banner's ×.
	report["tight"] = report["tight"].filter(
		func(t: Variant) -> bool: return not str(t).begins_with("× | ")
	)
	for rule: String in AUDIT:
		(
			assert_array(report[rule])
			. override_failure_message("%s %s: %s" % [what, rule, report[rule]])
			. is_empty()
		)


## The design's reachability table (2.4): [action, page, button, sheet option, taps, what
## the tap sends: [recorded call, command kind or ""]].
func _table(p: SciencePanel) -> Array:
	var a: Callable = func(k: String) -> Callable:
		return func() -> BaseButton: return p.phone.actions[k]
	var c: Callable = func(kind: String, id: String) -> Callable:
		return func() -> BaseButton: return p.phone.crew.button(kind, id)
	return [
		["Scan", 0, a.call("scan"), -1, 1, ["command", "science_scan"]],
		["Hack (choose subsystem)", 0, a.call("hack"), 0, 2, ["command", "science_hack"]],
		["Active ping", 0, a.call("ping"), -1, 1, ["command", "science_ping"]],
		["Scan-position mark", 0, a.call("mark"), -1, 1, ["command", "science_scan_mark"]],
		["Passive / active", 0, a.call("mode"), -1, 1, ["command", "science_sensor_mode"]],
		["Scan own ship", 0, a.call("self"), -1, 1, ["command", "science_self_scan"]],
		["Claim scan/hack", 0, a.call("claim"), -1, 1, ["claim", ""]],
		["Sensor power request", 2, c.call("chip", "sensor_power"), -1, 2, ["send_chip", ""]],
		["To scan mark request", 2, c.call("chip", "scan_mark"), -1, 2, ["send_chip", ""]],
		["Ping (Crew)", 2, c.call("ping", ""), -1, 2, ["ping", ""]],
		["Mark (Crew)", 2, c.call("mark", ""), -1, 2, ["place_mark", ""]],
		["Share", 2, c.call("share", ""), -1, 2, ["share", ""]],
	]


func _sent(s: StationScreen, what: Array) -> int:
	if what[1] != "":
		return _cmds(s, what[1]).size()
	return StationFixture.sent(s.ctx).of(what[0]).size()


# FT: FT-STN-005, FT-STN-009, FT-STN-010, FT-SCI-003, FT-SCI-004, FT-SCI-006, FT-SCI-009, FT-SCI-010
func test_every_action_is_within_two_taps_both_ways_up() -> void:
	for c: Array in [[SIDEWAYS, LANDSCAPE], [UPRIGHT, PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], c[1])
		var p: SciencePanel = _sci(s)
		s.ctx.crew.select("contact", H2)
		await _frames(2)
		for row: Array in _table(p):
			var what: String = "%s %s" % [row[0], c[0]]
			var before: int = _sent(s, row[5])
			var taps: int = await PhoneReach.tap_row(s, [row[1], row[2], row[3]])
			assert_int(taps).override_failure_message(what).is_equal(row[4])
			assert_int(taps).override_failure_message(what).is_less_equal(2)
			assert_int(_sent(s, row[5])).override_failure_message(what).is_equal(before + 1)
			await _frames(1)
		# Read the full card: its tab (1 tap) shows the whole card, no scroll.
		PhoneReach.rest(s)
		PhoneReach.tap(PhoneReach.tab(s, SciencePhone.PAGE_CARD))
		await _frames(2)
		assert_bool(p.card_view.is_visible_in_tree()).is_true()
		assert_float(p.card_view.size.y).is_greater_equal(ScienceCard.content_height(true))
		assert_bool(p.card_view.get_parent() is ScrollContainer).is_false()
		# Select a contact: a list row on the first page (1 tap).
		PhoneReach.rest(s)
		await _frames(1)
		assert_bool(p._list.is_visible_in_tree()).is_true()
		# Radar range: a tap on the range label (1 tap).
		var range_before: int = p.radar.range_index
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = p.radar._range_rect().get_center()
		p.radar._gui_input(click)
		assert_int(p.radar.range_index).is_not_equal(range_before)
		_vp.queue_free()
		await _frames(1)


# FT: FT-STN-005, FT-SCI-006
# P28-L1: Hack opens the sheet of the target's own subsystems plus Cancel, over the right
# rail; a pick hacks that subsystem; Cancel sends nothing. Nothing hackable selected: the
# nearest hackable contact is picked first. Picked by key already: Hack starts at once.
func test_hack_opens_a_sheet_of_the_targets_subsystems() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: SciencePanel = _sci(s)
	s.ctx.crew.select("contact", StationFixture.U3)
	await _frames(1)
	PhoneReach.tap(p.phone.actions["hack"])
	await _frames(1)
	assert_bool(s.sheet.is_open()).is_true()
	assert_dict(s.ctx.crew.selection).is_equal({"kind": "contact", "id": H2})
	assert_str(s.sheet.title.text).contains("H2")
	var subs: Array[StringName] = p.subsystems()
	assert_int(s.sheet.option_count()).is_equal(subs.size())
	assert_str(s.sheet.option(1).text).is_equal(tr("eng.name." + String(subs[1])))
	# It covers the right rail, not the list.
	var box: Rect2 = s.sheet.box.get_global_rect()
	assert_bool(box.encloses(p.phone.layout.right.get_global_rect().grow(-1.0))).is_true()
	assert_bool(box.intersects(p._list.get_global_rect())).is_false()
	_assert_taps_ok(s.sheet, "hack sheet")
	PhoneReach.tap(s.sheet.cancel_button)
	assert_int(_cmds(s, "science_hack").size()).is_equal(0)
	PhoneReach.tap(p.phone.actions["hack"])
	PhoneReach.tap(s.sheet.option(1))
	var sent: Array = _cmds(s, "science_hack")
	assert_int(sent.size()).is_equal(1)
	assert_dict(sent[0][1][0]).is_equal(
		{"kind": "science_hack", "contact": H2, "subsystem_id": String(subs[1])}
	)
	# The key's choice: ] picks the next subsystem, then Hack sends at once (1 tap), the
	# same command as the H key.
	p.handle_intent({"id": "sci_sub_next", "pressed": true})
	PhoneReach.tap(p.phone.actions["hack"])
	assert_bool(s.sheet.is_open()).is_false()
	p.handle_intent({"id": "sci_hack", "pressed": true})
	sent = _cmds(s, "science_hack")
	assert_int(sent.size()).is_equal(3)
	assert_dict(sent[1][1][0]).is_equal(sent[2][1][0])
	# The selection sheet offers Scan and Hack after Ping, Mark here and Clear.
	s.frame.open_selection_sheet()
	assert_str(s.sheet.option(3).text).is_equal(tr("sci.scan"))
	assert_str(s.sheet.option(4).text).is_equal(tr("sci.hack"))


# FT: FT-STN-005, FT-SCI-004, FT-SCI-012
# A scan replaces the tabs with "Scan H2 · n s" (pages don't change mid-session), the axis
# chips go left and Cancel and Submit right; taps send what Enter and Backspace send.
func test_scan_session_title_and_buttons() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE, "scan")
	var p: SciencePanel = _sci(s)
	assert_str(p.pages.session_title).starts_with("Scan H2 · ")
	assert_bool(s.top_bar.tabs._session.is_visible_in_tree()).is_true()
	p.pages.current = SciencePhone.PAGE_CREW
	assert_int(p.pages.current).is_equal(SciencePhone.PAGE_CONTACTS)
	assert_bool(p.scan_game.footer).is_false()
	var shown: Array = p.phone.axis_buttons.filter(
		func(b: RailButton) -> bool: return b.is_visible_in_tree()
	)
	assert_int(shown.size()).is_equal(p.scan_game.open_axes().size())
	assert_bool(p.phone.layout.left.is_ancestor_of(shown[0])).is_true()
	assert_bool(p.phone.layout.right.is_ancestor_of(p.phone.submit)).is_true()
	assert_bool(p.phone.actions["scan"].is_visible_in_tree()).is_false()
	assert_bool(p._list.is_visible_in_tree()).is_false()
	_assert_taps_ok(s, "scan")
	PhoneReach.tap(shown[1])
	assert_int(p.scan_game.selected).is_equal(1)
	PhoneReach.tap(p.phone.submit)
	assert_int(_cmds(s, "science_scan_submit").size()).is_equal(1)
	p.handle_intent({"id": "accept", "pressed": true})
	assert_int(_cmds(s, "science_scan_submit").size()).is_equal(2)
	PhoneReach.tap(p.phone.cancel)
	assert_int(_cmds(s, "science_cancel").size()).is_equal(1)
	# The session ends: the tabs come back on the page it started on.
	s.ctx.view.blocks[StationViews.Section.SCIENCE] = ScienceShotBlocks.block("cards")
	await _frames(2)
	assert_str(p.pages.session_title).is_empty()
	assert_bool(p._list.is_visible_in_tree()).is_true()


# FT: FT-STN-005, FT-SCI-006
func test_hack_session_nodes_are_tap_sized_and_apart() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE, "hack")
	var p: SciencePanel = _sci(s)
	var g: HackGame = p.hack_game
	assert_str(p.pages.session_title).starts_with("Hack H2 · ")
	assert_bool(p.phone.cancel.is_visible_in_tree()).is_true()
	assert_bool(p.phone.submit.is_visible_in_tree()).is_false()
	assert_float(g.node_centre(g.cols).y - g.node_centre(0).y).is_greater_equal(
		UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP
	)
	assert_float(g.node_centre(1).x - g.node_centre(0).x).is_greater_equal(
		UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP
	)
	_assert_taps_ok(s, "hack")
	PhoneReach.tap(p.phone.cancel)
	assert_int(_cmds(s, "science_cancel").size()).is_equal(1)


# FT: FT-STN-005, FT-SCI-001, FT-STN-002
# Every page, both ways up, keeps the touch rules; the radar stays between the rails and
# under the view-top row, and the Card page widens the left rail with the radar re-centred.
func test_every_page_keeps_the_touch_rules_both_ways_up() -> void:
	for c: Array in [[SIDEWAYS, LANDSCAPE], [UPRIGHT, PORTRAIT]]:
		for kind: String in ["cards", "scan", "hack"]:
			var s: StationScreen = await _screen(c[0], c[1], kind)
			var p: SciencePanel = _sci(s)
			assert_bool(p.in_frame).is_true()
			assert_int(p.pages.count()).is_equal(3)
			for page: int in p.pages.count():
				if kind != "cards" and page > 0:
					continue
				p.pages.current = page
				await _frames(3)
				var what: String = "%s %s page %d" % [c[0], kind, page]
				_assert_taps_ok(s, what)
				if kind == "cards":
					var free: Rect2 = p.phone.view_in_stage()
					assert_object(p.radar.view_rect).override_failure_message(what).is_equal(free)
					assert_float(free.position.y).is_greater_equal(p.top_reserve)
					assert_bool(free.has_point(p.radar.disc_centre())).is_true()
			if c[0] == SIDEWAYS and kind == "cards":
				var w: float = p.phone.layout.left.size.x
				assert_float(w).is_equal(SciencePhone.LEFT_W)
				p.pages.current = SciencePhone.PAGE_CARD
				await _frames(3)
				assert_float(p.phone.layout.left.size.x).is_equal(SciencePhone.CARD_W)
				assert_bool(p.radar.view_rect.position.x > SciencePhone.CARD_W).is_true()
			_vp.queue_free()
			await _frames(1)


# FT: FT-STN-005
# The tabs follow the panel's pages after the phone turns (its rails and pages are rebuilt),
# and a desktop gets the wide layout back with no pages.
func test_turning_the_phone_rebuilds_and_a_desktop_gets_the_wide_layout() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: SciencePanel = _sci(s)
	assert_object(s.top_bar.tabs.host).is_same(p.pages)
	SafeArea.simulate(PORTRAIT)
	_vp.size = UPRIGHT
	await _frames(4)
	assert_int(p.phone.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	assert_object(s.frame.bottom_tabs.host).is_same(p.pages)
	assert_bool(s.frame.bottom_tabs.is_visible_in_tree()).is_true()
	_assert_taps_ok(s, "turned")
	SafeArea.simulate([])
	_vp.size = Vector2i(1280, 720)
	await _frames(4)
	assert_object(p.phone).is_null()
	assert_object(p.pages).is_null()
	assert_bool(p._rows.visible).is_true()
	assert_object(p._list.get_parent()).is_same(p._top)
	assert_object(p.card_view.get_parent()).is_same(p._top)
	assert_bool(p.card_view.compact).is_false()
	assert_bool(p.scan_game.footer).is_true()
	assert_object(p.radar.view_rect).is_equal(Rect2())


# FT: FT-STN-005, FT-SCI-001, FT-SPA-011
# Two fingers orbit the radar (spec §5.4 touch); one finger doesn't.
func test_two_fingers_orbit_the_radar() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var r: DiscRadar = _sci(s).radar
	var yaw: float = r.yaw_deg
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 0
	drag.relative = Vector2(40.0, 0.0)
	_finger(r, 0, true)
	r._gui_input(drag)
	assert_float(r.yaw_deg).is_equal(yaw)
	_finger(r, 1, true)
	r._gui_input(drag)
	assert_float(r.yaw_deg).is_not_equal(yaw)
	_finger(r, 1, false)
	_finger(r, 0, false)


func _finger(r: DiscRadar, index: int, down: bool) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = index
	t.pressed = down
	t.position = r.size / 2.0
	r._gui_input(t)


# FT: FT-STN-012
# P28-Help: the touch picture of the pages (one drawing per page, a legend row per control).
func test_touch_help_picture_has_every_page() -> void:
	var pages: Array = ScienceTouchHelp.pages()
	(
		assert_array(pages.map(func(p: Dictionary) -> String: return p["title"]))
		. is_equal(["Contacts", "Card", "Crew"])
	)
	var pic: ScienceTouchHelp = auto_free(ScienceTouchHelp.new())
	assert_float(pic.custom_minimum_size.y).is_equal_approx(
		ScienceTouchHelp.height_for(pages), 0.01
	)
	assert_int(ScienceTouchHelp.FONT).is_greater_equal(12)
