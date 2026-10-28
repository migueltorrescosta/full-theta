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

var mirror: ViewerPanel
var chips: ChipList
var cards: CardList
## One button per MainScreen.View, in order.
var buttons: Array[Button] = []

## The phone arrangement (#28 follow-up, design 2.7): CaptainPhone, made for the phone's
## orientation and remade when it turns; null on a tablet or a desktop.
var phone: CaptainPhone = null

var _scroll: ScrollContainer
var _left: VBoxContainer
var _row: Control
var _cols: BoxContainer
var _side: VBoxContainer
## The form `phone` was built for; -1 for none.
var _phone_form: int = -1


func full_screen() -> bool:
	return true


func radar_orbitable() -> bool:
	return false


func _setup() -> void:
	clip_contents = true
	in_frame = true
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


## The phone arrangement is built before the screen lays out (its _ready and its
## size_changed handler run after the panel's), so the screen binds the new pages' tabs.
func _ready() -> void:
	get_viewport().size_changed.connect(_stack)
	_stack()


## Builds the phone arrangement for a phone either way up (CaptainPhone, with pages), and
## puts the mirror and lists back in the tablet and desktop columns elsewhere.
func _arrange_phone() -> void:
	var form: int = LayoutMode.form_of(self) if is_inside_tree() else -1
	if form != LayoutMode.Form.PHONE_LANDSCAPE and form != LayoutMode.Form.PHONE_PORTRAIT:
		form = -1
	if form == _phone_form:
		return
	_phone_form = form
	if phone != null:
		mirror.reparent(_left, false)
		_left.move_child(mirror, 0)
		mirror.set_anchors_preset(Control.PRESET_TOP_LEFT)
		for c: Control in [chips, cards]:
			c.reparent(_side, false)
		remove_child(phone)
		phone.queue_free()
		phone = null
		pages = null
	_scroll.visible = form < 0
	if form >= 0:
		phone = CaptainPhone.new(self, form == LayoutMode.Form.PHONE_PORTRAIT)
		add_child(phone)
		phone.adopt(mirror, chips, cards)
		pages = phone.pages


## Narrow: the mirror above the right column, scrolling; wide: side by side.
func _stack() -> void:
	_arrange_phone()
	if phone != null:
		return
	var narrow: bool = size.x < NARROW_W
	_cols.vertical = narrow
	mirror.custom_minimum_size.y = STACK_MIRROR_H if narrow else 0.0
	_side.custom_minimum_size = Vector2(0, STACK_SIDE_H) if narrow else Vector2(SIDE_WIDTH, 0)


## The Captain's phone help (P28-Help): per page, the controls in the 844x390 frame on its
## side (insets 47, 0, 47, 21) with what each does. The rail is on the first page only.
static func touch_help() -> Array:
	# The rail: x 47-215, rows from y 72 (the top bar's 56 px, the frame's 8 px gap and the
	# rail's own 8 px).
	var x0: float = 47.0
	var half: float = (CaptainPhone.RAIL_W - UiTheme.TOUCH_GAP) / 2.0
	var rows: Array = [
		["view_0", "view_1", "forward", "Forward", "chase", "Chase"],
		["view_2", "view_3", "tactical", "Tactical", "target", "Target"],
		["view_4", "", "status", "Status", "", ""],
	]
	var boxes: Array = []
	var y: float = 72.0
	for r: Array in rows:
		for k: int in 2:
			if r[2 + 2 * k] == "":
				continue
			var at: Rect2 = Rect2(
				x0 + k * (half + UiTheme.TOUCH_GAP), y, half, UiTheme.TOUCH_PRIMARY
			)
			var label: String = TranslationServer.translate("view." + str(r[2 + 2 * k]))
			var what: String = TouchText.of("help.captain.view", "Show this on the main screen")
			boxes.append([at, label, what])
		y += UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP
	(
		boxes
		. append(
			[
				Rect2(x0, y, half, UiTheme.TOUCH_PRIMARY),
				TranslationServer.translate("intent.ping"),
				TouchText.of("help.captain.ping", "Ping the selection for everyone"),
			]
		)
	)
	(
		boxes
		. append(
			[
				Rect2(x0 + half + UiTheme.TOUCH_GAP, y, half, UiTheme.TOUCH_PRIMARY),
				TranslationServer.translate("intent.mark"),
				TouchText.of("help.captain.mark", "Mark the selection (free slots only)"),
			]
		)
	)
	(
		boxes
		. append(
			[
				Rect2(223.0, 72.0, 574.0, 297.0),
				TouchText.of("help.captain.mirror_label", "Main screen"),
				TouchText.of(
					"help.captain.mirror", "Tap to select; hold to ping, hold and drag to mark"
				),
			]
		)
	)
	var lists: Rect2 = Rect2(489.0, 72.0, 308.0, 297.0)
	return [
		{"page": TouchText.of("page.screen", "Screen"), "boxes": boxes},
		{
			"page": TouchText.of("page.requests", "Requests"),
			"boxes":
			[
				[
					lists,
					TranslationServer.translate("captain.chips"),
					TouchText.of("help.captain.requests", "Who asked whom for what, read-only"),
				]
			],
		},
		{
			"page": TouchText.of("page.cards", "Cards"),
			"boxes":
			[
				[
					lists,
					TranslationServer.translate("captain.cards"),
					TouchText.of("help.captain.cards", "Tap a card to show it on the main screen"),
				]
			],
		},
	]


func _process(_delta: float) -> void:
	var view: int = ctx.crew.main_view
	for i: int in buttons.size():
		buttons[i].set_pressed_no_signal(i == view)
	if phone != null:
		phone.show_view(view)
		phone.place(top_reserve)
		mirror.top_reserve = maxf(top_reserve - phone.stage_rect().position.y, 0.0)
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


## On a phone: the mirror's area, under the view-top row.
func view_rect() -> Rect2:
	if phone != null:
		return phone.stage_rect()
	return super()


## A card in the list, else what the mirror shows under the point (on a phone, nothing
## under a shown list panel but its cards).
func item_at(pos: Vector2) -> Dictionary:
	var on_cards: Vector2 = pos - (cards.global_position - global_position)
	var card: int = cards.card_at(on_cards) if cards.is_visible_in_tree() else -1
	if card >= 0:
		return {"kind": "card", "id": card}
	if phone != null and phone.over_lists(pos):
		return {}
	return mirror.item_at(pos - (mirror.global_position - global_position))
