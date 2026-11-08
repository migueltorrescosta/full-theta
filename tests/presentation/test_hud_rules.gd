extends GdUnitTestSuite
## The HUD rules of D319 on every layout of the L5 fixtures: a toast sits in the top bar's
## status text (never over a panel, a radar or a control), and a radar chip stays within
## 48 px of its own blip, inside the radar's rectangle, clear of the other chips and of
## their stems.
# FT: FT-STN-002, FT-STN-004

const SETTINGS: String = "user://test_hud_rules.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
## [window size (px), UI scale, touch, insets]; the 150 % layout is a 1280 x 720 window.
const LAYOUTS: Array = [
	[Vector2i(1920, 1080), 1.0, false, []],
	[Vector2i(1280, 720), 1.0, false, []],
	[Vector2i(1280, 720), 1.5, false, []],
	[Vector2i(1024, 768), 1.0, true, []],
	[Vector2i(768, 1024), 1.0, true, []],
	[Vector2i(844, 390), 1.0, false, LANDSCAPE],
	[Vector2i(390, 844), 1.0, false, PORTRAIT],
]
const ENTRIES: Array = [
	"helm",
	"weapons",
	"engineering",
	"science",
	"relay",
	"comms",
	"captain",
	"viewer",
	"approach",
	"drive",
	"fire_control",
	"gunnery",
	"intel",
	"logistics",
	"nav",
	"ops",
	"parley",
	"quartermaster",
	"sensors",
	"survey",
	"systems",
	"tactical",
	"targeting",
]

var _window_size: Vector2i = Vector2i.ZERO


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(layout: Array, entry: String) -> StationScreen:
	LayoutMode.forced = LayoutMode.Kind.TOUCH if layout[2] else -1
	SafeArea.simulate(layout[3])
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	if float(layout[1]) == 1.0:
		var vp: SubViewport = auto_free(SubViewport.new())
		vp.size = layout[0]
		add_child(vp)
		vp.add_child(s)
	else:
		# A UI scale applies to the window (the form follows its physical size): the shot
		# is the 1280 x 720 window at 150 %, a 853 x 480 viewport.
		var win: Window = get_tree().root
		_window_size = win.size
		win.size = layout[0]
		win.content_scale_factor = float(layout[1])
		add_child(s)
	for i: int in 4:
		await get_tree().process_frame
	return s


func _drop(s: StationScreen) -> void:
	s.get_parent().remove_child(s)
	s.free()
	var win: Window = get_tree().root
	win.content_scale_factor = 1.0
	if _window_size != Vector2i.ZERO:
		win.size = _window_size
		_window_size = Vector2i.ZERO


# FT: FT-STN-004
func test_a_toast_sits_inside_the_top_bar_and_covers_no_control() -> void:
	for layout: Array in LAYOUTS:
		for entry: String in ["helm", "engineering", "science", "captain"]:
			var s: StationScreen = await _screen(layout, entry)
			var where: String = "%s %s" % [layout[0], entry]
			for i: int in 3:
				s.toasts.push("Weapons fault %d" % i, "warn", s.ctx.now_ms())
			await get_tree().process_frame
			await get_tree().process_frame
			assert_bool(s.toasts.visible).override_failure_message(where).is_true()
			var box: Rect2 = s.toasts.get_global_rect()
			var bar: Rect2 = s.top_bar.get_global_rect()
			assert_bool(box.has_area()).override_failure_message(where).is_true()
			(
				assert_bool(bar.grow(0.5).encloses(box))
				. override_failure_message("%s: toast %s outside the bar %s" % [where, box, bar])
				. is_true()
			)
			var controls: Array[Control] = [
				s.top_bar.chip, s.top_bar.sound, s.top_bar.menu_button, s.top_bar.tabs
			]
			for c: Control in controls:
				if c.is_visible_in_tree():
					(
						assert_bool(c.get_global_rect().intersects(box))
						. override_failure_message("%s: toast over %s" % [where, c.name])
						. is_false()
					)
			_drop(s)


# FT: FT-STN-002
func test_radar_chips_stay_near_their_blip_and_clear_of_each_other() -> void:
	for layout: Array in LAYOUTS:
		for entry: String in ENTRIES:
			var s: StationScreen = await _screen(layout, entry)
			var where: String = "%s %s" % [layout[0], entry]
			_check_chips(s.radar, where)
			_drop(s)


func _check_chips(radar: DiscRadar, where: String) -> void:
	var entries: Array[Dictionary] = radar._layout()
	var view: Rect2 = radar._view()
	for e: Dictionary in entries:
		if e["chip"] == "":
			continue
		var r: Rect2 = e["chip_rect"]
		var name: String = "%s %s" % [where, e["item"]["label"]]
		(
			assert_float(ChipLayout.gap_to(r, e["pos"]))
			. override_failure_message("%s: chip %s is far from its blip %s" % [name, r, e["pos"]])
			. is_less_equal(48.0)
		)
		(
			assert_bool(view.grow(0.5).encloses(r))
			. override_failure_message("%s: chip %s outside the radar %s" % [name, r, view])
			. is_true()
		)
		for o: Dictionary in entries:
			if o == e:
				continue
			if o["chip"] != "":
				(
					assert_bool((o["chip_rect"] as Rect2).intersects(r))
					. override_failure_message(
						"%s: chip over %s's chip" % [name, o["item"]["label"]]
					)
					. is_false()
				)
			if not o["beyond"]:
				var p: Vector2 = o["pos"]
				var f: Vector2 = o["foot"]
				var stem: Rect2 = Rect2(minf(f.x, p.x) - 1.0, minf(f.y, p.y), 2.0, absf(f.y - p.y))
				(
					assert_bool(stem.intersects(r))
					. override_failure_message(
						"%s: chip crossed by %s's stem" % [name, o["item"]["label"]]
					)
					. is_false()
				)


## The Engineering and Systems cutaway (rule 4): at least a 200 px square under the hint, no
## two discs overlapping, each label within 32 px of its part, and the faults list's
## last visible row whole at rest with a scrollbar when it scrolls.
# FT: FT-ENG-001
func test_the_ship_cutaway_stays_readable_on_small_layouts() -> void:
	var small: Array = [LAYOUTS[1], LAYOUTS[2], LAYOUTS[5], LAYOUTS[6]]
	var checked: int = 0
	for layout: Array in small:
		for entry: String in ["engineering", "systems"]:
			var s: StationScreen = await _screen(layout, entry)
			var phone: bool = LayoutMode.is_phone(s.form)
			var pages: Array = [-1]
			if phone and entry == "engineering":
				pages = [1]
			for page: int in pages:
				if page >= 0:
					s.focused_panel().pages.current = page
					for i: int in 3:
						await get_tree().process_frame
				var where: String = "%s %s page %d" % [layout[0], entry, page]
				var panel: EngineeringPanel = (
					(s.focused_panel() if entry == "engineering" else s.panels[0])
					as EngineeringPanel
				)
				if panel == null:
					panel = s.panels[0] as EngineeringPanel
				if _check_cutaway(panel, where):
					checked += 1
			_drop(s)
	assert_int(checked).is_greater_equal(6)


func _check_cutaway(panel: EngineeringPanel, where: String) -> bool:
	var cut: EngineeringCutaway = panel.cutaway
	if not cut.is_visible_in_tree():
		return false
	var area: Vector2 = Vector2(cut.size.x, cut.size.y - cut.hint_height())
	(
		assert_bool(area.x >= 199.0 and area.y >= 199.0)
		. override_failure_message("%s: cutaway area %s under 200 px" % [where, area])
		. is_true()
	)
	var r: float = cut.node_r()
	for i: int in panel.count():
		for j: int in range(i + 1, panel.count()):
			(
				assert_float(cut.subsystem_pos(i).distance_to(cut.subsystem_pos(j)))
				. override_failure_message("%s: discs %d and %d overlap" % [where, i, j])
				. is_greater_equal(2.0 * r)
			)
	var rects: Dictionary = cut.label_rects()
	for i: int in rects:
		var box: Rect2 = rects[i]
		var c: Vector2 = cut.subsystem_pos(i)
		var near: Vector2 = c.clamp(box.position, box.end)
		(
			assert_float(near.distance_to(c))
			. override_failure_message(
				"%s: label %d is %s from its part" % [where, i, near.distance_to(c)]
			)
			. is_less_equal(32.0)
		)
	return true


# FT: FT-STN-002
func test_relay_map_chips_sit_next_to_their_blip_inside_the_free_part_of_the_map() -> void:
	for layout: Array in [LAYOUTS[1], LAYOUTS[2], LAYOUTS[3]]:
		var s: StationScreen = await _screen(layout, "relay")
		var p: RelayPanel = s.focused_panel() as RelayPanel
		p.refresh()
		await get_tree().process_frame
		var where: String = "%s relay" % [layout[0]]
		var free: Rect2 = p.hud.free_rect()
		assert_bool(free.has_area()).override_failure_message(where).is_true()
		var entries: Array[Dictionary] = p.map._layout()
		for e: Dictionary in entries:
			var name: String = "%s %s" % [where, e["item"]["label"]]
			(
				assert_bool(free.grow(2.0).has_point(e["pos"]))
				. override_failure_message(
					"%s: blip %s outside the free map %s" % [name, e["pos"], free]
				)
				. is_true()
			)
			if e["chip"] == "":
				continue
			var r: Rect2 = e["chip_rect"]
			(
				assert_float(ChipLayout.gap_to(r, e["pos"]))
				. override_failure_message(name)
				. is_less_equal(48.0)
			)
			assert_bool(free.grow(2.5).encloses(r)).override_failure_message(name).is_true()
			for o: Dictionary in entries:
				if o != e and o["chip"] != "":
					(
						assert_bool((o["chip_rect"] as Rect2).intersects(r))
						. override_failure_message(name)
						. is_false()
					)
		_drop(s)


# FT: FT-STN-002
func test_a_chip_a_sheet_would_cut_is_hidden() -> void:
	var radar: DiscRadar = auto_free(DiscRadar.new())
	radar.size = Vector2(300, 300)
	add_child(radar)
	var box: Control = auto_free(Control.new())
	box.position = Vector2(0, 150)
	box.size = Vector2(300, 150)
	add_child(box)
	SheetCover.register(box)
	var covers: Array[Rect2] = SheetCover.over(radar)
	assert_int(covers.size()).is_equal(1)
	var layout: Array[Dictionary] = [
		{"chip": "H2", "chip_rect": Rect2(20, 100, 30, 18)},
		{"chip": "U3", "chip_rect": Rect2(20, 142, 30, 18)},
		{"chip": "F4", "chip_rect": Rect2(20, 200, 30, 18)},
	]
	DiscRadar.hide_covered(layout, covers)
	assert_str(layout[0]["chip"]).is_equal("H2")
	assert_str(layout[1]["chip"]).is_equal("")
	assert_str(layout[2]["chip"]).is_equal("")
	box.visible = false
	assert_array(SheetCover.over(radar)).is_empty()


# FT: FT-STN-001
func test_the_pause_sheet_is_opaque_and_the_lesson_card_covers_no_gauge() -> void:
	var s: StationScreen = await _screen(LAYOUTS[6], "helm")
	var ctx: StationContext = s.ctx
	var o: PauseOverlay = PauseOverlay.new()
	s.get_parent().add_child(o)
	o.setup(ctx)
	ctx.crew.handle_event(
		{
			"type": "pause",
			"payload": {"ship": 0, "uncovered": ["science"], "crew": 2, "min_crew": 3}
		},
		0
	)
	for i: int in 3:
		await get_tree().process_frame
	var sheet: StyleBoxFlat = o.get_theme_stylebox("panel") as StyleBoxFlat
	assert_float(sheet.bg_color.a).is_equal(1.0)
	_drop(s)
	# On a desktop the lesson card sits in the side column, off the main view's gauges.
	var d: StationScreen = await _screen(LAYOUTS[1], "helm")
	d.ctx.training["helm"] = {
		"line": "shakedown.helm.face", "text": "Face the drone.", "example": "", "done": false
	}
	for i: int in 3:
		await get_tree().process_frame
	var card: Rect2 = d.training.get_global_rect()
	var main: Rect2 = d.focused_panel().get_global_rect()
	assert_bool(d.training.visible).is_true()
	(
		assert_bool(card.intersects(main))
		. override_failure_message("card %s over the view %s" % [card, main])
		. is_false()
	)
	_drop(d)


# FT: FT-STN-001
func test_a_short_viewer_hides_its_radar_strip() -> void:
	var tall: StationScreen = await _screen(LAYOUTS[1], "viewer")
	var viewer: ViewerPanel = tall.focused_panel() as ViewerPanel
	assert_bool(viewer.radar.visible).is_true()
	_drop(tall)
	var short: StationScreen = await _screen(LAYOUTS[2], "viewer")
	viewer = short.focused_panel() as ViewerPanel
	assert_bool(viewer.radar.visible).is_false()
	_drop(short)


## Round 5 fixes (full-theta #12): each rule below failed on a baseline of round 4.


# FT: FT-STN-001
func test_the_captain_phone_shows_its_radar_except_under_a_list() -> void:
	for layout: Array in [LAYOUTS[5], LAYOUTS[6]]:
		var s: StationScreen = await _screen(layout, "captain")
		var cap: CaptainPanel = s.focused_panel() as CaptainPanel
		var where: String = "%s captain" % [layout[0]]
		(
			assert_bool(cap.mirror.radar.is_visible_in_tree())
			. override_failure_message(where + ": radar hidden on the Screen page")
			. is_true()
		)
		for page: int in [1, 2]:
			cap.pages.current = page
			for i: int in 3:
				await get_tree().process_frame
			(
				assert_bool(cap.mirror.radar.is_visible_in_tree())
				. override_failure_message("%s page %d: radar under a list" % [where, page])
				. is_false()
			)
		cap.pages.current = 0
		for i: int in 3:
			await get_tree().process_frame
		(
			assert_bool(cap.mirror.radar.is_visible_in_tree())
			. override_failure_message(where + ": radar not back on the Screen page")
			. is_true()
		)
		_drop(s)


# FT: FT-STN-004
func test_a_toast_leaves_the_bars_divider() -> void:
	for layout: Array in [LAYOUTS[0], LAYOUTS[1], LAYOUTS[2]]:
		var s: StationScreen = await _screen(layout, "engineering")
		s.toasts.push("Weapons fault", "warn", s.ctx.now_ms())
		for i: int in 3:
			await get_tree().process_frame
		var box: Rect2 = s.toasts.get_global_rect()
		var bar: Rect2 = s.top_bar.get_global_rect()
		(
			assert_float(box.end.y)
			. override_failure_message(
				"%s: toast %s covers the divider of %s" % [layout[0], box, bar]
			)
			. is_less_equal(bar.end.y - 1.0)
		)
		_drop(s)


# FT: FT-ENG-001
func test_the_faults_scrollbar_shows_only_when_the_list_overflows() -> void:
	var overflowed: int = 0
	for layout: Array in [LAYOUTS[0], LAYOUTS[1], LAYOUTS[2]]:
		for entry: String in ["engineering", "systems", "logistics"]:
			var s: StationScreen = await _screen(layout, entry)
			var panel: EngineeringPanel = s.panels[0] as EngineeringPanel
			var scroll: ScrollContainer = panel._lists_scroll
			var over: bool = panel._lists.get_combined_minimum_size().y > scroll.size.y
			overflowed += int(over)
			(
				assert_bool(scroll.get_v_scroll_bar().visible)
				. override_failure_message(
					(
						"%s %s: scrollbar %s with overflow %s"
						% [layout[0], entry, scroll.get_v_scroll_bar().visible, over]
					)
				)
				. is_equal(over)
			)
			_drop(s)
	assert_int(overflowed).is_greater(0)


# FT: FT-STN-002
func test_relay_boxes_show_their_headings_and_cut_no_row_at_150_percent() -> void:
	var s: StationScreen = await _screen(LAYOUTS[2], "relay")
	var hud: RelayHud = (s.focused_panel() as RelayPanel).hud
	assert_bool(hud._inbox_heading.is_visible_in_tree()).is_true()
	assert_str(hud._inbox_heading.text).starts_with("INBOX")
	var view: Rect2 = hud._left_scroll.get_global_rect()
	for b: Node in hud._contacts.get_children() + hud._marks.get_children():
		var r: Rect2 = (b as Control).get_global_rect()
		if view.intersects(r):
			(
				assert_bool(view.grow(0.5).encloses(r))
				. override_failure_message("row %s cut by the list view %s" % [r, view])
				. is_true()
			)
	_drop(s)
	# Ops: the side column ends under a whole row, at a station that scrolls it.
	var o: StationScreen = await _screen(LAYOUTS[1], "ops")
	var scroll: ScrollContainer = o._side_scroll
	for c: Node in o._extras.find_children("*", "CardList", true, false):
		var list: CardList = c as CardList
		if list.is_visible_in_tree():
			var top: float = list.get_global_rect().position.y
			var view_end: float = scroll.get_global_rect().end.y
			for edge: float in list.row_bottoms():
				if top + edge > view_end and top + edge - view_end < 40.0:
					(
						assert_bool(top + edge <= view_end + 0.5)
						. override_failure_message(
							"a card row is cut by the column: %s past %s" % [top + edge, view_end]
						)
						. is_true()
					)
	_drop(o)


# FT: FT-HLM-003
func test_the_helm_site_label_and_the_phone_compass_chip_stay_near_their_marker() -> void:
	var s: StationScreen = await _screen(LAYOUTS[2], "helm")
	var hud: HelmHud = (s.focused_panel() as HelmPanel).hud
	assert_float(hud._label_reach()).is_equal_approx(32.0, 0.01)
	var font: Font = hud.get_theme_default_font()
	var inside: Rect2 = Rect2(Vector2.ZERO, hud.size)
	for fx: float in [0.1, 0.5, 0.9]:
		for fy: float in [0.2, 0.5, 0.8]:
			var at: Vector2 = hud.size * Vector2(fx, fy)
			var box: Rect2 = hud.label_rect(font, "Kappa 4.7 km", at, 10.0)
			if inside.encloses(box):
				assert_float(ChipLayout.gap_to(box, at)).is_less_equal(32.0 + 0.5)
	_drop(s)
	var p: StationScreen = await _screen(LAYOUTS[6], "helm")
	var phud: HelmHud = (p.focused_panel() as HelmPanel).hud
	var ids: Array = p.ctx.interp.contact_ids()
	assert_bool(ids.is_empty()).is_false()
	for id: int in ids:
		p.ctx.crew.select("contact", id)
		for i: int in 2:
			await get_tree().process_frame
		var local: Variant = p.ctx.selection_local()
		if not local is Vector3:
			continue
		var dot: Vector2 = (
			phud._compass_centre() + HelmHud.compass_point(local, HelmHud.COMPASS_R - 6.0)
		)
		var chip: Rect2 = phud.compass_boxes()[1]
		(
			assert_float(ChipLayout.gap_to(chip, dot))
			. override_failure_message(
				"contact %d: compass chip %s far from its dot %s" % [id, chip, dot]
			)
			. is_less_equal(48.0)
		)
	_drop(p)


# FT: FT-ENG-001
func test_the_cutaway_keeps_200_px_and_no_crew_token_sits_on_a_disc() -> void:
	for layout: Array in [LAYOUTS[1], LAYOUTS[2], LAYOUTS[5]]:
		var s: StationScreen = await _screen(layout, "engineering")
		var panel: EngineeringPanel = s.focused_panel() as EngineeringPanel
		if LayoutMode.is_phone(s.form):
			panel.pages.current = 1
			for i: int in 3:
				await get_tree().process_frame
		var cut: EngineeringCutaway = panel.cutaway
		var where: String = "%s" % [layout[0]]
		var area: Vector2 = Vector2(cut.size.x, cut.size.y - cut.hint_height())
		(
			assert_bool(area.x >= 199.0 and area.y >= 199.0)
			. override_failure_message("%s: area %s" % [where, area])
			. is_true()
		)
		for c: int in panel.crew_count():
			if panel.crew_job(c) < 0:
				continue
			for i: int in panel.count():
				(
					assert_float(cut.token_pos(c).distance_to(cut.subsystem_pos(i)))
					. override_failure_message("%s: token %d on disc %d" % [where, c, i])
					. is_greater_equal(cut.node_r() + EngineeringCutaway.TOKEN_R)
				)
		_drop(s)


# FT: FT-STN-010
func test_crew_page_words_fit_their_buttons_and_no_row_is_cut() -> void:
	var s: StationScreen = await _screen(LAYOUTS[5], "relay")
	var relay: RelayPanel = s.focused_panel() as RelayPanel
	relay.pages.current = 4
	for i: int in 4:
		await get_tree().process_frame
	var crew: CrewPage = relay.phone.crew
	var font: Font = crew.get_theme_default_font()
	var view: Rect2 = crew.get_global_rect()
	for b: Node in crew.grid.get_children():
		var button: RailButton = b as RailButton
		var fs: int = button.get_theme_font_size("font_size")
		var room: float = button.size.x - button.get_theme_stylebox("normal").get_minimum_size().x
		for word: String in button.text.split(" ", false):
			(
				assert_float(font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
				. override_failure_message("'%s' wider than its button (%s)" % [word, room])
				. is_less_equal(room)
			)
		var r: Rect2 = button.get_global_rect()
		if view.intersects(r):
			(
				assert_bool(view.grow(0.5).encloses(r))
				. override_failure_message(
					"button '%s' %s cut by the page %s" % [button.text, r, view]
				)
				. is_true()
			)
	_drop(s)
