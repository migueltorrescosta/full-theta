extends GdUnitTestSuite
## The shared phone frame (#28 follow-up, design "Shared frame", owner picks P28-Tabs,
## P28-Band, P28-Common, P28-Joint, P28-Dev, P28-L1): pages and their tabs, the compact top
## bar, choice sheets, the view-top row (selection chip, request chips, ping toast, partner
## glance), long-press ping and mark, the bottom band, the Crew page; tablets and desktops
## keep their layout.
# FT: FT-STN-005

const SETTINGS: String = "user://test_phone_frame.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]


## A station panel in the frame with three pages: a persistent button, a part per page.
class FramePanel:
	extends StationPanel

	var keep: RailButton = RailButton.make("Keep")
	var parts: Array[RailButton] = []

	func _setup() -> void:
		in_frame = true
		selection_extras = [["Extra", func() -> void: set_meta(&"extra", true)]]
		var rail: VBoxContainer = VBoxContainer.new()
		rail.position = Vector2(560, 120)
		rail.size = Vector2(160, 200)
		add_child(rail)
		rail.add_child(keep)
		pages = PageHost.new()
		for t: String in ["One", "Two", "Crew"]:
			var b: RailButton = RailButton.make(t + " part")
			rail.add_child(b)
			parts.append(b)
			pages.add_page(t, [b])

	func item_at(_screen_pos: Vector2) -> Dictionary:
		return {"kind": "contact", "id": StationFixture.U3}


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, entry: String, insets: Array, framed: bool = true) -> StationScreen:
	SafeArea.simulate(insets)
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	var s: StationScreen = StationScreen.new()
	if framed and entry in ["helm", "science"]:
		s.panel_factory = func(_id: String) -> StationPanel: return FramePanel.new()
	s.setup(ctx)
	# Wave 2's stations join the frame themselves; `framed` false keeps one out of it.
	for p: StationPanel in s.panels:
		p.in_frame = framed
	vp.add_child(s)
	await _frames(4)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _drop(s: StationScreen) -> void:
	s.get_parent().remove_child(s)
	s.free()


func _assert_clean(root: Control, what: String) -> void:
	var report: Dictionary = TapAudit.check(root)
	for k: String in AUDIT:
		(
			assert_array(report[k])
			. override_failure_message("%s %s: %s" % [what, k, report[k]])
			. is_empty()
		)


func _sent(s: StationScreen, method: String) -> Array:
	return StationFixture.sent(s.ctx).of(method)


func _touch(s: StationScreen, at: Vector2, down: bool, ms: int) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = at
	t.pressed = down
	StationFixture.clock(s.ctx).ms = ms
	s._input(t)


func _ev_touch(at: Vector2) -> InputEventScreenTouch:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = at
	t.pressed = true
	return t


func _drag(s: StationScreen, at: Vector2) -> void:
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.position = at
	s._input(d)


# FT: FT-STN-005
# A page swaps only its own parts: the persistent zone stays; at most five pages; a session
# title freezes the pages; a badge shows on the tab.
func test_pages_swap_only_their_parts() -> void:
	var keep: Control = auto_free(Control.new())
	var a: Control = auto_free(Control.new())
	var b: Control = auto_free(Control.new())
	var host: PageHost = PageHost.new()
	var seen: Array[int] = []
	host.page_changed.connect(func(i: int) -> void: seen.append(i))
	host.add_page("A", [a])
	host.add_page("B", [b])
	assert_bool(a.visible).is_true()
	assert_bool(b.visible).is_false()
	host.current = 1
	assert_bool(a.visible).is_false()
	assert_bool(b.visible).is_true()
	assert_bool(keep.visible).is_true()
	assert_array(seen).is_equal([1])
	host.session_title = "Scan H2 · 12 s"
	host.select(0)
	assert_int(host.current).is_equal(1)
	host.session_title = ""
	for i: int in 3:
		host.add_page("P%d" % i, [])
	assert_int(host.count()).is_equal(PageHost.MAX)
	host.set_badge(1, true)
	assert_bool(host.badge(1)).is_true()


# FT: FT-STN-005
# The tab strip follows its host: the current tab is the accent one, a tap switches, a
# lead button goes first, and a session title replaces the tabs.
func test_tabs_follow_the_host() -> void:
	var host: PageHost = PageHost.new()
	var parts: Array[Control] = []
	for t: String in ["Fly", "Nav", "Crew"]:
		var c: Control = auto_free(Control.new())
		parts.append(c)
		host.add_page(t, [c])
	var tabs: PageTabs = auto_free(PageTabs.new())
	add_child(tabs)
	tabs.bind(host)
	assert_int(tabs.tab_count()).is_equal(3)
	assert_int(tabs.tab(0).role).is_equal(RailButton.Role.ACCENT)
	tabs.tab(2).pressed.emit()
	assert_int(host.current).is_equal(2)
	assert_bool(parts[2].visible).is_true()
	assert_int(tabs.tab(2).role).is_equal(RailButton.Role.ACCENT)
	assert_int(tabs.tab(0).role).is_equal(RailButton.Role.PLAIN)
	var lead: RailButton = auto_free(RailButton.make("⇄ Weapons"))
	tabs.set_lead(lead)
	assert_int(lead.get_index()).is_equal(0)
	host.session_title = "Hack H2"
	assert_int(tabs.tab_count()).is_equal(0)
	assert_str(tabs._session.text).is_equal("Hack H2")


# FT: FT-STN-005
# A choice sheet is one level: a pick calls back once and closes; Cancel and a tap on the
# scrim close it without a choice; on its side it covers the right 308 px, upright the
# bottom.
func test_choice_sheet_picks_once_and_cancels() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(750, 302)
	add_child(host)
	var sheet: ChoiceSheet = ChoiceSheet.new()
	host.add_child(sheet)
	var picked: Array[int] = []
	var cancelled: Array[bool] = []
	sheet.cancelled.connect(func() -> void: cancelled.append(true))
	sheet.open("Hack H2", ["Engines", "Weapons", "Shields"], func(i: int) -> void: picked.append(i))
	await _frames(2)
	assert_bool(sheet.is_open()).is_true()
	assert_int(sheet.option_count()).is_equal(3)
	assert_float(sheet.box.position.x).is_equal(750.0 - ChoiceSheet.WIDTH)
	sheet.option(1).pressed.emit()
	assert_array(picked).is_equal([1])
	assert_bool(sheet.is_open()).is_false()
	sheet.option(1).pressed.emit()
	assert_array(picked).is_equal([1])
	sheet.open("Alert", ["N", "Y", "R"], func(i: int) -> void: picked.append(i))
	sheet.cancel_button.pressed.emit()
	assert_array(cancelled).is_equal([true])
	sheet.open("Alert", ["N", "Y", "R"])
	var tap: InputEventScreenTouch = InputEventScreenTouch.new()
	tap.pressed = false
	sheet._on_scrim(tap)
	assert_array(cancelled).is_equal([true, true])
	assert_array(picked).is_equal([1])
	sheet.upright = true
	sheet.open("Stations", ["1", "2"])
	await _frames(1)
	assert_float(sheet.box.position.x).is_equal(0.0)
	assert_float(sheet.box.get_rect().end.y).is_equal(302.0)


# FT: FT-STN-001, FT-STN-005, FT-STN-008
# The phone's top bar is one row: menu, status, page tabs, alert chip, timer; the ship name
# and Sound go to the menu. The menu button asks for the menu; the crew's alert chip opens
# the N/Y/R sheet and its pick sets the alert; tabs show the focused panel's pages.
func test_phone_top_bar() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "helm", LANDSCAPE)
	var bar: TopBar = s.top_bar
	assert_bool(bar.phone).is_true()
	assert_bool(bar.menu_button.is_visible_in_tree()).is_true()
	assert_bool(bar._name.is_visible_in_tree()).is_false()
	assert_bool(bar.sound.is_visible_in_tree()).is_false()
	assert_bool(bar.glance.is_visible_in_tree()).is_true()
	assert_str(bar._phone_timer.text).is_equal("00:50")
	assert_int(bar.tabs.tab_count()).is_equal(3)
	var menus: Array[bool] = []
	s.menu_requested.connect(func() -> void: menus.append(true))
	bar.menu_button.pressed.emit()
	assert_array(menus).is_equal([true])
	bar.chip.pressed.emit()
	assert_bool(s.sheet.is_open()).is_true()
	assert_int(s.sheet.option_count()).is_equal(3)
	s.sheet.option(2).pressed.emit()
	assert_array(_sent(s, "set_alert")).is_equal([["set_alert", [2]]])
	var p: FramePanel = s.focused_panel()
	bar.tabs.tab(1).pressed.emit()
	assert_bool(p.parts[1].visible).is_true()
	assert_bool(p.parts[0].visible).is_false()
	assert_bool(p.keep.visible).is_true()
	_assert_clean(bar, "top bar")
	_drop(s)


# FT: FT-STN-005
# Upright the tabs move to a bottom tab bar above the band; a tablet and a desktop keep
# their bar (ship name, Sound) and show none of the frame.
func test_upright_tabs_and_larger_screens_unchanged() -> void:
	var up: StationScreen = await _screen(Vector2i(390, 844), "helm", PORTRAIT)
	assert_bool(up.frame.bottom_tabs.is_visible_in_tree()).is_true()
	assert_int(up.frame.bottom_tabs.tab_count()).is_equal(3)
	assert_int(up.top_bar.tabs.tab_count()).is_equal(0)
	assert_float(up.frame.bottom_tabs.get_global_rect().end.y).is_less_equal(
		SafeArea.tap_bottom(up)
	)
	_assert_clean(up.frame.bottom_tabs, "bottom tabs")
	_drop(up)
	for size: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		LayoutMode.forced = LayoutMode.Kind.TOUCH if size.x == 1280 else LayoutMode.Kind.DESKTOP
		var big: StationScreen = await _screen(size, "helm", [])
		assert_bool(big.phone).is_false()
		assert_bool(big.top_bar.phone).is_false()
		assert_bool(big.top_bar._name.is_visible_in_tree()).is_true()
		assert_bool(big.top_bar.sound.is_visible_in_tree()).is_true()
		assert_bool(big.frame.bottom_tabs.visible).is_false()
		assert_bool(big.frame.view_top.visible).is_false()
		assert_bool(big.frame.band_guard.visible).is_false()
		_drop(big)


# FT: FT-STN-009, FT-SPA-016, FT-STN-005
# The selection chip: arrows cycle the target, its name opens the selection sheet (Ping,
# Mark here, Clear and the station's extras).
func test_selection_chip_and_sheet() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "helm", LANDSCAPE)
	s.ctx.crew.select("contact", StationFixture.H2)
	s._process(0.016)
	assert_bool(s.frame.selection_chip.is_visible_in_tree()).is_true()
	assert_str(s.frame.selection_chip.name_button.text).starts_with("H2 · ")
	var order: Array = s.contacts_by_range()
	s.frame.selection_chip.next_button.pressed.emit()
	assert_int(int(s.ctx.crew.selection["id"])).is_equal(
		int(order[(order.find(StationFixture.H2) + 1) % order.size()])
	)
	s.frame.selection_chip.prev_button.pressed.emit()
	assert_int(int(s.ctx.crew.selection["id"])).is_equal(StationFixture.H2)
	s.frame.selection_chip.name_button.pressed.emit()
	assert_int(s.sheet.option_count()).is_equal(4)
	s.sheet.option(0).pressed.emit()
	assert_array(_sent(s, "ping")[0][1].slice(0, 2)).is_equal(["contact", StationFixture.H2])
	s.frame.selection_chip.name_button.pressed.emit()
	s.sheet.option(1).pressed.emit()
	assert_int(_sent(s, "place_mark").size()).is_equal(1)
	s.frame.selection_chip.name_button.pressed.emit()
	s.sheet.option(3).pressed.emit()
	assert_bool(s.focused_panel().has_meta(&"extra")).is_true()
	s.frame.selection_chip.name_button.pressed.emit()
	s.sheet.option(2).pressed.emit()
	assert_bool(s.ctx.crew.selection.is_empty()).is_true()
	s._process(0.016)
	await _frames(1)
	_assert_clean(s.frame.view_top, "view-top row")
	_drop(s)


# FT: FT-PAIR-013, FT-SPA-016, FT-STN-005
# Incoming chips show with ✓ and ✕ that answer them; a ping shows a toast whose tap selects
# the pinged item.
func test_request_chips_and_ping_toast() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "helm", LANDSCAPE)
	var at: int = NetChips.def().chips.find(
		NetChips.def().chips.filter(func(c: ChipDef) -> bool: return c.to_station == &"helm")[0]
	)
	var from: int = StationViews.CREW.find(String(NetChips.def().chips[at].from_station))
	var row: Dictionary = {
		"id": 5, "chip": at, "arg": -1, "from": from, "to": 0, "sent": 3500, "expires": 4000
	}
	s.ctx.view.blocks[StationViews.Section.CHIPS] = {"chips": [row]}
	s._process(0.016)
	await _frames(1)
	assert_bool(s.frame.request_chips.is_visible_in_tree()).is_true()
	assert_bool(s.chip_strip.visible).is_false()
	s.frame.request_chips.buttons(0)[0].pressed.emit()
	assert_array(_sent(s, "answer_chip")).is_equal([["answer_chip", [5, true]]])
	s.frame.request_chips.buttons(0)[1].pressed.emit()
	assert_array(_sent(s, "answer_chip")[1][1]).is_equal([5, false])
	var p: Dictionary = {"ship": 0, "kind": "contact", "id": StationFixture.U3, "by": "Bo"}
	s.ctx.crew.handle_event({"type": "ping", "payload": p}, StationFixture.NOW_MS)
	assert_bool(s.frame.ping_toast.visible).is_true()
	assert_str(s.frame.ping_toast.text).is_equal("Bo pinged U3")
	s.frame.ping_toast.pressed.emit()
	assert_int(int(s.ctx.crew.selection["id"])).is_equal(StationFixture.U3)
	_drop(s)


# FT: FT-SPA-016, FT-SPA-013, FT-STN-005
# A long-press let go in place pings; held then dragged, it marks where it ends; a short tap
# or a quick drag does neither; a finger in the bottom band does nothing.
func test_long_press_pings_and_marks() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "helm", LANDSCAPE)
	s.ctx.crew.select("contact", StationFixture.H2)
	var mid: Vector2 = s._main.get_global_rect().get_center() + Vector2(-40, 40)
	var t0: int = StationFixture.NOW_MS
	_touch(s, mid, true, t0)
	_touch(s, mid, false, t0 + 100)
	assert_int(_sent(s, "ping").size()).is_equal(0)
	_touch(s, mid, true, t0 + 1000)
	_touch(s, mid, false, t0 + 1000 + LongPress.HOLD_MS + 10)
	assert_int(_sent(s, "ping").size()).is_equal(1)
	_touch(s, mid, true, t0 + 3000)
	s.frame.long_press.update(t0 + 3000 + LongPress.HOLD_MS)
	_drag(s, mid + Vector2(60, 0))
	_touch(s, mid + Vector2(60, 0), false, t0 + 3700)
	assert_int(_sent(s, "ping").size()).is_equal(1)
	assert_int(_sent(s, "place_mark").size()).is_equal(1)
	_touch(s, mid, true, t0 + 5000)
	_drag(s, mid + Vector2(60, 0))
	_touch(s, mid + Vector2(60, 0), false, t0 + 5000 + LongPress.HOLD_MS + 10)
	assert_int(_sent(s, "place_mark").size()).is_equal(1)
	var band: Vector2 = Vector2(422, 388)
	assert_bool(s.frame.band_guard.get_global_rect().has_point(band)).is_true()
	assert_bool(s.frame.input(_ev_touch(band))).is_true()
	_drop(s)


# FT: FT-STN-005
# A panel in the frame draws into the bottom band on its side; one not yet in the frame
# stops above it, and keeps the chip strip.
func test_band_is_drawn_into_only_by_framed_panels() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "helm", LANDSCAPE)
	assert_float(s._main.get_global_rect().end.y).is_equal(390.0)
	assert_bool(s.frame.band_guard.visible).is_true()
	_drop(s)
	var old: StationScreen = await _screen(Vector2i(844, 390), "engineering", LANDSCAPE, false)
	assert_float(old._main.get_global_rect().end.y).is_less_equal(SafeArea.tap_bottom(old))
	assert_bool(old.frame.view_top.visible).is_false()
	_drop(old)


# FT: FT-JNT-001, FT-STN-005
# The dev seat's station button opens a sheet of the six stations numbered 1 to 6 (D256);
# a pick focuses that station, and the button names it.
func test_dev_seat_station_sheet() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), StationViews.ALL, LANDSCAPE, false)
	assert_bool(s._tabs.visible).is_false()
	assert_object(s.top_bar.tabs.lead).is_same(s.joint_switch)
	assert_str(s.joint_switch.text).is_equal(tr("station.helm") + " ▾")
	s.joint_switch.pressed.emit()
	assert_int(s.sheet.option_count()).is_equal(6)
	assert_str(s.sheet.option(2).text).is_equal("3 " + tr("station.engineering"))
	s.sheet.option(2).pressed.emit()
	await _frames(2)
	assert_str(s.focused_station()).is_equal("engineering")
	assert_str(s.joint_switch.text).starts_with(tr("station.engineering"))
	_drop(s)


# FT: FT-JNT-001, FT-JNT-005, FT-STN-005
# A joint view's partner glance shows the other station's read-outs; in Tactical on
# Weapons focus it reads Helm's speed and mode and its Stop runs Helm's All stop.
func test_partner_glance_in_tactical() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "tactical", LANDSCAPE)
	s.focus(1)
	s._process(0.016)
	await _frames(1)
	assert_bool(s.frame.glance.is_visible_in_tree()).is_true()
	assert_str(s.frame.glance.text.text).contains("80 m/s")
	assert_bool(s.frame.glance.action.visible).is_true()
	s.frame.glance.action.pressed.emit()
	var stops: Array = _sent(s, "command").filter(
		func(c: Array) -> bool: return c[1][0]["kind"] == "helm_all_stop"
	)
	assert_int(stops.size()).is_equal(1)
	_drop(s)


# FT: FT-JNT-001
# Every joint view has a glance card for each of its stations as the partner, and every
# read-out names a known one.
func test_every_joint_view_has_both_glance_cards() -> void:
	var ctx: StationContext = StationFixture.context("tactical", SETTINGS)
	var joint: int = 0
	for entry: String in StationViews.ENTRIES:
		var pair: Array = StationViews.ENTRIES[entry][2]
		if pair.size() != 2:
			continue
		joint += 1
		for i: int in 2:
			var card: Array = PartnerGlance.card_of(pair[i], pair[1 - i])
			assert_array(card).override_failure_message(entry).has_size(2)
			for id: String in card[0]:
				(
					assert_str(PartnerGlance.readout(ctx, id))
					. override_failure_message(id)
					. is_not_equal("-")
				)
	assert_int(joint).is_equal(15)
	assert_int(PartnerGlance.CARDS.size()).is_equal(30)


# FT: FT-STN-010, FT-PAIR-007, FT-STN-005
# The Crew page holds the station's request chips, Ping, Mark and its shares; each sends.
func test_crew_page_buttons_send() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), "engineering", LANDSCAPE, false)
	var page: CrewPage = CrewPage.new(s.focused_panel())
	s.focused_panel().add_child(page)
	page.refresh()
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_object(page.button("ping")).is_not_null()
	assert_object(page.button("mark")).is_not_null()
	page.button("ping").pressed.emit()
	assert_int(_sent(s, "ping").size()).is_equal(1)
	page.button("mark").pressed.emit()
	assert_int(_sent(s, "place_mark").size()).is_equal(1)
	var chips: Array[ChipDef] = s.focused_panel().request_chips()
	if not chips.is_empty():
		page.button("chip", String(chips[0].id)).pressed.emit()
		assert_int(_sent(s, "send_chip").size() + _sent(s, "command").size()).is_greater(0)
	for id: StringName in s.shareable():
		page.button("share", String(id)).pressed.emit()
	assert_int(_sent(s, "share").size()).is_equal(s.shareable().size())
	_drop(s)
