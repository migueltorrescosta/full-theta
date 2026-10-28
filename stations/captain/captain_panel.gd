class_name CaptainPanel
extends StationPanel
## The Captain's seat (§5.7, FT-CPT-001 to FT-CPT-005, D54): a mirror of the main screen
## (a ViewerPanel on the same state, taking clicks), buttons or keys 1 to 5 for its view,
## pings and marks, and a right column with the read-only list of open request chips
## (ChipList) and Comms' mission and contract cards (CardList, the COMMS block).
## Information only: the only things it sends are the main-screen view (MainView), pings
## and marks into empty slots (the server refuses anything else, FT-SPA-013, FT-CPT-003).
## A ping on a card shows it on the main screen for 10 s or until the next ping.

const SIDE_WIDTH: float = 330.0
const BUTTON_HEIGHT: float = 44.0
## Under this width (a phone or a tablet upright, D195) the mirror and the right column
## stack and scroll.
const NARROW_W: float = 760.0
const STACK_MIRROR_H: float = 320.0
const STACK_SIDE_H: float = 520.0
## A phone on its side: the width of the right rail with the chips and cards.
const PHONE_LISTS_W: float = 220.0

var mirror: ViewerPanel
var chips: ChipList
var cards: CardList
## One button per MainScreen.View, in order.
var buttons: Array[Button] = []

## The phone-landscape arrangement (#28, docked rails like Weapons B): the view buttons in a
## rail at the left edge, the mirror in the middle, the chips and cards in a rail at the
## right edge. Made on first use.
var touch_layout: RailLayout = null

var _scroll: ScrollContainer
var _left: VBoxContainer
var _row: Control
var _cols: BoxContainer
var _side: VBoxContainer
## The right rail's lists scroll when they outgrow it (a phone on its side).
var _lists: ScrollContainer


func full_screen() -> bool:
	return true


func radar_orbitable() -> bool:
	return false


func _setup() -> void:
	clip_contents = true
	var cols: BoxContainer = BoxContainer.new()
	_cols = cols
	cols.add_theme_constant_override("separation", 8)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	_scroll = scroll
	scroll.add_child(cols)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	_left = left
	mirror = ViewerPanel.new()
	mirror.interactive = true
	mirror.setup(ctx, StationViews.VIEWER)
	mirror.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(mirror)
	_row = HFlowContainer.new()
	_row.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_row)
	for i: int in MainScreen.NAMES.size():
		var b: Button = Button.new()
		b.text = tr("view." + MainScreen.NAMES[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(88, 0)
		b.pressed.connect(set_view.bind(i))
		_row.add_child(b)
		buttons.append(b)
	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.add_theme_constant_override("separation", 12)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(side)
	_side = side
	chips = ChipList.new()
	side.add_child(chips)
	cards = CardList.new()
	side.add_child(cards)
	resized.connect(_stack)
	_stack()


## True when the panel takes the phone-landscape arrangement: a phone on its side.
func phone_landscape() -> bool:
	return is_inside_tree() and LayoutMode.form_of(self) == LayoutMode.Form.PHONE_LANDSCAPE


## Moves the buttons, mirror and lists into the rails on a phone on its side, back elsewhere.
func _arrange_rails() -> void:
	var rails: bool = phone_landscape()
	if rails == (touch_layout != null and touch_layout.visible):
		return
	if rails:
		if touch_layout == null:
			touch_layout = RailLayout.new()
			touch_layout.docked = true
			touch_layout.offset_top = UiTheme.TOUCH_GAP
			add_child(touch_layout)
			touch_layout.rail(SIDE_LEFT)
			touch_layout.rail(SIDE_RIGHT).custom_minimum_size.x = PHONE_LISTS_W
			_lists = ScrollContainer.new()
			_lists.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			_lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
			touch_layout.right.add(_lists)
			var box: VBoxContainer = VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
			_lists.add_child(box)
		touch_layout.visible = true
		_scroll.visible = false
		var gap: MarginContainer = MarginContainer.new()
		for side: String in ["margin_left", "margin_right"]:
			gap.add_theme_constant_override(side, UiTheme.TOUCH_GAP)
		mirror.reparent(gap, false)
		touch_layout.set_content(gap)
		for b: Button in buttons:
			b.reparent(touch_layout.left.box, false)
			b.custom_minimum_size = Vector2(0, UiTheme.TOUCH_PRIMARY)
		for c: Control in [chips, cards]:
			c.reparent(_lists.get_child(0), false)
	else:
		touch_layout.visible = false
		_scroll.visible = true
		var gap: Control = mirror.get_parent()
		mirror.reparent(_left, false)
		_left.move_child(mirror, 0)
		touch_layout.remove_child(gap)
		gap.queue_free()
		for b: Button in buttons:
			b.reparent(_row, false)
			b.custom_minimum_size = Vector2(88, 0)
		for c: Control in [chips, cards]:
			c.reparent(_side, false)


## Narrow: the mirror above the right column, scrolling; wide: side by side.
func _stack() -> void:
	_arrange_rails()
	# A phone upright: touch-sized view buttons 8 px apart (#28).
	var upright: bool = (
		is_inside_tree() and LayoutMode.form_of(self) == LayoutMode.Form.PHONE_PORTRAIT
	)
	for c: String in ["h_separation", "v_separation"]:
		if upright:
			_row.add_theme_constant_override(c, UiTheme.TOUCH_GAP)
		else:
			_row.remove_theme_constant_override(c)
	if not (touch_layout != null and touch_layout.visible):
		for b: Button in buttons:
			b.custom_minimum_size.y = UiTheme.TOUCH_PRIMARY if upright else 0.0
	var narrow: bool = size.x < NARROW_W
	_cols.vertical = narrow
	# In the rails the mirror takes the height it gets: never past the bottom inset.
	var rails: bool = touch_layout != null and touch_layout.visible
	mirror.custom_minimum_size.y = STACK_MIRROR_H if narrow and not rails else 0.0
	_side.custom_minimum_size = Vector2(0, STACK_SIDE_H) if narrow else Vector2(SIDE_WIDTH, 0)


func _process(_delta: float) -> void:
	var view: int = ctx.crew.main_view
	for i: int in buttons.size():
		buttons[i].set_pressed_no_signal(i == view)
	chips.show_rows(ChipList.open_rows(ctx.view))
	cards.setup(CardList.rows(ctx.view, [CardList.MISSION, CardList.CONTRACT]))
	cards.highlight = ctx.crew.shown_card(ctx.now_ms())
	cards.queue_redraw()


## Asks the server to switch the main screen's view (MainScreen.View).
func set_view(view: int) -> void:
	ctx.intents.set_main_view(view)


## Keys 1 to 5 pick a view, Tab or the d-pad step through them.
func handle_intent(event: Dictionary) -> bool:
	var id: String = str(event.get("id", ""))
	if not bool(event.get("pressed", true)):
		return false
	if id.begins_with("captain_view_") and id.trim_prefix("captain_view_").is_valid_int():
		set_view(id.trim_prefix("captain_view_").to_int() - 1)
		return true
	var count: int = MainScreen.NAMES.size()
	match id:
		"captain_view_next":
			set_view((ctx.crew.main_view + 1) % count)
		"captain_view_prev":
			set_view((ctx.crew.main_view + count - 1) % count)
		_:
			return false
	return true


## A card in the list, else what the mirror shows under the point.
func item_at(pos: Vector2) -> Dictionary:
	var on_cards: Vector2 = pos - (cards.global_position - global_position)
	var card: int = cards.card_at(on_cards)
	if card >= 0:
		return {"kind": "card", "id": card}
	return mirror.item_at(pos - (mirror.global_position - global_position))
