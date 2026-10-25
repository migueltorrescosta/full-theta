class_name CaptainPanel
extends StationPanel
## The Captain's seat (§5.7, FT-CPT-001 to FT-CPT-005, D54): a mirror of the main screen
## (a ViewerPanel on the same state, taking clicks), buttons or keys 1 to 5 for its view,
## pings and marks, and a right column with the read-only list of open request chips
## (ChipList) and Comms' mission and contract cards (FixtureCards, fixtures until #10).
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

var mirror: ViewerPanel
var chips: ChipList
var cards: FixtureCards
## One button per MainScreen.View, in order.
var buttons: Array[Button] = []

var _row: Control
var _cols: BoxContainer
var _side: VBoxContainer


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
	scroll.add_child(cols)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
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
	cards = FixtureCards.new()
	cards.setup()
	side.add_child(cards)
	resized.connect(_stack)
	_stack()


## Narrow: the mirror above the right column, scrolling; wide: side by side.
func _stack() -> void:
	var narrow: bool = size.x < NARROW_W
	_cols.vertical = narrow
	mirror.custom_minimum_size.y = STACK_MIRROR_H if narrow else 0.0
	_side.custom_minimum_size = Vector2(0, STACK_SIDE_H) if narrow else Vector2(SIDE_WIDTH, 0)


func _process(_delta: float) -> void:
	var view: int = ctx.crew.main_view
	for i: int in buttons.size():
		buttons[i].set_pressed_no_signal(i == view)
	chips.show_rows(ChipList.open_rows(ctx.view))
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
