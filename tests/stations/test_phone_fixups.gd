extends GdUnitTestSuite
## Phone fix-ups after the #28 station strands: the share buttons in a drawer on a phone on
## its side, Weapons' rail radar in a joint view, radar chips inside a small disc,
## Engineering's touch-sized columns, tokens and one-finger turn. Every screen is checked
## with TapAudit at the mockups' iPhone insets.
# FT: FT-STN-005

const SETTINGS: String = "user://test_phone_fixups.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "in_band", "outside_safe", "tight"]


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, entry: String, insets: Array, focus: int = 0) -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	CommsFixture.install(ctx)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	vp.add_child(s)
	await _frames(4)
	if focus != 0:
		s.focus(focus)
		await _frames(3)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _drop(s: StationScreen) -> void:
	s.get_parent().remove_child(s)
	s.free()


func _assert_clean(root: Control, what: String) -> void:
	var report: Dictionary = TapAudit.check(root)
	assert_array(report["targets"]).override_failure_message(what + ": no targets").is_not_empty()
	for k: String in AUDIT:
		(
			assert_array(report[k])
			. override_failure_message("%s %s: %s" % [what, k, report[k]])
			. is_empty()
		)


func _share_buttons(s: StationScreen) -> Array[Button]:
	var out: Array[Button] = []
	for b: Node in s.share_bar.get_children():
		out.append(b as Button)
	return out


# FT: FT-STN-005, FT-PAIR-007, FT-JNT-001
# On a phone on its side the share buttons don't fit under the 180 px disc: a Share opener
# (beside the joint switch) opens a drawer of 48 px buttons 8 px apart, at the top of the
# radar column or, with the column hidden (Weapons' rails), at the bottom of the view.
func test_share_buttons_sit_in_a_drawer_on_a_phone_on_its_side() -> void:
	var cases: Array = [
		["systems", 0, true],
		["logistics", 0, true],
		["quartermaster", 1, true],
		["approach", 0, false],
		["parley", 0, false],
		["targeting", 0, false],
		["comms", 0, true],
		["science", 0, false],
	]
	for c: Array in cases:
		var what: String = "%s/%d" % [c[0], c[1]]
		var s: StationScreen = await _screen(Vector2i(844, 390), c[0], LANDSCAPE, c[1])
		assert_bool(s.share_opener.is_visible_in_tree()).override_failure_message(what).is_true()
		assert_bool(s.share_drawer.visible).is_false()
		assert_bool(s.share_bar.is_visible_in_tree()).is_false()
		# The opener sits in the radar column when it shows, else in the view or, for
		# Science, under the contacts in its left rail.
		assert_bool(s.radar.is_visible_in_tree()).override_failure_message(what).is_equal(c[2])
		var slot: Container = s.focused_panel().share_slot
		if slot != null:
			assert_object(s.share_opener.get_parent()).is_same(slot)
		_assert_clean(s, what)
		s.share_opener.button_pressed = true
		s.share_opener.pressed.emit()
		await _frames(2)
		assert_bool(s.share_drawer.is_open()).override_failure_message(what).is_true()
		var buttons: Array[Button] = _share_buttons(s)
		assert_array(buttons).override_failure_message(what).is_not_empty()
		for b: Button in buttons:
			assert_bool(b.is_visible_in_tree()).is_true()
			assert_float(b.size.y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
		# The drawer covers the panel under it; its own targets keep the rules, and it keeps
		# 8 px from the opener and the switch.
		_assert_clean(s.share_drawer, what + " open")
		var drawer: Rect2 = s.share_drawer.get_global_rect()
		for b: Control in [s.share_opener, s.joint_switch]:
			if b != null and b.is_visible_in_tree():
				assert_float(TapAudit.gap(drawer, b.get_global_rect())).is_greater_equal(
					UiTheme.TOUCH_GAP
				)
		buttons[0].pressed.emit()
		assert_int(StationFixture.sent(s.ctx).of("share").size()).is_equal(1)
		_drop(s)


# FT: FT-STN-005, FT-PAIR-007
# Relay's phone layout has its own share drawer: the screen adds no second opener. Turning
# Science's phone (its rails are rebuilt) keeps the opener alive and puts it back.
func test_panels_with_their_own_share_place_keep_one_opener() -> void:
	var r: StationScreen = await _screen(Vector2i(844, 390), "relay", LANDSCAPE)
	assert_bool(r.focused_panel().shows_shares).is_true()
	assert_bool(r.share_opener.visible).is_false()
	_drop(r)
	var s: StationScreen = await _screen(Vector2i(844, 390), "science", LANDSCAPE)
	var opener: RailButton = s.share_opener
	var vp: SubViewport = s.get_parent() as SubViewport
	SafeArea.simulate(PORTRAIT)
	vp.size = Vector2i(390, 844)
	await _frames(4)
	SafeArea.simulate(LANDSCAPE)
	vp.size = Vector2i(844, 390)
	await _frames(4)
	assert_bool(is_instance_valid(opener)).is_true()
	assert_object(opener.get_parent()).is_same(s.focused_panel().share_slot)
	assert_bool(opener.is_visible_in_tree()).is_true()
	_assert_clean(s, "science turned back")
	_drop(s)


# FT: FT-STN-005, FT-PAIR-007
# Upright the share buttons stay in the column beside the radar, 48 px and 8 px apart; on a
# desktop they keep their place and there is no opener.
func test_share_buttons_stay_in_the_column_upright_and_on_a_desktop() -> void:
	var up: StationScreen = await _screen(Vector2i(390, 844), "systems", PORTRAIT)
	assert_bool(up.share_opener.visible).is_false()
	assert_bool(up.share_bar.is_visible_in_tree()).is_true()
	for b: Button in _share_buttons(up):
		assert_float(b.size.y).is_greater_equal(UiTheme.TOUCH_PRIMARY)
	_assert_clean(up.share_bar, "upright")
	_assert_clean(up, "upright screen")
	_drop(up)
	var desk: StationScreen = await _screen(Vector2i(1280, 720), "systems", [])
	assert_bool(desk.share_opener.visible).is_false()
	assert_bool(desk.share_bar.is_visible_in_tree()).is_true()
	assert_float(_share_buttons(desk)[0].size.y).is_equal(ShareBar.BUTTON_H)
	_drop(desk)


# FT: FT-STN-005, FT-WPN-002, FT-JNT-001
# In a joint view on a phone on its side Weapons shows the whole screen like alone: its
# right rail carries the radar (so Guided sits under it, clear of the top bar).
func test_weapons_keeps_its_rail_radar_in_a_joint_view() -> void:
	for c: Array in [["tactical", 1], ["gunnery", 0], ["parley", 0], ["targeting", 0]]:
		var what: String = "%s/%d" % [c[0], c[1]]
		var s: StationScreen = await _screen(Vector2i(844, 390), c[0], LANDSCAPE, c[1])
		var p: WeaponsPanel = s.focused_panel() as WeaponsPanel
		assert_object(p).is_not_null()
		var t: WeaponsTouch = p.touch()
		assert_object(t.radar).override_failure_message(what).is_not_null()
		assert_bool(t.radar.is_visible_in_tree()).is_true()
		assert_bool(s.radar.is_visible_in_tree()).is_false()
		assert_float(t.guided_button.get_global_rect().position.y).is_greater(
			t.radar.get_global_rect().end.y
		)
		_assert_clean(s, what)
		_drop(s)


# FT: FT-STN-002, FT-SPA-007, FT-STN-005
# The phone's 180 px disc keeps every chip inside it: a chip that would cross the edge
# moves to the blip's other side or slides in, and one too wide shows the callsign alone.
func test_small_radar_keeps_chips_inside() -> void:
	for c: Array in [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], "engineering", c[1])
		var r: DiscRadar = s.radar
		assert_float(r.size.x).is_less_equal(StationScreen.PHONE_RADAR + 1.0)
		var view: Rect2 = Rect2(Vector2.ZERO, r.size)
		var chips: int = 0
		for e: Dictionary in r._layout():
			if e["chip"] == "":
				continue
			chips += 1
			(
				assert_bool(view.encloses(e["chip_rect"]))
				. override_failure_message("%s at %s" % [e["chip"], e["chip_rect"]])
				. is_true()
			)
		assert_int(chips).is_greater(2)
		_drop(s)
	# A chip too wide for the disc falls back to the callsign.
	var radar: DiscRadar = auto_free(DiscRadar.new())
	radar.size = Vector2(90, 90)
	var font: Font = radar.get_theme_default_font()
	var wide: Rect2 = radar._chip_rect(font, "U3 · 11 high · mid", Vector2(80, 40), false)
	assert_float(wide.position.x).is_greater_equal(DiscRadar.CHIP_MARGIN)


# FT: FT-ENG-002, FT-ENG-003, FT-STN-005
# On a phone a pip box (22 px) and a tightness step are no tap targets: a tap anywhere in a
# column selects it (each column's area at least 44 px, 8 px from the next) and Power +/-
# set the pips; the tightness steps ignore taps (Tighter and Wider set it).
func test_engineering_columns_take_the_taps_on_a_phone() -> void:
	for c: Array in [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], "engineering", c[1])
		var e: EngineeringPanel = s.focused_panel() as EngineeringPanel
		var board: EngineeringBoard = e.board
		assert_bool(board.phone()).is_true()
		if e.touch_tabs != null:
			e.touch_tabs.current = 0
			await _frames(2)
		_assert_clean(s, "board %s" % c[0])
		var taps: Array[Node] = board.find_children("ColumnTap*", "", false, false)
		assert_int(taps.size()).is_equal(board.columns().size())
		# A tap on column 2's top pip selects it and leaves its pips alone.
		var k: int = 1
		var i: int = board.columns()[k]
		var pips: int = e.pips_of(i)
		var top: Vector2 = board._pip_rect(k, 3).get_center()
		_click(board, top)
		assert_int(e.selected).is_equal(i)
		assert_int(e.pips_of(i)).is_equal(pips)
		assert_array(StationFixture.sent(s.ctx).of("command")).is_empty()
		_click(board, board._step_rect(0).get_center())
		assert_array(StationFixture.sent(s.ctx).of("command")).is_empty()
		_drop(s)


# FT: FT-ENG-001, FT-ENG-004, FT-STN-005
# On a phone the crew tokens take a 44 px grab area (52 px apart) and a drag onto a part
# still sends the crew; a finger dragged across empty cutaway space turns it, and a tap
# there selects the part under it.
func test_engineering_cutaway_works_with_one_finger() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "engineering", LANDSCAPE)
	var e: EngineeringPanel = s.focused_panel() as EngineeringPanel
	e.touch_tabs.current = 1
	await _frames(2)
	var cut: EngineeringCutaway = e.cutaway
	assert_bool(cut.phone()).is_true()
	assert_float(cut.grab_radius() * 2.0).is_greater_equal(UiTheme.TOUCH_MIN)
	assert_str(cut.hint()).contains(tr("eng.cutaway_hint_touch"))
	_assert_clean(s, "cutaway")
	var tokens: Array[Node] = cut.find_children("CrewTap*", "", false, false)
	assert_int(tokens.size()).is_equal(e.crew_count())
	# A drag from the edge of crew B's grab area onto weapons sends B.
	var edge: Vector2 = cut.token_pos(1) + Vector2(cut.grab_radius() - 2.0, 0.0)
	_click(cut, edge)
	_move(cut, edge, cut.subsystem_pos(2))
	_click(cut, cut.subsystem_pos(2), false)
	var sent: Array = StationFixture.sent(s.ctx).of("command")
	assert_dict(sent[-1][1][0]).is_equal(
		{"kind": "dispatch_repair", "crew": 1, "subsystem_id": "weapons"}
	)
	# One finger on empty space turns the cutaway; no part is picked.
	var empty: Vector2 = Vector2(cut.size.x - 16.0, 60.0)
	assert_int(cut.subsystem_at(empty, UiTheme.TOUCH_MIN)).is_equal(-1)
	assert_int(cut.crew_at(empty)).is_equal(-1)
	var yaw: float = cut.yaw
	var picked: int = e.selected
	_click(cut, empty)
	_move(cut, empty, empty + Vector2(-40.0, 10.0))
	_click(cut, empty + Vector2(-40.0, 10.0), false)
	assert_float(cut.yaw).is_not_equal(yaw)
	assert_int(e.selected).is_equal(picked)
	# A tap (no drag) on a part selects it on release.
	var other: int = 3 if picked != 3 else 2
	_click(cut, cut.subsystem_pos(other))
	assert_int(e.selected).is_equal(picked)
	_click(cut, cut.subsystem_pos(other), false)
	assert_int(e.selected).is_equal(other)
	_drop(s)


# FT: FT-ENG-004
# A desktop keeps the mouse: a left press selects at once and only right-drag turns.
func test_engineering_cutaway_keeps_the_mouse_on_a_desktop() -> void:
	var s: StationScreen = await _screen(Vector2i(1280, 720), "engineering", [])
	var e: EngineeringPanel = s.focused_panel() as EngineeringPanel
	var cut: EngineeringCutaway = e.cutaway
	assert_bool(cut.phone()).is_false()
	assert_float(cut.grab_radius()).is_equal(EngineeringCutaway.TOKEN_R + 3.0)
	(
		assert_array(
			cut.find_children("CrewTap*", "", false, false).filter(
				func(n: Node) -> bool: return (n as Control).visible
			)
		)
		. is_empty()
	)
	var yaw: float = cut.yaw
	var empty: Vector2 = Vector2(cut.size.x - 16.0, 60.0)
	_click(cut, empty)
	_move(cut, empty, empty + Vector2(-40.0, 10.0))
	_click(cut, empty + Vector2(-40.0, 10.0), false)
	assert_float(cut.yaw).is_equal(yaw)
	_click(cut, cut.subsystem_pos(3))
	assert_int(e.selected).is_equal(3)
	_drop(s)


func _click(c: Control, pos: Vector2, pressed: bool = true) -> void:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
	c._gui_input(mb)


func _move(c: Control, from: Vector2, to: Vector2) -> void:
	for k: int in 4:
		var mm: InputEventMouseMotion = InputEventMouseMotion.new()
		mm.position = from.lerp(to, (k + 1) / 4.0)
		mm.relative = (to - from) / 4.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		c._gui_input(mm)
