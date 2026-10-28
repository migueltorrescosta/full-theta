class_name CaptainPhone
extends Control
## The Captain on a phone (#28 follow-up, design 2.7, D287): a persistent rail of view
## buttons (Forward / Chase, Tactical / Target, Status, Ping / Mark) and the main-screen
## mirror filling the rest; pages Screen (the mirror alone), Requests (the open request
## chips, read-only, FT-CPT-004) and Cards (Comms' mission and contract cards, the pinged
## one lit) as a panel over the mirror's right part. No Crew page: the Captain sends no
## chips, shares nothing and sets no alert (FT-STN-008). On its side the rail docks at the
## left; upright the buttons sit in a grid under the mirror and the tabs in the screen's
## bottom tab bar.
##
## CaptainPanel builds it and moves its mirror, chip list and card list in (`stage`, the
## list panels) and takes them back when the phone becomes a tablet or a desktop.

## The docked rail's width on its side (design 1: 168 px, two 80 px half buttons).
const RAIL_W: float = 168.0
## The lists' panel over the mirror on its side (design 1.4: x 489-797).
const LISTS_W: float = 308.0
## The buttons' text size (px).
const FONT: int = 14
## Upright: view and common buttons per grid row.
const UPRIGHT_COLUMNS: int = 4
## A finger lifted this close (px) and this soon (ms) after it went down on a card is a tap.
const TAP_SLOP_PX: float = 12.0
const TAP_MS: int = 450

var panel: CaptainPanel
var upright: bool = false
## On its side: the docked rail and the mirror; null upright.
var layout: RailLayout = null
## The mirror's area; the list panels float over its right part (upright: all of it).
var stage: Control = Control.new()
## The Requests page's panel (the ChipList) and the Cards page's (the CardList).
var requests: PanelContainer = PanelContainer.new()
var card_box: PanelContainer = PanelContainer.new()
## "view_0" to "view_4" (MainScreen.View), "ping", "mark".
var buttons: Dictionary = {}
var pages: PageHost = PageHost.new()

var _down_at: Vector2 = Vector2.ZERO
var _down_ms: int = -1


func _init(owner_panel: CaptainPanel = null, is_upright: bool = false) -> void:
	panel = owner_panel
	upright = is_upright
	name = "CaptainPhone"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	var views: Array[RailButton] = []
	for i: int in MainScreen.NAMES.size():
		var b: RailButton = _button("view_%d" % i, tr("view." + MainScreen.NAMES[i]))
		b.toggle_mode = true
		b.pressed.connect(func() -> void: panel.set_view(i))
		views.append(b)
	var ping: RailButton = _button("ping", tr("intent.ping"))
	ping.pressed.connect(func() -> void: panel.common_requested.emit("ping"))
	var mark: RailButton = _button("mark", tr("intent.mark"))
	mark.pressed.connect(func() -> void: panel.common_requested.emit("mark"))
	if upright:
		_build_upright(views, ping, mark)
	else:
		_build_side(views, ping, mark)
	for box: PanelContainer in [requests, card_box]:
		box.theme_type_variation = "OverlayRail"
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		stage.add_child(box)
	requests.name = "Requests"
	card_box.name = "Cards"
	card_box.gui_input.connect(_on_cards_input)
	pages.add_page(TouchText.of("page.screen", "Screen"), [])
	pages.add_page(TouchText.of("page.requests", "Requests"), [requests])
	pages.add_page(TouchText.of("page.cards", "Cards"), [card_box])


## Takes the mirror and the lists in.
func adopt(mirror: ViewerPanel, chips: ChipList, cards: CardList) -> void:
	mirror.reparent(stage, false)
	stage.move_child(mirror, 0)
	mirror.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mirror.custom_minimum_size = Vector2.ZERO
	for pair: Array in [[chips, requests], [cards, card_box]]:
		var list: Control = pair[0]
		var scroll: ScrollContainer = (pair[1] as PanelContainer).get_child(0)
		list.reparent(scroll, false)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The mirror's area in the panel's coordinates (the view-top row goes on top of it).
func stage_rect() -> Rect2:
	var xf: Transform2D = panel.get_global_transform().affine_inverse()
	return xf * stage.get_global_rect()


## Places the list panels over the mirror: under the view-top row (`reserve`, px from the
## panel's top), above the bottom band, inside the safe area; on its side the right
## LISTS_W px, upright the whole mirror.
func place(reserve: float) -> void:
	var at: Rect2 = Rect2(Vector2.ZERO, stage.size)
	var tap: Rect2 = SafeArea.to_local(stage, SafeArea.tap_rect(stage)).intersection(at)
	var top: float = maxf(reserve - stage_rect().position.y, 0.0)
	var r: Rect2 = Rect2(tap.position.x, top, tap.size.x, tap.end.y - top)
	if not upright:
		var w: float = minf(LISTS_W, tap.end.x)
		r = Rect2(tap.end.x - w, top, w, tap.end.y - top)
	for box: PanelContainer in [requests, card_box]:
		if box.position != r.position or box.size != r.size:
			box.position = r.position
			box.size = r.size


## The view buttons follow the main screen's view.
func show_view(view: int) -> void:
	for i: int in MainScreen.NAMES.size():
		(buttons["view_%d" % i] as RailButton).set_pressed_no_signal(i == view)


## True when `pos` (panel coordinates) is over a shown list panel.
func over_lists(pos: Vector2) -> bool:
	var global: Vector2 = panel.get_global_transform() * pos
	for box: PanelContainer in [requests, card_box]:
		if box.is_visible_in_tree() and box.get_global_rect().has_point(global):
			return true
	return false


func _button(id: String, label: String) -> RailButton:
	var b: RailButton = RailButton.make(label)
	b.name = "Captain_" + id
	# Two to a 168 px rail: labels wrap at 14 px rather than trim ("Place mark").
	b.add_theme_font_size_override("font_size", FONT)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	buttons[id] = b
	return b


## On its side: the docked left rail (design 2.7) and the mirror beside it.
func _build_side(views: Array[RailButton], ping: RailButton, mark: RailButton) -> void:
	layout = RailLayout.new()
	layout.docked = true
	layout.offset_top = UiTheme.TOUCH_GAP
	add_child(layout)
	var rail: TouchRail = layout.rail(SIDE_LEFT)
	rail.custom_minimum_size.x = RAIL_W
	var empty: Control = Control.new()
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row: Array in [[views[0], views[1]], [views[2], views[3]], [views[4], empty], [ping, mark]]:
		rail.add_row(row)
	var gap: MarginContainer = MarginContainer.new()
	gap.add_theme_constant_override("margin_left", UiTheme.TOUCH_GAP)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.add_child(stage)
	layout.set_content(gap)


## Upright: the mirror over a grid of the seven buttons, 48 px tall, 8 px apart.
func _build_upright(views: Array[RailButton], ping: RailButton, mark: RailButton) -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = UiTheme.TOUCH_GAP
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stage)
	var grid: GridContainer = GridContainer.new()
	grid.name = "Grid"
	grid.columns = UPRIGHT_COLUMNS
	grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	grid.add_to_group(TouchInput.GROUP)
	col.add_child(grid)
	for b: RailButton in views + [ping, mark]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)


## A tap on a card pings it (FT-CPT-005): the main screen shows it for 10 s.
func _on_cards_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var now: int = panel.ctx.now_ms()
	if mb.pressed:
		_down_at = mb.position
		_down_ms = now
		return
	var tap: bool = (
		_down_ms >= 0
		and now - _down_ms <= TAP_MS
		and mb.position.distance_to(_down_at) <= TAP_SLOP_PX
	)
	_down_ms = -1
	if not tap:
		return
	var at: Vector2 = (
		panel.cards.get_global_transform().affine_inverse()
		* (card_box.get_global_transform() * mb.position)
	)
	var card: int = panel.cards.card_at(at)
	if card >= 0:
		panel.ctx.ping_item({"kind": "card", "id": card})
