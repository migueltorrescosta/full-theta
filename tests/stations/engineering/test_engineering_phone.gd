extends GdUnitTestSuite
## Engineering on a phone (#28 follow-up, design 2.3, D287): the persistent rail (a grid
## upright) with every board action and Claim, the pages Power, Ship, Faults and Crew, every
## action within 2 taps of rest (rail actions at 1), the touch rules on every page both ways
## up, and rail taps that send what the keys send.
# FT: FT-STN-005

const Reach = preload("res://tests/stations/wr/phone_reach.gd")
const SETTINGS: String = "user://test_engineering_phone.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]
const FORMS: Array = [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]
const P = EngineeringPanel.Page

## The design's reachability table (2.3): [action, page, control, taps, the send it makes].
## Rail actions are persistent, so 1 tap from rest; the page views are 1 tap.
const TABLE: Array = [
	["pip add", P.POWER, "Touch_pip_add", 1, "set_pips"],
	["pip remove", P.POWER, "Touch_pip_remove", 1, "set_pips"],
	["shield tighter", P.POWER, "Touch_shield_tighter", 1, "set_shield"],
	["shield wider", P.POWER, "Touch_shield_wider", 1, "set_shield"],
	["boost", P.POWER, "Touch_boost", 1, "boost"],
	["harden", P.POWER, "Touch_harden", 1, "harden"],
	["send crew", P.POWER, "Touch_dispatch_nearest", 1, "dispatch_repair"],
	["cause", P.POWER, "Touch_cause_next", 1, ""],
	["probe", P.POWER, "Touch_fabricate_probe", 1, "fabricate_probe"],
	["claim a crew", P.POWER, "Touch_claim", 1, "claim"],
	["ping", P.CREW, "ping", 2, "ping"],
	["mark", P.CREW, "mark", 2, "place_mark"],
]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, insets: Array, entry: String = "engineering") -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
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


## The kinds of what the screen sent since `from`: commands by their kind, else the method.
func _kinds(s: StationScreen, from: int) -> Array:
	var out: Array = []
	var sent: Array = StationFixture.sent(s.ctx).sent
	for i: int in range(from, sent.size()):
		var e: Array = sent[i]
		out.append(str(e[1][0]["kind"]) if e[0] == "command" else str(e[0]))
	return out


# FT: FT-STN-005, FT-STN-009, FT-ENG-002, FT-ENG-003, FT-ENG-004, FT-ENG-008, FT-NET-023
# Every action of the design's table is reached within its taps from rest, both ways up, and
# sends what it should; the Ship and Faults pages are one tab away.
func test_every_action_within_two_taps() -> void:
	for f: Array in FORMS:
		var s: StationScreen = await _screen(f[0], f[1])
		s.ctx.crew.select("contact", StationFixture.H2)
		var e: EngineeringPanel = s.focused_panel()
		assert_object(e.pages).is_not_null()
		assert_array(e.pages.titles()).is_equal(["Power", "Ship", "Faults", "Crew"])
		await _frames(2)
		for row: Array in TABLE:
			var from: int = StationFixture.sent(s.ctx).sent.size()
			var r: Dictionary = Reach.walk(s, {"page": row[1], "control": row[2], "taps": row[3]})
			var what: String = "%s %s" % [row[0], f[0]]
			assert_str(r["error"]).override_failure_message(what).is_empty()
			if row[4] != "":
				assert_array(_kinds(s, from)).override_failure_message(what).contains([row[4]])
			await _frames(1)
		for page: int in [P.SHIP, P.FAULTS]:
			Reach.rest(s)
			Reach.strip(s).tab(page).pressed.emit()
			assert_bool(e.pages.parts(page)[0].is_visible_in_tree()).is_true()
			assert_bool(e.pages.parts(P.POWER)[0].is_visible_in_tree()).is_false()
			# The rail stays: the persistent zone never pages away.
			assert_bool(Reach.control(s, "Touch_pip_add").is_visible_in_tree()).is_true()
		_drop(s)


# FT: FT-STN-005, FT-ENG-002
# Selecting a subsystem is one tap on its column on the Power page (rest).
func test_select_a_subsystem_at_rest() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var e: EngineeringPanel = s.focused_panel()
	var board: EngineeringBoard = e.board
	assert_bool(board.is_visible_in_tree()).is_true()
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = board.column_tap_rect(2).get_center()
	board._gui_input(mb)
	assert_int(e.selected).is_equal(board.columns()[2])
	_drop(s)


# FT: FT-STN-005
# Every page keeps the touch rules both ways up: 48 px rail buttons 8 px apart, nothing in
# the band or under an inset; the board stays under the view-top row.
func test_touch_rules_on_every_page() -> void:
	for f: Array in FORMS:
		var s: StationScreen = await _screen(f[0], f[1])
		s.ctx.crew.select("contact", StationFixture.H2)
		var e: EngineeringPanel = s.focused_panel()
		for page: int in e.pages.count():
			e.pages.current = page
			await _frames(3)
			var report: Dictionary = TapAudit.check(s)
			for k: String in AUDIT:
				(
					assert_array(report[k])
					. override_failure_message("%s page %d %s: %s" % [f[0], page, k, report[k]])
					. is_empty()
				)
			var view: Rect2 = e.view_rect()
			var shown: Control = e.pages.parts(page)[0]
			var top: float = shown.get_global_rect().position.y - e.global_position.y
			assert_float(top).is_greater_equal(view.position.y + e.top_reserve - 0.5)
		_drop(s)


# FT: FT-ENG-002, FT-ENG-003, FT-ENG-004, FT-ENG-008, FT-NET-023, FT-STN-005
# Each rail button, on its side and upright, sends exactly what its key sends (Claim: the
# common claim, K).
func test_rail_taps_send_the_key_intents() -> void:
	for a: Array in EngineeringPanel.TOUCH_ACTIONS:
		var id: String = a[0]
		for f: Array in FORMS:
			var touch: StationScreen = await _screen(f[0], f[1])
			var b: BaseButton = Reach.control(touch, "Touch_" + id)
			assert_bool(b.is_visible_in_tree()).override_failure_message(id).is_true()
			b.pressed.emit()
			SafeArea.simulate([])
			var keys: StationScreen = await _screen(Vector2i(1280, 720), [])
			var target: String = "screen" if id == "claim" else "engineering"
			keys.dispatch({"id": id, "pressed": true, "device": IntentTable.KBM, "target": target})
			var by_touch: Array = StationFixture.sent(touch.ctx).sent
			assert_array(by_touch).override_failure_message("%s: %s" % [id, by_touch]).is_equal(
				StationFixture.sent(keys.ctx).sent
			)
			_drop(touch)
			_drop(keys)


# FT: FT-STN-005, FT-NET-023
# The Claim button names the crew it takes, and Release once this player holds it.
func test_claim_names_the_crew() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var e: EngineeringPanel = s.focused_panel()
	var b: RailButton = e.touch_buttons["claim"]
	assert_str(b.text).is_equal("Claim A")
	s.ctx.crew.claims["crew:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	await _frames(1)
	assert_str(b.text).is_equal("Release A")
	b.pressed.emit()
	assert_array(StationFixture.sent(s.ctx).of("release_claim")).is_equal(
		[["release_claim", ["crew:0"]]]
	)
	_drop(s)


# FT: FT-STN-005
# A tablet and a desktop keep their arrangement: no pages shown, no rail.
func test_larger_screens_keep_their_layout() -> void:
	LayoutMode.forced = LayoutMode.Kind.TOUCH
	var s: StationScreen = await _screen(Vector2i(1280, 800), [])
	var e: EngineeringPanel = s.focused_panel()
	assert_bool(e._scroll_all.visible).is_true()
	assert_bool(e.board.is_visible_in_tree()).is_true()
	assert_bool(e.cutaway.is_visible_in_tree()).is_true()
	assert_int(s.top_bar.tabs.tab_count()).is_equal(0)
	assert_bool(e.touch_layout == null or not e.touch_layout.visible).is_true()
	_drop(s)


# FT: FT-STN-005, FT-PAIR-007, FT-JNT-001
# In Systems (Engineering with Science) on its side the share buttons are on Engineering's
# Crew page, 2 taps from rest; the screen shows no Share opener of its own.
func test_shares_on_the_crew_page() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE, "systems")
	s.focus(0)
	await _frames(2)
	assert_str(s.focused_station()).is_equal("engineering")
	assert_bool(s.share_opener.is_visible_in_tree()).is_false()
	var crew: CrewPage = (s.focused_panel() as EngineeringPanel).crew_page
	crew.refresh()
	var share: Array = crew.entries().filter(func(e: Array) -> bool: return e[0] == "share")
	assert_array(share).is_not_empty()
	var r: Dictionary = Reach.walk(
		s,
		{
			"page": P.CREW,
			"control":
			func(sc: StationScreen) -> BaseButton:
## Engineering on a phone (#28 follow-up, design 2.3, D287): the persistent rail (a grid
## upright) with every board action and Claim, the pages Power, Ship, Faults and Crew, every
## action within 2 taps of rest (rail actions at 1), the touch rules on every page both ways
## up, and rail taps that send what the keys send.
# FT: FT-STN-005

## The design's reachability table (2.3): [action, page, control, taps, the send it makes].
## Rail actions are persistent, so 1 tap from rest; the page views are 1 tap.

## The kinds of what the screen sent since `from`: commands by their kind, else the method.

# FT: FT-STN-005, FT-STN-009, FT-ENG-002, FT-ENG-003, FT-ENG-004, FT-ENG-008, FT-NET-023
# Every action of the design's table is reached within its taps from rest, both ways up, and
# sends what it should; the Ship and Faults pages are one tab away.

				# The rail stays: the persistent zone never pages away.

# FT: FT-STN-005, FT-ENG-002
# Selecting a subsystem is one tap on its column on the Power page (rest).

# FT: FT-STN-005
# Every page keeps the touch rules both ways up: 48 px rail buttons 8 px apart, nothing in
# the band or under an inset; the board stays under the view-top row.

# FT: FT-ENG-002, FT-ENG-003, FT-ENG-004, FT-ENG-008, FT-NET-023, FT-STN-005
# Each rail button, on its side and upright, sends exactly what its key sends (Claim: the
# common claim, K).

# FT: FT-STN-005, FT-NET-023
# The Claim button names the crew it takes, and Release once this player holds it.

# FT: FT-STN-005
# A tablet and a desktop keep their arrangement: no pages shown, no rail.

# FT: FT-STN-005, FT-PAIR-007, FT-JNT-001
# In Systems (Engineering with Science) on its side the share buttons are on Engineering's
# Crew page, 2 taps from rest; the screen shows no Share opener of its own.

				return (sc.focused_panel() as EngineeringPanel).crew_page.button("share"),
		}
	)
	assert_str(r["error"]).is_empty()
	assert_int(StationFixture.sent(s.ctx).of("share").size()).is_equal(1)
	_drop(s)
