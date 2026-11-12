class_name CommsPanel
extends StationPanel
## Comms (§5.6, D53, D87; FT-COM-001 to FT-COM-009): the card board (CommsBoard) of missions,
## contracts, and offers with hails, and a card's conversation over it (CommsOverlay).
## Comms alone accepts and declines cards (FT-COM-003), trades (FT-COM-004) and buys and
## sells modules while docked (FT-COM-009); a conversation's replies need its claim, which
## the server takes for a free one (FT-COM-006). Docked in a joint view the panel is the list
## of the ship's live cards (CardList), the Comms half of Approach, Parley, Quartermaster
## and Intel (FT-CPT-004).
##
## KB/M: click a card, or the arrows then O, to open it; Tab the next column; H hails the
## selected contact; B asks Weapons to hold fire on it (a request chip, P9); in the overlay
## 1 to 4 reply, Up and Down move the focus over the trade lines, E buys one, X sells one;
## Esc closes the overlay; Enter and Backspace accept and decline the card; K claims its
## conversation; middle-click pings the card's contact. Controller: d-pad or left stick move
## between cards and columns (and over the lines of the overlay), A opens a card or does the
## focused line, B closes the overlay, LB hails, RT buys, LT sells; X and Y accept and
## decline, View+X claims, View+Y asks for hold fire. Touch: tap a card to open it, swipe to
## change column, tap a reply or a trade line, tap outside or swipe down to close, the
## buttons under the board for the rest.
##
## On a phone (#28 follow-up, D287, design 2.6) the five buttons are a persistent rail (on
## its side a docked left rail, upright a row under the board) and the board's columns are
## pages: Missions (rest), Contracts, Hails (a dot on the tab while a hail waits), Rep (the
## docked site, credits, hull and reputation, off the board) and Crew. On its side the
## conversation covers the board and the radar column, the rail staying live.

enum Page { MISSIONS, CONTRACTS, HAILS, REP, CREW }

## A stick must pass this to count as a move, and fall under RELEASE to re-arm.
const STICK_MOVE: float = 0.6
const STICK_RELEASE: float = 0.3
## Panels narrower than this (a portrait phone) shrink the button bar.
const NARROW_BAR: float = 420.0
## The reason words a refusal event may carry (comms.refused_<reason>).
const REFUSALS: Array[String] = [
	"no_target",
	"not_detected",
	"no_answer",
	"already_talking",
	"no_conversation",
	"not_open",
	"no_option",
	"requirement",
	"no_card",
	"not_offer",
	"closed",
	"not_docked",
	"no_market",
	"bad_item",
	"wrong_slot",
	"no_credits",
	"over_stock",
	"not_held",
	"no_room",
	"no_price",
	"nothing_to_repair",
	"requires_docked",
]

var board: CommsBoard
var overlay: CommsOverlay
var list: CardList

## The phone arrangement (CommsPhone): the rail, the spacers and the conversation's place.
var phone: CommsPhone = null
## The phone-landscape rail (CommsPhone.layout); null until first used.
var touch_layout: RailLayout:
	get:
		return phone.layout if phone != null else null
## A phone's Rep page (docked site, credits, hull, reputation) and Crew page.
var rep_view: VBoxContainer
var crew_page: CrewPage

var _rows: VBoxContainer
var _bar: HFlowContainer
var _buttons: Dictionary = {}
var _status: Label
var _block_ref: Dictionary = {}
var _stick_armed: bool = true
var _list_h: float = 0.0
var _rep_shown: Array = []


func _setup() -> void:
	clip_contents = true
	phone = CommsPhone.new(self)
	in_frame = true
	shows_shares = true
	var rows: VBoxContainer = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 4)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	_rows = rows
	rows.add_child(phone.top_gap)
	board = CommsBoard.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.card_activated.connect(open_card)
	board.card_selected.connect(_on_card_selected)
	rows.add_child(board)
	rep_view = VBoxContainer.new()
	rep_view.name = "RepPage"
	rep_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rep_view.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	rep_view.visible = false
	rows.add_child(rep_view)
	crew_page = CrewPage.new(self)
	crew_page.name = "CrewPage"
	crew_page.visible = false
	rows.add_child(crew_page)
	list = CardList.new()
	list.visible = false
	rows.add_child(list)
	_bar = HFlowContainer.new()
	_bar.add_theme_constant_override("h_separation", 6)
	_bar.add_theme_constant_override("v_separation", 4)
	rows.add_child(_bar)
	for spec: Array in [
		["hail", "comms.hail", _hail],
		["accept", "comms.accept", func() -> void: _answer_card(true)],
		["decline", "comms.decline", func() -> void: _answer_card(false)],
		["claim", "comms.claim", _claim],
		["hold_fire", "comms.hold_fire", send_request],
	]:
		var b: Button = Button.new()
		b.name = "Comms_" + str(spec[0])
		b.text = tr(spec[1])
		b.pressed.connect(spec[2])
		b.focus_mode = Control.FOCUS_NONE
		_bar.add_child(b)
		_buttons[spec[0]] = b
	resized.connect(_fit_bar)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Palette.color("text_dim"))
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(120, 0)
	_bar.add_child(_status)
	rows.add_child(phone.foot_gap)
	overlay = CommsOverlay.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.row_activated.connect(_activate_row)
	overlay.trade_pressed.connect(_buy_sell)
	add_child(overlay)
	pages = PageHost.new()
	for t: String in page_titles():
		pages.add_page(t, [])
	pages.page_changed.connect(_on_page)
	ctx.crew.sim_event.connect(_on_sim_event)
	refresh(true)


## The phone's tab titles, in Page order.
static func page_titles() -> Array[String]:
	return [
		TouchText.of("comms.page.missions", "Missions"),
		TouchText.of("comms.page.contracts", "Contracts"),
		TouchText.of("comms.page.hails", "Hails"),
		TouchText.of("comms.page.rep", "Rep"),
		TouchText.of("page.crew", "Crew"),
	]


## Lays the buttons out for the form: the rail on a phone on its side (CommsPhone), the
## page's part, then the bar's sizes.
func _fit_bar() -> void:
	phone.arrange_rails()
	_show_page()
	phone.fit_bar()


## Shows the current page's part: the board (on its column), the Rep page or the Crew page;
## off a phone the board as on a desktop.
func _show_page() -> void:
	var on_phone: bool = phone.paged()
	var i: int = pages.current if on_phone else Page.MISSIONS
	if not on_phone:
		board.page_column = -1
	elif i <= Page.HAILS:
		board.page_column = i
	board.visible = not docked and i <= Page.HAILS
	rep_view.visible = on_phone and i == Page.REP
	crew_page.visible = on_phone and i == Page.CREW
	# The spacers show only on a phone (a hidden one adds no separation).
	phone.top_gap.visible = on_phone
	phone.foot_gap.visible = on_phone
	if not on_phone:
		_bar.visible = not docked


## A tab: the board shows that column (its first card selected), or the Rep or Crew page;
## an open conversation closes.
func _on_page(i: int) -> void:
	close_overlay()
	if i <= Page.HAILS:
		board.show_column(i)
	_show_page()


## Keys, a swipe or a tap moved the selection: a phone's page follows its column.
func _on_card_selected(id: int) -> void:
	var col: int = board.column_of(id)
	if phone.paged() and pages.current <= Page.HAILS and col >= 0 and col != pages.current:
		pages.current = col


## Docked, the panel is as tall as its card list, so no row is cut off.
func _get_minimum_size() -> Vector2:
	return Vector2(0.0, _list_h if docked else 0.0)


func _mode_changed() -> void:
	_list_h = 0.0
	update_minimum_size()
	board.visible = not docked
	_bar.visible = not docked
	list.visible = docked
	if is_inside_tree():
		_fit_bar()
	if docked and overlay != null:
		overlay.close()
	if pages != null:
		_show_page()


func _process(delta: float) -> void:
	if focused:
		_poll_stick(delta)
	# Hidden (a station not shown on this phone): nothing to refresh until it shows (R20-5).
	if not is_visible_in_tree():
		return
	refresh()
	ControlsHint.show_radar_legend(self, ctx.settings)
	phone.place()


## Pushes the COMMS block into the widgets: every frame when it changed (tests call it).
func refresh(force: bool = false) -> void:
	var blk: Dictionary = CommsData.block(ctx.snap)
	var names: Dictionary = CommsData.claimers(ctx.crew, blk.get("cards", []))
	var changed: bool = force or not is_same(blk, _block_ref) or names != board.claim_names
	_block_ref = blk
	if changed:
		board.claim_names = names
		board.own_name = ctx.settings.player_name
		board.site_name = ctx.site_name(int(blk.get("site", -1)))
		board.set_data(blk)
		if overlay.card_id >= 0:
			if CommsData.card(blk, overlay.card_id).is_empty():
				overlay.close()
			else:
				_show_overlay(overlay.card_id)
	list.set_heading(tr("station.comms"))
	list.setup(CardList.rows(ctx.snap))
	if docked and not is_equal_approx(_list_h, list.custom_minimum_size.y):
		_list_h = list.custom_minimum_size.y
		update_minimum_size()
	_refresh_buttons()
	pages.set_badge(Page.HAILS, hail_waits(blk))
	_refresh_rep(blk)


## True while a hail waits for an answer (the dot on a phone's Hails tab).
static func hail_waits(blk: Dictionary) -> bool:
	for c: Dictionary in blk.get("cards", []):
		if int(c["kind"]) == CardList.HAIL and int(c["state"]) == CardList.STATE_OPEN:
			return true
	return false


## A phone's Rep page: where the ship is docked, hull and credits, then a line per faction
## (FT-COM-005).
func _refresh_rep(blk: Dictionary) -> void:
	var lines: Array = [
		board.where_text(), board.status_text(), tr("comms.rep"), tr(CommsData.WHY_REP_KEY)
	]
	for r: Dictionary in blk.get("rep", []):
		lines.append(CommsData.rep_line(r))
	if lines == _rep_shown:
		return
	_rep_shown = lines
	for c: Node in rep_view.get_children():
		rep_view.remove_child(c)
		c.queue_free()
	for i: int in lines.size():
		var l: Label = Label.new()
		l.text = str(lines[i])
		var pad: StyleBoxEmpty = StyleBoxEmpty.new()
		pad.content_margin_left = UiTheme.TOUCH_GAP
		l.add_theme_stylebox_override("normal", pad)
		l.add_theme_font_size_override("font_size", CommsBoard.FONT_SIZE - (3 if i == 3 else 0))
		var dim: bool = i == 2 or i == 3
		l.add_theme_color_override("font_color", Palette.color("text_dim" if dim else "text"))
		rep_view.add_child(l)


func _show_overlay(id: int) -> void:
	overlay.holder = ctx.crew.claimer("%s:%d" % [StationCatalogue.CLAIM_NPC, id])
	overlay.own_name = ctx.settings.player_name
	overlay.ship_name = ctx.crew.ship_name()
	overlay.show_card(block(), id)


func _refresh_buttons() -> void:
	var card: Dictionary = current_card()
	var live: bool = not card.is_empty() and CardList.is_live(card)
	var open_state: bool = not card.is_empty() and int(card["state"]) == CardList.STATE_OPEN
	(_buttons["hail"] as Button).disabled = hail_contact() < 0
	# An information card has nothing to accept (Q23): its Accept button is hidden.
	var info: bool = not card.is_empty() and int(card["kind"]) == CardList.INFO
	(_buttons["accept"] as Button).visible = not info
	(_buttons["accept"] as Button).disabled = not open_state
	(_buttons["decline"] as Button).disabled = not open_state
	var item: String = claim_item()
	var holder: String = ctx.crew.claimer(item) if item != "" else ""
	var mine: bool = holder == ctx.settings.player_name
	(_buttons["claim"] as Button).disabled = not live or item == ""
	(_buttons["claim"] as Button).text = (
		tr("comms.release")
		if mine
		else (tr("comms.claimed_by") % holder if holder != "" else tr("comms.claim"))
	)
	(_buttons["hold_fire"] as Button).disabled = request_chips().is_empty()


## Controls help on touch (P28-Help): per page, the boxes of its controls in the 844x390
## landscape frame (the rail's on the first page only) with a label and what each does.
static func touch_help() -> Array:
	var t: Array[String] = page_titles()
	var rail: Array = []
	var rows: Array = [
		["hail", "comms.hail", "Hail the selected contact"],
		["accept", "comms.accept", "Accept the card, or answer a hail"],
		["decline", "comms.decline", "Decline the card"],
		["claim", "comms.claim", "Take or release the card's conversation"],
		["hold_fire", "comms.hold_fire", "Ask Weapons to hold fire on the contact"],
	]
	for i: int in rows.size():
		var r: Array = rows[i]
		(
			rail
			. append(
				[
					Rect2(47, 72 + 56 * i, 136, 48),
					TranslationServer.translate(r[1]),
					TouchText.of("help.comms." + r[0], r[2]),
				]
			)
		)
	var card: Rect2 = Rect2(195.0, 132.0 + CommsBoard.PAGE_WHY_H, 414, 72)
	var open: String = TouchText.of("help.comms.card", "Tap to open; long-press pings its contact")
	rail.append([card, TouchText.of("help.comms.mission", "Mission card"), open])
	return [
		{"page": t[Page.MISSIONS], "boxes": rail},
		{
			"page": t[Page.CONTRACTS],
			"boxes": [[card, TouchText.of("help.comms.contract", "Contract card"), open]],
		},
		{
			"page": t[Page.HAILS],
			"boxes":
			[
				[
					card,
					TouchText.of("help.comms.offer", "Offer or hail"),
					TouchText.of("help.comms.talk", "Tap to talk, buy or sell"),
				]
			],
		},
		{
			"page": t[Page.REP],
			"boxes":
			[
				[
					Rect2(191, 132, 422, 180),
					TranslationServer.translate("comms.rep"),
					TouchText.of("help.comms.rep", "Docked site, credits and standing per faction"),
				]
			],
		},
		{
			"page": t[Page.CREW],
			"boxes":
			[
				[
					Rect2(191, 132, 207, 48),
					TranslationServer.translate("comms.hold_fire"),
					TouchText.of("help.comms.hold_fire", "Ask Weapons to hold fire on the contact"),
				],
				[
					Rect2(406, 132, 207, 48),
					TranslationServer.translate("intent.ping"),
					TouchText.of("help.comms.ping", "Ping the selection for the crew"),
				],
				[
					Rect2(191, 188, 207, 48),
					TranslationServer.translate("intent.mark"),
					TouchText.of("help.comms.mark", "Mark the selection"),
				],
			],
		},
	]


# --- Reading. ---


## The card the keys act on: the open one, else the board's selection; {} for none.
func current_card() -> Dictionary:
	return overlay.card() if overlay.card_id >= 0 else board.selected_row()


func block() -> Dictionary:
	return CommsData.block(ctx.snap)


## The contact H hails and hold fire names: the shared selection if it is a contact, else
## the subject of the card the keys act on, else -1.
func hail_contact() -> int:
	var s: Dictionary = ctx.crew.selection
	if s.get("kind", "") == "contact":
		return int(s["id"])
	var t: int = int(current_card().get("subject", -1))
	return t if t in ctx.interp.contact_ids() else -1


func chip_arg(_chip: ChipDef) -> int:
	return hail_contact()


## "Hold fire on H2": the chip names the contact it is about.
func chip_label(chip: ChipDef) -> String:
	var t: int = hail_contact()
	var who: String = ctx.snap.callsign(t) if t >= 0 else ""
	return ChipsReader.label({"chip": String(chip.id), "arg": t}, who)


## Hold fire needs a contact to name.
func send_chip(chip: ChipDef) -> void:
	if hail_contact() < 0:
		ctx.crew.toast.emit("toast.select_first", {})
		return
	super(chip)


func claim_item() -> String:
	var card: Dictionary = current_card()
	if card.is_empty() or not bool(card.get("conv", false)):
		return ""
	return "%s:%d" % [StationCatalogue.CLAIM_NPC, int(card["id"])]


# --- Doing. ---


## Opens a card's conversation over the board; a conversation not yet open is answered
## first (the server takes the claim of a free one, FT-COM-006).
func open_card(id: int) -> void:
	var card: Dictionary = CommsData.card(block(), id)
	if card.is_empty():
		return
	board.select(id)
	_status.text = ""
	_show_overlay(id)
	if bool(card["conv"]) and not bool(card["open"]) and CardList.is_live(card):
		ctx.intents.command({"kind": "comms_answer", "card": id})


## Esc and a controller's B: the overlay goes, the board shows.
func close_overlay() -> bool:
	if overlay.card_id < 0:
		return false
	overlay.close()
	return true


func _hail() -> void:
	var t: int = hail_contact()
	if t < 0:
		ctx.crew.toast.emit("toast.select_first", {})
		return
	ctx.intents.command({"kind": "comms_hail", "contact": t})


## Accepts or declines the card the keys act on; an unanswered hail is answered instead of
## accepted (FT-COM-002). False with no card, so the common key falls through to a chip.
func _answer_card(accept: bool) -> bool:
	var card: Dictionary = current_card()
	if card.is_empty():
		return false
	var id: int = int(card["id"])
	if accept and int(card["kind"]) == CardList.INFO:
		return true  # nothing to accept (Q23); the key is taken, not passed on to a chip
	if accept and int(card["kind"]) == CardList.HAIL:
		open_card(id)
	else:
		ctx.intents.command({"kind": "comms_accept" if accept else "comms_decline", "card": id})
	return true


func _claim() -> void:
	var item: String = claim_item()
	if item == "":
		return
	if int(ctx.crew.claims.get(item, {}).get("session", -1)) == ctx.crew.session:
		ctx.intents.release_claim(item)
	else:
		ctx.intents.claim(item)


## Does what a row of the overlay says: a reply, one buy step of an item, a module, a sale.
func _activate_row(row: Dictionary) -> void:
	var card: int = overlay.card_id
	match row["kind"]:
		"reply":
			if not bool(row["enabled"]):
				_note(tr("comms.refused_requirement"))
			else:
				ctx.intents.command({"kind": "comms_reply", "card": card, "option": row["id"]})
		"buy":
			_trade(row, true)
		"module":
			(
				ctx
				. intents
				. command(
					{
						"kind": "comms_buy_module",
						"card": card,
						"module_key": row["module"],
						"slot": row["slot"],
					}
				)
			)
		"sell_module":
			ctx.intents.command({"kind": "comms_sell_module", "card": card, "slot": row["slot"]})


func _trade(row: Dictionary, buy: bool) -> void:
	var item: String = str(row["item"])
	if not buy and int(row["sell"]) <= 0:
		return
	(
		ctx
		. intents
		. command(
			{
				"kind": "comms_trade",
				"card": overlay.card_id,
				"item": item,
				"qty": CommsData.step_of(item) if not item.begins_with("repair:") else 1,
				"buy": buy,
			}
		)
	)


func _note(text: String) -> void:
	overlay.status = text
	_status.text = text
	overlay.queue_redraw()


func _focused_row() -> Dictionary:
	var rows: Array[Dictionary] = overlay.rows()
	return rows[overlay.focus] if overlay.focus < rows.size() else {}


# --- Events. ---


func _on_sim_event(kind: StringName, p: Dictionary) -> void:
	var tag: String = str(p.get("tag", ""))
	match kind:
		&"card_posted":
			ctx.crew.toast.emit("toast.comms_card", {})
		&"card_refused", &"hail_refused", &"reply_refused", &"trade_refused":
			_note(tr("comms.refused_" + tag) if tag in REFUSALS else tr("comms.refused"))
		&"trade_done":
			_note(tr("comms.trade_done") % [CommsData.item_text(tag), absi(roundi(p["value"]))])
		&"module_fitted":
			_note(tr("comms.module_fitted") % CommsData.module_text(tag))
		&"module_sold":
			_note(tr("comms.module_sold") % [CommsData.module_text(tag), roundi(p["value"])])


# --- Input. ---


func handle_intent(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)):
		return false
	var id: String = str(ev["id"])
	var handled: bool = true
	if id.begins_with("comms_reply_"):
		handled = _reply_key(id.trim_prefix("comms_reply_").to_int())
	else:
		match id:
			"comms_close":
				handled = close_overlay()
			"accept":
				handled = _answer_card(true)
			"decline":
				handled = _answer_card(false)
			"comms_open":
				handled = _open_selected()
			"comms_hail":
				_hail()
			"comms_next_column":
				board.move(1, 0)
			"comms_up":
				_move(0, -1)
			"comms_down":
				_move(0, 1)
			"comms_left":
				_move(-1, 0)
			"comms_right":
				_move(1, 0)
			"comms_buy":
				handled = _buy_sell(true)
			"comms_sell":
				handled = _buy_sell(false)
			_:
				handled = false
	return handled


## A on a controller, the common select, which the screen offers the panel first: it opens
## the focused card, or does the focused line of the overlay.
func take_select() -> bool:
	if overlay.card_id >= 0:
		var row: Dictionary = _focused_row()
		if not row.is_empty():
			_activate_row(row)
		return true
	return _open_selected()


func _open_selected() -> bool:
	if overlay.card_id >= 0 or board.selected < 0:
		return false
	open_card(board.selected)
	return true


func _move(dx: int, dy: int) -> void:
	if overlay.card_id >= 0:
		overlay.move_focus(dy)
	else:
		board.move(dx, dy)


func _reply_key(n: int) -> bool:
	if overlay.card_id < 0:
		return false
	var i: int = overlay.reply_index(n)
	if i < 0:
		return true
	overlay.focus = i
	_activate_row(overlay.rows()[i])
	return true


## E / X in the overlay: one step of the focused line bought or sold.
func _buy_sell(buy: bool) -> bool:
	if overlay.card_id < 0:
		return false
	var row: Dictionary = _focused_row()
	match str(row.get("kind", "")):
		"buy":
			_trade(row, buy)
		"module":
			if buy:
				_activate_row(row)
		"sell_module":
			if not buy:
				_activate_row(row)
	return true


## The left stick moves between cards and columns: one move per deflection.
func _poll_stick(_delta: float) -> void:
	var m: InputMatcher = ctx.matcher
	if m.device != IntentTable.PAD:
		return
	var x: float = m.axis("comms_stick_x")
	var y: float = m.axis("comms_stick_y")
	var mag: float = maxf(absf(x), absf(y))
	if mag < STICK_RELEASE:
		_stick_armed = true
	elif _stick_armed and mag > STICK_MOVE:
		_stick_armed = false
		if absf(x) > absf(y):
			_move(1 if x > 0.0 else -1, 0)
		else:
			_move(0, 1 if y > 0.0 else -1)


## The contact a card is about, for ping and mark (§5.6): the card under the pointer, else
## the open or selected one. Cards about no detected contact give nothing.
func item_at(screen_pos: Vector2) -> Dictionary:
	var card: Dictionary = {}
	if overlay.card_id >= 0:
		card = overlay.card()
	elif docked:
		card = CommsData.card(
			block(), list.card_at(screen_pos - (list.global_position - global_position))
		)
	else:
		card = CommsData.card(
			block(), board.card_at(screen_pos - (board.global_position - global_position))
		)
	var t: int = int(card.get("subject", -1))
	if t < 0 or t not in ctx.interp.contact_ids():
		return {}
	return {"kind": "contact", "id": t}


## A controller has no pointer: the cursor is the middle of the card the keys act on.
func cursor_pos() -> Vector2:
	if overlay.card_id >= 0:
		return overlay.box_rect().get_center()
	var r: Rect2 = board.card_rect(board.selected)
	if r.size == Vector2.ZERO:
		return size / 2.0
	return r.get_center() + board.global_position - global_position
