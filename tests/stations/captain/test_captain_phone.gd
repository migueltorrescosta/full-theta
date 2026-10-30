extends GdUnitTestSuite
## The Captain on a phone (#28 follow-up, design 2.7, D287): a persistent rail of view
## buttons, Ping and Mark beside the mirror; pages Screen, Requests and Cards; the view-top
## row and long-press over the mirror; upright a button grid under the mirror and the tabs
## at the bottom. Tablets and desktops keep their columns.
# FT: FT-STN-005

const Reach = preload("res://tests/stations/wr/phone_reach.gd")
const SETTINGS: String = "user://test_captain_phone.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(StationViews.CAPTAIN, SETTINGS)
	CommsFixture.install(ctx)
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


func _cap(s: StationScreen) -> CaptainPanel:
	return s.focused_panel() as CaptainPanel


func _sent(s: StationScreen) -> StationFixture.RecordingClient:
	return StationFixture.sent(s.ctx)


## Both phone forms: [size, insets].
func _forms() -> Array:
	return [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]


# FT: FT-CPT-001, FT-CPT-004, FT-STN-005
# On its side the rail docks at the left (x 47-215) in four rows, the mirror fills the rest,
# the tabs are Screen, Requests and Cards (no Crew page), and the panel is in the frame.
func test_rail_mirror_and_pages_on_its_side() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: CaptainPanel = _cap(s)
	assert_bool(p.in_frame).is_true()
	assert_object(p.phone).is_not_null()
	assert_bool(p.phone.upright).is_false()
	assert_array(p.pages.titles()).is_equal(["Screen", "Requests", "Cards"])
	var rail: Rect2 = p.phone.layout.left.get_global_rect()
	assert_float(rail.position.x).is_equal_approx(47.0, 0.5)
	assert_float(rail.end.x).is_equal_approx(215.0, 0.5)
	var mirror: Rect2 = p.mirror.get_global_rect()
	assert_float(mirror.position.x).is_equal_approx(223.0, 0.5)
	assert_float(mirror.end.x).is_greater_equal(797.0)
	for id: String in ["view_0", "view_2", "view_4", "ping", "mark"]:
		var b: RailButton = p.phone.buttons[id]
		assert_bool(p.phone.layout.left.is_ancestor_of(b)).override_failure_message(id).is_true()
	# The desktop column's buttons are hidden, not shown twice.
	assert_bool(p.buttons[0].is_visible_in_tree()).is_false()
	_drop(s)


# FT: FT-CPT-001, FT-CPT-002, FT-CPT-004, FT-CPT-005, FT-STN-005
# The design's reachability table, both ways up: each view 1 tap, Ping 1, Mark 1 (the rail),
# the requests 1 and the cards 1 (a page); every action did what it should.
func test_reachability_both_ways_up() -> void:
	for f: Array in _forms():
		var s: StationScreen = await _screen(f[0], f[1])
		var p: CaptainPanel = _cap(s)
		var what: String = str(f[0])
		for i: int in MainScreen.NAMES.size():
			var r: Dictionary = Reach.walk(s, {"control": "Captain_view_%d" % i, "taps": 1})
			assert_str(r["error"]).override_failure_message("%s view %d" % [what, i]).is_empty()
		var views: Array = _sent(s).of("set_main_view").map(func(e: Array) -> int: return e[1][0])
		assert_array(views).override_failure_message(what).is_equal([0, 1, 2, 3, 4])
		var r: Dictionary = Reach.walk(s, {"control": "Captain_ping", "taps": 1})
		assert_str(r["error"]).override_failure_message(what).is_empty()
		assert_array(_sent(s).of("ping")[0][1].slice(0, 2)).is_equal(["contact", StationFixture.H2])
		r = Reach.walk(s, {"control": "Captain_mark", "taps": 1})
		assert_str(r["error"]).override_failure_message(what).is_empty()
		assert_int(_sent(s).of("place_mark").size()).is_equal(1)
		for page: int in [1, 2]:
			Reach.rest(s)
			var tab: RailButton = Reach.strip(s).tab(page)
			assert_object(tab).override_failure_message("%s tab %d" % [what, page]).is_not_null()
			tab.pressed.emit()
			var box: PanelContainer = p.phone.requests if page == 1 else p.phone.card_box
			assert_bool(box.is_visible_in_tree()).override_failure_message(what).is_true()
			var other: PanelContainer = p.phone.card_box if page == 1 else p.phone.requests
			assert_bool(other.is_visible_in_tree()).is_false()
		Reach.rest(s)
		assert_bool(p.phone.requests.is_visible_in_tree()).is_false()
		assert_bool(p.phone.card_box.is_visible_in_tree()).is_false()
		_drop(s)


# FT: FT-CPT-005, FT-STN-005
# Select by tapping: a mirror blip selects through the screen's item_at_point; on the Cards
# page a tap on a card pings it (2 taps from rest), a drag does not; under the list panel
# the mirror takes no taps.
func test_tap_a_card_pings_it() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: CaptainPanel = _cap(s)
	Reach.strip(s).tab(2).pressed.emit()
	await _frames(2)
	var box: PanelContainer = p.phone.card_box
	var row: Vector2 = Vector2(30.0, CardList.HEADER_HEIGHT + CardList.ROW_HEIGHT * 1.0 + 5.0)
	var at: Vector2 = box.get_global_transform().affine_inverse() * (p.cards.global_position + row)
	var panel_at: Vector2 = (
		p.get_global_transform().affine_inverse() * box.get_global_transform() * at
	)
	assert_dict(p.item_at(panel_at)).is_equal({"kind": "card", "id": 1})
	_mouse(box, at, true)
	_mouse(box, at, false)
	var pings: Array = _sent(s).of("ping")
	assert_int(pings.size()).is_equal(1)
	assert_array(pings[0][1].slice(0, 2)).is_equal(["card", 1])
	# A drag across the list scrolls; it pings nothing.
	_mouse(box, at, true)
	_mouse(box, at + Vector2(0.0, 40.0), false)
	assert_int(_sent(s).of("ping").size()).is_equal(1)
	# Under the panel, outside a card, nothing of the mirror is picked.
	var low: Vector2 = Vector2(box.size.x / 2.0, box.size.y - 10.0)
	var panel_low: Vector2 = (
		p.get_global_transform().affine_inverse() * box.get_global_transform() * low
	)
	assert_dict(p.item_at(panel_low)).is_empty()
	# Back on the Screen page the cards are gone and the mirror answers.
	Reach.rest(s)
	await _frames(1)
	assert_dict(p.item_at(panel_at)).is_not_equal({"kind": "card", "id": 1})
	_drop(s)


# FT: FT-CPT-001, FT-STN-005
# Taps send what the keys send: each view button equals captain_view_1..5, Ping and Mark
# equal the common ping and mark intents through StationScreen.dispatch.
func test_rail_taps_send_the_key_intents() -> void:
	for i: int in MainScreen.NAMES.size():
		var touch: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
		(_cap(touch).phone.buttons["view_%d" % i] as RailButton).pressed.emit()
		var by_touch: Array = _sent(touch).sent.duplicate()
		_drop(touch)
		var keys: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
		var ev: Dictionary = {
			"id": "captain_view_%d" % (i + 1), "target": "captain", "pressed": true
		}
		assert_bool(keys.dispatch(ev)).is_true()
		assert_array(by_touch).override_failure_message(str(i)).is_equal(_sent(keys).sent)
		_drop(keys)
	for id: String in ["ping", "mark"]:
		var touch: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
		(_cap(touch).phone.buttons[id] as RailButton).pressed.emit()
		var by_touch: Array = _sent(touch).sent.duplicate()
		_drop(touch)
		var keys: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
		var ev: Dictionary = {
			"id": id, "target": "screen", "pressed": true, "device": IntentTable.PAD
		}
		# The pad's "under the reticle" is the mirror's centre: nothing there, so the selection.
		keys.dispatch(ev)
		assert_array(by_touch).override_failure_message(id).is_not_empty()
		assert_array(by_touch).override_failure_message(id).is_equal(_sent(keys).sent)
		_drop(keys)


# FT: FT-STN-005
# The touch rules on every page, both ways up: 48 px targets 8 px apart, inside the safe
# area, never in the bottom band.
func test_touch_rules_on_every_page() -> void:
	for f: Array in _forms():
		var s: StationScreen = await _screen(f[0], f[1])
		var p: CaptainPanel = _cap(s)
		for page: int in p.pages.count():
			p.pages.current = page
			await _frames(2)
			var report: Dictionary = TapAudit.check(s)
			assert_array(report["targets"]).is_not_empty()
			for k: String in AUDIT:
				(
					assert_array(report[k])
					. override_failure_message("%s page %d %s: %s" % [f[0], page, k, report[k]])
					. is_empty()
				)
		_drop(s)


# FT: FT-CPT-004, FT-STN-005
# The list panels and the mirror's top read-outs stay under the view-top row (top_reserve);
# the panel ends above the bottom band. Upright the buttons sit under the mirror, the tabs in
# the bottom tab bar.
func test_lists_keep_under_the_view_top_row() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: CaptainPanel = _cap(s)
	p.pages.current = 1
	p.top_reserve = 60.0
	p._process(0.0)
	var view_top: float = p.global_position.y + 60.0
	assert_float(p.phone.requests.get_global_rect().position.y).is_greater_equal(view_top - 0.5)
	assert_float(p.phone.requests.get_global_rect().end.y).is_less_equal(SafeArea.tap_bottom(s))
	assert_float(p.phone.requests.get_global_rect().end.x).is_less_equal(797.5)
	assert_float(p.mirror.global_position.y + p.mirror.top_reserve).is_equal_approx(view_top, 0.5)
	_drop(s)
	var up: StationScreen = await _screen(Vector2i(390, 844), PORTRAIT)
	var q: CaptainPanel = _cap(up)
	assert_bool(q.phone.upright).is_true()
	assert_bool(up.frame.bottom_tabs.is_visible_in_tree()).is_true()
	var grid: Rect2 = (q.phone.buttons["view_0"] as Control).get_global_rect()
	assert_float(grid.position.y).is_greater_equal(q.mirror.get_global_rect().end.y)
	assert_float(grid.size.y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
	_drop(up)


# FT: FT-STN-005
# Turning the phone remakes the arrangement and its pages; a tablet keeps the desktop
# columns with no pages.
func test_turning_remakes_and_tablets_keep_columns() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: CaptainPanel = _cap(s)
	var side: PageHost = p.pages
	SafeArea.simulate(PORTRAIT)
	(s.get_parent() as SubViewport).size = Vector2i(390, 844)
	await _frames(4)
	assert_bool(p.phone.upright).is_true()
	assert_object(p.pages).is_not_same(side)
	assert_bool(p.phone.stage.is_ancestor_of(p.mirror)).is_true()
	_drop(s)
	LayoutMode.forced = LayoutMode.Kind.TOUCH
	var tab: StationScreen = await _screen(Vector2i(1280, 800), [])
	var t: CaptainPanel = _cap(tab)
	assert_object(t.phone).is_null()
	assert_object(t.pages).is_null()
	assert_bool(t.buttons[0].is_visible_in_tree()).is_true()
	_drop(tab)


# FT: FT-STN-005
# The controls help has one entry per page, the rail on the first page only, every box in
# the 844x390 frame's safe part.
func test_touch_help_lists_every_page() -> void:
	var help: Array = CaptainPanel.touch_help()
	(
		assert_array(help.map(func(e: Dictionary) -> String: return e["page"]))
		. is_equal(["Screen", "Requests", "Cards"])
	)
	assert_int(help[0]["boxes"].size()).is_equal(8)
	for e: Dictionary in help:
		for box: Array in e["boxes"]:
			var r: Rect2 = box[0]
			(
				assert_bool(Rect2(47, 0, 750, 369).encloses(r))
				. override_failure_message(str(box))
				. is_true()
			)
			assert_str(str(box[1])).is_not_empty()
			assert_str(str(box[2])).is_not_empty()
	# The rail's boxes are where the buttons are, the lists' where the panel is.
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: CaptainPanel = _cap(s)
	var ids: Array[String] = ["view_0", "view_1", "view_2", "view_3", "view_4", "ping", "mark"]
	for i: int in ids.size():
		var real: Rect2 = (p.phone.buttons[ids[i]] as Control).get_global_rect()
		var drawn: Rect2 = help[0]["boxes"][i][0]
		for d: Vector2 in [real.position - drawn.position, real.end - drawn.end]:
			(
				assert_float(d.length())
				. override_failure_message("%s %s %s" % [ids[i], real, drawn])
				. is_less(1.5)
			)
	p.pages.current = 2
	await _frames(2)
	var lists: Rect2 = p.phone.card_box.get_global_rect()
	var drawn_lists: Rect2 = help[2]["boxes"][0][0]
	assert_float((lists.position - drawn_lists.position).length()).is_less(1.5)
	_drop(s)


func _mouse(c: Control, at: Vector2, down: bool) -> void:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.position = at
	c.gui_input.emit(mb)
