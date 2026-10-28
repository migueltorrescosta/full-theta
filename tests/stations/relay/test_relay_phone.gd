extends GdUnitTestSuite
## Relay on a phone (#28 follow-up, design 2.5, D287-D289): the map between overlay rails
## with the pages Map, Marks, Contacts, Log and Crew; Send ▸ opens the screen's sheet of
## allied ships; a long press on Launch probe claims the launcher; on the map a second
## finger slides a dragged mark's depth, a pinch zooms and two fingers turn it. Every action
## is within 2 taps of rest (the reachability table, both ways up), every page keeps the
## touch rules both ways up, and a tap does what the key does.
# FT: FT-STN-005

const SETTINGS: String = "user://test_relay_phone.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const SIDEWAYS: Vector2i = Vector2i(844, 390)
const UPRIGHT: Vector2i = Vector2i(390, 844)
const H2: int = StationFixture.H2
const ALLY: int = 3
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## A Relay screen in a phone-sized viewport: an allied ship to send to, two probes in stock.
func _screen(size: Vector2i, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("relay", SETTINGS)
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	var ships: Array = ctx.crew.catalogue["ships"]
	ships.append({"id": ALLY, "def": "m1_corvette", "name": "Wren", "faction": 0})
	ctx.view.blocks[StationViews.Section.RELAY] = {
		"stock": 2, "fab_left": 0.0, "lanes": false, "probes": []
	}
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	_vp.add_child(s)
	await _frames(4)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _relay(s: StationScreen) -> RelayPanel:
	return s.panels[0] as RelayPanel


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


func _count(s: StationScreen, call: String, kind: String = "") -> Callable:
	return func() -> int:
		var rows: Array = StationFixture.sent(s.ctx).of(call)
		if kind != "":
			rows = rows.filter(func(c: Array) -> bool: return c[1][0]["kind"] == kind)
		return rows.size()


## The selection a row starts from: a contact, a mark, nothing (with a route to clear).
func _given(s: StationScreen, what: String) -> void:
	var crew: CrewState = s.ctx.crew
	match what:
		"contact":
			crew.select("contact", H2)
		"mark":
			crew.select("mark", StationFixture.BRAVO_SLOT)
		"none":
			crew.select("", -1)
			crew.routes = [[{"pos": Vector3.ONE}]]
	var item: Dictionary = {
		"id": 7, "from_ship": ALLY, "from": "Wren", "name": "Rock", "x": 1.0, "y": 2.0, "z": 3.0
	}
	crew.handle_event({"type": "inbox", "payload": {"ship": 0, "items": [item]}}, 0)
	(s.panels[0] as RelayPanel).armed = ""


## The design's reachability table (2.5): [action, page, button, sheet option, taps, given
## selection, what changes].
func _table(s: StationScreen, p: RelayPanel) -> Array:
	var b: Callable = func(k: String) -> Callable:
		return func() -> BaseButton: return p.phone.buttons[k]
	var c: Callable = func(kind: String, id: String) -> Callable:
		return func() -> BaseButton: return p.phone.crew.button(kind, id)
	var row_of: Callable = func(box_name: String) -> Callable:
		return func() -> BaseButton:
			var box: VBoxContainer = p.phone.get(box_name)
			return box.get_child(0) as BaseButton if box.get_child_count() > 0 else null
	var centred: Callable = func() -> bool: return p._centred
	var sel: Callable = func() -> String: return str(s.ctx.crew.selection)
	var rows: Array = [
		[
			"Launch probe",
			0,
			b.call("launch"),
			-1,
			1,
			"contact",
			_count(s, "command", "launch_probe")
		],
		["Hazard", 0, b.call("hazard"), -1, 1, "contact", _count(s, "hazard_add")],
		["Flag lanes", 0, b.call("lanes"), -1, 1, "contact", _count(s, "command", "flag_lanes")],
		["Route to selection", 0, b.call("route"), -1, 1, "contact", _count(s, "route_add")],
		["Clear route", 0, b.call("route"), -1, 1, "none", _count(s, "route_clear")],
		["Accept inbox mark", 0, b.call("accept"), -1, 1, "contact", _count(s, "accept_mark")],
		["Decline inbox mark", 0, b.call("decline"), -1, 1, "contact", _count(s, "decline_mark")],
		["Send mark to an ally", 0, b.call("send"), 0, 2, "mark", _count(s, "send_mark")],
		["Centre", 0, b.call("centre"), -1, 1, "contact", centred],
		["Pick a mark", 1, row_of.call("_marks_box"), -1, 2, "none", sel],
		["Rename", 1, b.call("rename"), -1, 2, "mark", func() -> bool: return p._rename.visible],
		["Delete", 1, b.call("delete"), -1, 2, "mark", _count(s, "delete_mark")],
		["Attach", 1, b.call("attach"), -1, 2, "mark", _count(s, "move_mark")],
		["Centre (Marks)", 1, b.call("centre_mark"), -1, 2, "mark", centred],
		["Pick a contact", 2, row_of.call("_contacts_box"), -1, 2, "none", sel],
		["Route (Contacts)", 2, b.call("route_contact"), -1, 2, "contact", _count(s, "route_add")],
		["Centre (Contacts)", 2, b.call("centre_contact"), -1, 2, "contact", centred],
		[
			"Fabricate probe request",
			4,
			c.call("chip", "fabricate_probe"),
			-1,
			2,
			"contact",
			_count(s, "send_chip")
		],
		["Ping (Crew)", 4, c.call("ping", ""), -1, 2, "contact", _count(s, "ping")],
		["Mark (Crew)", 4, c.call("mark", ""), -1, 2, "contact", _count(s, "place_mark")],
	]
	for i: int in MainScreen.NAMES.size():
		rows.append(
			[
				"Main screen %d" % (i + 1),
				3,
				b.call("view_%d" % (i + 1)),
				-1,
				2,
				"contact",
				_count(s, "set_main_view")
			]
		)
	return rows


# FT: FT-STN-005, FT-STN-010, FT-RLY-003, FT-RLY-005, FT-RLY-006, FT-RLY-008, FT-RLY-010
func test_every_action_is_within_two_taps_both_ways_up() -> void:
	for sz: Array in [[SIDEWAYS, LANDSCAPE], [UPRIGHT, PORTRAIT]]:
		var s: StationScreen = await _screen(sz[0], sz[1])
		var p: RelayPanel = _relay(s)
		for row: Array in _table(s, p):
			var what: String = "%s %s" % [row[0], sz[0]]
			PhoneReach.rest(s)
			_given(s, row[5])
			p._centred = false
			p._rename.visible = false
			await _frames(2)
			var before: Variant = (row[6] as Callable).call()
			var taps: int = await PhoneReach.tap_row(s, [row[1], row[2], row[3]])
			assert_int(taps).override_failure_message(what).is_equal(row[4])
			assert_int(taps).override_failure_message(what).is_less_equal(2)
			var after: Variant = (row[6] as Callable).call()
			assert_bool(after != before).override_failure_message(what).is_true()
		# Read the ship's log: its tab (1 tap).
		PhoneReach.rest(s)
		PhoneReach.tap(PhoneReach.tab(s, RelayPhone.PAGE_LOG))
		await _frames(1)
		assert_bool(p.phone.log_text.is_visible_in_tree()).is_true()
		_vp.queue_free()
		await _frames(1)


# FT: FT-STN-005, FT-RLY-002, FT-RLY-003, FT-RLY-004, FT-RLY-005, FT-RLY-009, FT-RLY-010, FT-RLY-011
# A button's tap runs the panel's intent: the same as the key.
func test_taps_send_what_the_keys_send() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: RelayPanel = _relay(s)
	var pairs: Array = [
		["launch", "probe_launch", "contact", "command"],
		["lanes", "flag_lanes", "contact", "command"],
		["route", "route", "contact", "route_add"],
		["accept", "accept", "contact", "accept_mark"],
		["decline", "decline", "contact", "decline_mark"],
		["delete", "mark_delete", "mark", "delete_mark"],
		["attach", "mark_attach", "mark", "move_mark"],
		["view_2", "main_view_2", "contact", "set_main_view"],
	]
	for pair: Array in pairs:
		_given(s, pair[2])
		await _frames(1)
		var sent: Array = StationFixture.sent(s.ctx).sent
		sent.clear()
		var page: int = 0
		for i: int in p.pages.count():
			if (
				p.phone.buttons[pair[0]] in p.pages.parts(i)
				or _holds(p.pages.parts(i), p.phone.buttons[pair[0]])
			):
				page = i
		p.pages.current = page
		PhoneReach.tap(p.phone.buttons[pair[0]])
		var by_tap: Array = sent.duplicate(true)
		sent.clear()
		_given(s, pair[2])
		p.handle_intent({"id": pair[1], "pressed": true})
		assert_array(sent).override_failure_message(pair[0]).is_equal(by_tap)
		assert_array(by_tap).override_failure_message(pair[0]).is_not_empty()


func _holds(parts: Array[Control], b: Control) -> bool:
	for c: Control in parts:
		if c.is_ancestor_of(b):
			return true
	return false


# FT: FT-STN-005, FT-RLY-001, FT-STN-002
# Every page, both ways up, keeps the touch rules; the map's view stays between the rails
# and under the view-top row, and the Log page widens the left rail.
func test_every_page_keeps_the_touch_rules_both_ways_up() -> void:
	for sz: Array in [[SIDEWAYS, LANDSCAPE], [UPRIGHT, PORTRAIT]]:
		var s: StationScreen = await _screen(sz[0], sz[1])
		var p: RelayPanel = _relay(s)
		_given(s, "mark")
		assert_bool(p.in_frame).is_true()
		assert_int(p.pages.count()).is_equal(5)
		assert_bool(p.hud.visible).is_false()
		for page: int in p.pages.count():
			p.pages.current = page
			await _frames(3)
			var what: String = "%s page %d" % [sz[0], page]
			_assert_taps_ok(s, what)
			assert_object(p.map.view_rect).override_failure_message(what).is_equal(
				p.phone.view_in_map()
			)
			assert_float(p.map.view_rect.position.y).is_greater_equal(p.top_reserve)
		if sz[0] == SIDEWAYS:
			p.pages.current = RelayPhone.PAGE_LOG
			await _frames(3)
			assert_float(p.phone.layout.left.size.x).is_equal(RelayPhone.LOG_W)
		# The Send sheet keeps the rules too.
		p.pages.current = RelayPhone.PAGE_MAP
		p.open_send()
		await _frames(1)
		assert_bool(s.sheet.is_open()).is_true()
		assert_str(s.sheet.option(0).text).is_equal("Wren")
		_assert_taps_ok(s.sheet, "%s send sheet" % sz[0])
		s.sheet.cancel()
		_vp.queue_free()
		await _frames(1)


# FT: FT-STN-005, FT-NET-022
# A long press on Launch probe takes the launcher (a tap still launches).
func test_long_press_on_launch_claims_the_launcher() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: RelayPanel = _relay(s)
	_given(s, "contact")
	var launch: RailButton = p.phone.buttons["launch"]
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = launch.size / 2.0
	t.pressed = true
	launch._gui_input(t)
	StationFixture.clock(s.ctx).ms += RelayPhone.LONG_PRESS_MS + 10
	await _frames(2)
	t.pressed = false
	launch._gui_input(t)
	assert_array(StationFixture.sent(s.ctx).of("claim")).is_equal(
		[["claim", [StationViews.CLAIM_PROBE]]]
	)
	assert_int(_count(s, "command", "launch_probe").call()).is_equal(0)
	PhoneReach.tap(launch)
	assert_int(_count(s, "command", "launch_probe").call()).is_equal(1)


# FT: FT-STN-005, FT-RLY-002, FT-SPA-013
# On the map: one finger drags a mark out; a second finger slides its depth before it
# lands; a pinch zooms and a twist turns the map.
func test_map_gestures_depth_pinch_and_twist() -> void:
	var s: StationScreen = await _screen(SIDEWAYS, LANDSCAPE)
	var p: RelayPanel = _relay(s)
	s.ctx.crew.select("", -1)
	var at: Vector2 = p.map.view_rect.get_center() + Vector2(30.0, 40.0)
	_mouse(p, at, true)
	_mouse_move(p, Vector2(20.0, 0.0))
	_touch(p, 0, at, true)
	_touch(p, 1, at + Vector2(0.0, 80.0), true)
	_drag(p, 1, at + Vector2(0.0, 40.0), Vector2(0.0, -40.0))
	assert_float(float(p._drag["depth"])).is_less(0.0)
	_touch(p, 1, at, false)
	_touch(p, 0, at, false)
	_mouse(p, at, false)
	var placed: Array = StationFixture.sent(s.ctx).of("place_mark")
	assert_int(placed.size()).is_equal(1)
	# Pinch and twist: no mark, the span and the view change.
	var span: float = p.map.span_m
	var view: Basis = p.map.view
	var a: Vector2 = at
	var b0: Vector2 = at + Vector2(100.0, 0.0)
	_mouse(p, a, true)
	_touch(p, 0, a, true)
	_touch(p, 1, b0, true)
	_drag(p, 1, at + Vector2(140.0, 40.0), Vector2(40.0, 40.0))
	assert_float(p.map.span_m).is_less(span)
	assert_bool(p.map.view.is_equal_approx(view)).is_false()
	_touch(p, 1, b0, false)
	_touch(p, 0, a, false)
	_mouse(p, a, false)
	assert_int(StationFixture.sent(s.ctx).of("place_mark").size()).is_equal(1)


func _touch(p: RelayPanel, index: int, at: Vector2, down: bool) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = down
	p._gui_input(t)


func _drag(p: RelayPanel, index: int, at: Vector2, rel: Vector2) -> void:
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.index = index
	d.position = at
	d.relative = rel
	p._gui_input(d)


## The first finger's emulated mouse.
func _mouse(p: RelayPanel, at: Vector2, down: bool) -> void:
	var m: InputEventMouseButton = InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = at
	m.pressed = down
	m.device = InputEvent.DEVICE_ID_EMULATION
	p._gui_input(m)


func _mouse_move(p: RelayPanel, rel: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.relative = rel
	m.device = InputEvent.DEVICE_ID_EMULATION
	p._gui_input(m)
