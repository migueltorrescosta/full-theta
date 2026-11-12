class_name EngineeringPhone
extends RefCounted
## Engineering on a phone (#28 follow-up, design 2.3, D287; R13-5): a docked thumb rail at the
## screen's left edge (upright a grid above the pages) with every board action, two to a row;
## the pages Power (the board), Ship (the cutaway), Faults (the lists) and Crew beside it. The
## board, cutaway and lists are the panel's own: `place_lists` moves them onto the pages on a
## phone and back into the desktop and tablet arrangement elsewhere. Every button sends its
## intent as the key or the pad does (EngineeringPanel.press_touch).

## Below this width (px) the lists sit under the cutaway instead of in a column of
## their own (150 % UI scale, FT-STN-013).
const NARROW: float = 760.0
## Under this width (a phone, D195) the cutaway, the board and the lists stack and scroll.
const PHONE_W: float = 560.0
## Narrow and under this height (px, a desktop at 150 %), the faults list is compact.
const SHORT_H: float = 520.0
## The docked thumb rail's width at the screen's left edge (the screen's radar column stays,
## P28-E2): two buttons to a row, wide enough for a verb and its object (C3).
const PHONE_RAIL_W: float = 224.0
## Upright, the rail's buttons in a grid of this many columns.
const GRID_COLUMNS: int = 3

var panel: EngineeringPanel
## The phone arrangement on its side (#28 follow-up): the docked rail and the pages; hidden
## elsewhere.
var touch_layout: RailLayout = null
## Intent id -> its rail button on a phone on its side.
var touch_buttons: Dictionary = {}
## Intent id -> its button in the upright grid.
var grid_buttons: Dictionary = {}
var crew_page: CrewPage = null
## The phone's pages: the box under the view-top row (its top margin follows top_reserve),
## one full-size page control each (Power scrolls the board), and upright the button grid.
var pages_box: MarginContainer

var _page_ctl: Array[Control] = []
var _board_page: ScrollContainer
var _upright: VBoxContainer
var _grid: GridContainer


func _init(p: EngineeringPanel) -> void:
	panel = p


## The phone's pages (built in the panel's _setup, so the screen binds them at once): Power
## (the board, scrolling only when the view-top row grows), Ship (the cutaway), Faults (the
## lists) and Crew. Only the page controls take part in the pages: the board, cutaway and
## lists move into them on a phone and back out elsewhere.
func build_pages() -> void:
	pages_box = MarginContainer.new()
	pages_box.name = "Pages"
	pages_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# (a hidden child until the phone arrangement takes it: never an orphan on a desktop)
	pages_box.visible = false
	panel.add_child(pages_box)
	var area: Control = Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages_box.add_child(area)
	_board_page = ScrollContainer.new()
	_board_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	crew_page = CrewPage.new(panel)
	crew_page.name = "CrewPage"
	panel.pages = PageHost.new()
	var titles: Array[String] = [
		panel.tr("eng.power"),
		TouchText.of("eng.touch.ship", "Ship"),
		panel.tr("eng.faults"),
		TouchText.of("page.crew", "Crew"),
	]
	for i: int in titles.size():
		var page: Control = crew_page if i == EngineeringPanel.Page.CREW else _board_page
		if i == EngineeringPanel.Page.SHIP or i == EngineeringPanel.Page.FAULTS:
			page = Control.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if page != crew_page and page != _board_page:
			page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(page)
		_page_ctl.append(page)
		panel.pages.add_page(titles[i], [page])
	panel.pages.page_changed.connect(panel._on_page)


## The rail on its side (two to a row) and the upright grid, each a full set of the buttons;
## a hidden button (EngineeringRail.update) leaves no gap: the grids close up in order.
func _build_rails() -> void:
	touch_layout = RailLayout.new()
	touch_layout.name = "TouchLayout"
	touch_layout.docked = true
	# 8 px from the top bar and from the rail (UiTheme.TOUCH_GAP between targets).
	touch_layout.offset_top = UiTheme.TOUCH_GAP
	panel.add_child(touch_layout)
	var rail: TouchRail = touch_layout.rail(SIDE_LEFT)
	rail.custom_minimum_size.x = PHONE_RAIL_W
	var pairs: GridContainer = GridContainer.new()
	pairs.name = "RailGrid"
	pairs.columns = 2
	pairs.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	pairs.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	rail.add(pairs)
	for a: Array in EngineeringPanel.TOUCH_ACTIONS:
		var b: RailButton = rail_button(panel, a)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		touch_buttons[a[0]] = b
		pairs.add_child(b)
	_upright = VBoxContainer.new()
	_upright.name = "Upright"
	_upright.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upright.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_upright.offset_top = UiTheme.TOUCH_GAP
	_upright.visible = false
	panel.add_child(_upright)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	_upright.add_child(_grid)
	for a: Array in EngineeringPanel.TOUCH_ACTIONS:
		var b: RailButton = rail_button(panel, a)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_buttons[a[0]] = b
		_grid.add_child(b)


## A button of `a` (a TOUCH_ACTIONS entry) that runs `p`'s intent (the rails and the tablet's).
static func rail_button(p: EngineeringPanel, a: Array) -> RailButton:
	var b: RailButton = RailButton.make(TouchText.of(a[1], a[2]))
	b.name = "Touch_" + str(a[0])
	# Two lines of text (the part or the reason under the label) in a 48 px row; the text
	# size fits the widest line (EngineeringRail.fit).
	b.theme_type_variation = "RailCompactButton"
	b.pressed.connect(p.press_touch.bind(str(a[0])))
	return b


## The phone arrangement for the panel's form, else the desktop and tablet one.
func place_lists() -> void:
	if panel.ctx == null:
		return
	var f: LayoutMode.Form = panel.phone_form()
	if f != LayoutMode.Form.DESKTOP:
		_to_phone(f == LayoutMode.Form.PHONE_LANDSCAPE)
		return
	_from_phone()


## Moves the board, cutaway and lists onto the pages, beside the rail on its side or under
## the grid upright.
func _to_phone(sideways: bool) -> void:
	if touch_layout == null:
		_build_rails()
	panel._scroll_all.visible = false
	touch_layout.visible = sideways
	_upright.visible = not sideways
	var home: Control = touch_layout if sideways else _upright
	pages_box.visible = true
	if pages_box.get_parent() != home:
		if pages_box.get_parent() != null:
			pages_box.get_parent().remove_child(pages_box)
		if sideways:
			touch_layout.set_content(pages_box)
		else:
			_upright.add_child(pages_box)
	pages_box.add_theme_constant_override("margin_left", UiTheme.TOUCH_GAP if sideways else 0)
	var board: EngineeringBoard = panel.board
	var cutaway: EngineeringCutaway = panel.cutaway
	for pair: Array in [
		[board, _board_page],
		[cutaway, _page_ctl[EngineeringPanel.Page.SHIP]],
		[panel._side, _page_ctl[EngineeringPanel.Page.FAULTS]]
	]:
		var c: Control = pair[0]
		var page: Control = pair[1]
		if c.get_parent() != page:
			c.get_parent().remove_child(c)
			page.add_child(c)
		c.visible = true
		if page != _board_page:
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.custom_minimum_size = Vector2(0.0, EngineeringBoard.PHONE_H)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cutaway.custom_minimum_size = Vector2.ZERO
	panel._side.custom_minimum_size = Vector2.ZERO
	fit_pages()


## Puts the board, cutaway and lists back in the desktop and tablet arrangement.
func _from_phone() -> void:
	var board: EngineeringBoard = panel.board
	var cutaway: EngineeringCutaway = panel.cutaway
	var side: PanelContainer = panel._side
	var box: MarginContainer = panel._side_box
	var left: VBoxContainer = panel._left
	var row: BoxContainer = panel._row
	if touch_layout != null and (touch_layout.visible or _upright.visible):
		touch_layout.visible = false
		_upright.visible = false
		pages_box.visible = false
		panel._scroll_all.visible = true
		for c: Control in [cutaway, board, side]:
			c.get_parent().remove_child(c)
			c.visible = true
			c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		left.add_child(cutaway)
		left.move_child(cutaway, 0)
		row.add_child(board)
		row.move_child(board, left.get_index() + 1)
		box.add_child(side)
		cutaway.visible = not panel.docked
		side.visible = not panel.docked
		box.visible = not panel.docked
	var narrow: bool = panel.size.x < NARROW
	var phone: bool = panel.size.x < PHONE_W
	row.vertical = phone
	cutaway.custom_minimum_size.y = 260.0 if phone else 0.0
	board.fit(0.0 if phone or panel.docked else panel.size.y)
	board.custom_minimum_size = (Vector2(0, 460) if phone else Vector2(270, board.content_height()))
	side.custom_minimum_size = Vector2(0, 220) if phone else Vector2(210, 0)
	var parent: Control = left if narrow else row
	# Under the cutaway (narrow) the faults share the column's height evenly with it, so
	# they show more than their first line at 150 %.
	box.size_flags_stretch_ratio = cutaway.size_flags_stretch_ratio if narrow else 2.2
	panel.compact_lists = narrow and not phone and panel.size.y < SHORT_H
	# Under the cutaway the box sits at the screen's left and bottom edges: keep it off them.
	var gap: int = UiTheme.TOUCH_GAP if narrow else 0
	for m: String in ["margin_left", "margin_right", "margin_bottom"]:
		if box.get_theme_constant(m) != gap:
			box.add_theme_constant_override(m, gap)
	if box.get_parent() != parent:
		box.get_parent().remove_child(box)
		parent.add_child(box)


## The pages start under the view-top row (top_reserve) and end above the gesture band.
func fit_pages() -> void:
	if pages_box == null or not pages_box.is_inside_tree():
		return
	var tap: Rect2 = SafeArea.to_local(panel, SafeArea.tap_rect(panel))
	var band: float = maxf(panel.size.y - tap.end.y, 0.0)
	var top: int = roundi(panel.top_reserve)
	var bottom: int = roundi(band)
	if pages_box.get_theme_constant("margin_top") != top:
		pages_box.add_theme_constant_override("margin_top", top)
	if pages_box.get_theme_constant("margin_bottom") != bottom:
		pages_box.add_theme_constant_override("margin_bottom", bottom)
	panel.update_rails()
