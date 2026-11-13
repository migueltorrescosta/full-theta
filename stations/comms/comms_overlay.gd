class_name CommsOverlay
extends Control
## A card's conversation over the board (§5.6, D87, FT-COM-008): the NPC's line, up to four
## numbered replies (FT-COM-007; a science icon marks an option Science's scan unlocked,
## P14), and for an offer card what the docked market sells and buys (FT-COM-004), the
## modules it offers with the module a full slot gives up in the same trade and what that
## pays (FT-MIS-036, FT-COM-009), and the fitted modules to sell. Every line that does
## something is a row: a click or tap, or the focus plus a key, activates it. A click
## outside the box or a swipe down closes the overlay. On a phone (#28 follow-up, design 2.6)
## rows are 48 px in two columns, a list too long for the box pages with ‹ › buttons, and a
## Close button closes; with `fill` set the box fills the overlay (a phone on its side, where
## the overlay covers the board and the radar column).

signal row_activated(row: CommsRows.Row)
## The visible Buy or Sell button was pressed: one step on the focused row (R23-9).
signal trade_pressed(buy: bool)
signal closed

const FONT_SIZE: int = 15
const ROW_H: float = 40.0
const PAD: float = 14.0
const MAX_WIDTH: float = 760.0
## A swipe down of this many pixels closes the overlay (touch).
const SWIPE_PX: float = 60.0
## Replies are numbered 1 to MAX_REPLIES.
const MAX_REPLIES: int = 4
## A phone's rows (#28): touch-sized with 8 px gaps, in two columns when the box is this wide
## (a phone on its side), and no keyboard hint under them.
const PHONE_ROW_H: float = 48.0
const PHONE_TWO_COLS_WIDTH: float = 520.0
## The Close button's width on a phone.
const CLOSE_WIDTH: float = 112.0
## The Buy and Sell buttons, drawn while the card trades (R23-9): size, and the room a
## desktop box keeps for them above its hint line.
const TRADE_WIDTH: float = 96.0
const TRADE_H: float = 40.0
const TRADE_FOOT: float = 48.0
## The page counter's width ("1/2") beside the ‹ › buttons.
const COUNTER_WIDTH: float = 44.0

## The COMMS block, the open card, and the focused row (index into `rows()`).
var data: Dictionary = {}
var card_id: int = -1
var focus: int = 0:
	set(value):
		focus = value
		_sync_trade_buttons()
## The last result (a refusal or a trade), shown under the rows.
var status: String = ""
## Who holds the card's conversation ("" for free) and the session's own name.
var holder: String = ""
var own_name: String = ""
var ship_name: String = ""

## Rows that don't fit show a page at a time (a phone's trade offer, #28): the first line
## of rows shown.
var first_line: int = 0
## The box fills the overlay (a phone on its side) instead of a centred box.
var fill: bool = false
## A phone's buttons: the previous and next page of rows, and Close.
var prev_button: RailButton
var next_button: RailButton
var close_button: RailButton
## The visible Buy and Sell buttons of a card that trades (hidden otherwise).
var buy_button: RailButton
var sell_button: RailButton

var _rows: Array[CommsRows.Row] = []
var _rects: Array[Rect2] = []
var _box: Rect2 = Rect2()
var _press: Vector2 = Vector2(-1.0, -1.0)
## The line each row is on, and the lines a page shows (see first_line).
var _line_of: Array[int] = []
var _lines_shown: int = 0
var _line_count: int = 0
## One tap target per row shown on a phone, for TapAudit (the rows are drawn).
var _hits: Array[Control] = []
## Buy and Sell sit on their own row (a narrow phone).
var _stacked: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	clip_contents = true
	prev_button = _foot_button("Prev", "‹", func() -> void: page(false))
	next_button = _foot_button("Next", "›", func() -> void: page(true))
	close_button = _foot_button("Close", tr("comms.close"), close)
	buy_button = _foot_button(
		"Buy", TranslationServer.translate("comms.buy"), func() -> void: trade_pressed.emit(true)
	)
	sell_button = _foot_button(
		"Sell", TranslationServer.translate("comms.sell"), func() -> void: trade_pressed.emit(false)
	)


func _foot_button(id: String, text: String, does: Callable) -> RailButton:
	var b: RailButton = RailButton.make(text)
	b.name = id
	b.visible = false
	b.pressed.connect(does)
	add_child(b)
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


## Opens card `id` over the block, or updates the open card with a new block.
func show_card(blk: Dictionary, id: int) -> void:
	var fresh: bool = id != card_id
	data = blk
	card_id = id
	if fresh:
		focus = 0
		first_line = 0
		status = ""
	_rows = _make_rows()
	focus = clampi(focus, 0, maxi(0, _rows.size() - 1))
	if fresh:
		# A card that trades opens on its first trade row, so Enter does not pick "Go back".
		for i: int in _rows.size():
			if _rows[i].kind != "reply":
				focus = i
				break
	visible = true
	_layout()


func close() -> void:
	visible = false
	card_id = -1
	closed.emit()


func card() -> Dictionary:
	return CommsData.card(data, card_id)


## The actionable rows: replies, goods to buy, modules to buy and fitted modules to sell.
func rows() -> Array[CommsRows.Row]:
	return _rows


## The index of the row at `pos` (local), or -1.
func row_at(pos: Vector2) -> int:
	for i: int in _rects.size():
		if _rects[i].has_point(pos):
			return i
	return -1


## The box's rectangle (local), for tests and the pad's cursor.
func box_rect() -> Rect2:
	return _box


## The row of reply `n` (1 to 4), or -1.
func reply_index(n: int) -> int:
	for i: int in _rows.size():
		if _rows[i] is CommsRows.Reply and _rows[i].n == n:
			return i
	return -1


## Moves the focus by `step` rows.
func move_focus(step: int) -> void:
	if _rows.is_empty():
		return
	focus = clampi(focus + step, 0, _rows.size() - 1)
	if focus < _line_of.size():
		var line: int = _line_of[focus]
		if line < first_line:
			first_line = line
		elif line >= first_line + _lines_shown:
			first_line = line - _lines_shown + 1
		_layout()
	queue_redraw()


## True when a row of the card trades (the Buy and Sell buttons show).
func trades() -> bool:
	for row: CommsRows.Row in _rows:
		if row.can_buy() or row.can_sell():
			return true
	return false


## "1/2" while the rows page, else "".
func page_text() -> String:
	if _lines_shown <= 0 or _lines_shown >= _line_count:
		return ""
	var pages: int = ceili(float(_line_count) / _lines_shown)
	return "%d/%d" % [mini(first_line / _lines_shown + 1, pages), pages]


func _sync_trade_buttons() -> void:
	if buy_button == null:
		return
	var row: CommsRows.Row = _rows[focus] if focus >= 0 and focus < _rows.size() else null
	buy_button.disabled = row == null or not row.can_buy()
	sell_button.disabled = row == null or not row.can_sell()


## True when rows below the page shown don't fit.
func more_below() -> bool:
	return first_line + _lines_shown < _line_count


## Shows the next page of rows (a swipe up), or the previous one; false when there is none.
func page(down: bool) -> bool:
	var to: int = first_line + (maxi(_lines_shown, 1) if down else -maxi(_lines_shown, 1))
	to = clampi(to, 0, maxi(_line_count - 1, 0))
	if to == first_line:
		return false
	first_line = to
	_layout()
	return true


func _make_rows() -> Array[CommsRows.Row]:
	var out: Array[CommsRows.Row] = []
	var node: Dictionary = CommsData.node_of(data, card_id)
	var n: int = 0
	for o: Dictionary in node.get("options", []):
		n += 1
		if n > MAX_REPLIES:
			break
		out.append(CommsRows.Reply.new(o, n))
	for o: Dictionary in CommsData.offers_of(data, card_id):
		out.append(CommsRows.Buy.new(o))
	var sell_pay: Dictionary = {}
	for m: Dictionary in CommsData.modules_of(data, card_id):
		out.append(CommsRows.Module.new(m))
		if str(m["old"]) != "":
			sell_pay[int(m["slot"])] = int(m["trade_in"])
	if not CommsData.offers_of(data, card_id).is_empty() or sell_pay.size() > 0:
		for f: Dictionary in data.get("fitted", []):
			if str(f["module"]) != "":
				out.append(CommsRows.SellModule.new(f, sell_pay.get(int(f["slot"]), 0)))
	return out


# --- Layout. ---


## Body text above the rows: the NPC's line, or the card's detail text.
func _body() -> String:
	var c: Dictionary = card()
	var node: Dictionary = CommsData.node_of(data, card_id)
	if not node.is_empty():
		var numbers: Dictionary = CommsData.trade_args(data, card_id)
		return CommsData.line_text(str(node["line"]), str(c.get("npc", "")), ship_name, numbers)
	var text: String = TranslationServer.translate(str(c.get("detail", "")))
	if bool(c.get("conv", false)) and CardList.is_live(c):
		# A phone opened it with the tap that shows it: no key to name (#28).
		var phone: bool = is_inside_tree() and LayoutMode.is_phone(LayoutMode.form_of(self))
		text += (
			"\n"
			+ (tr("comms.opening") if phone else TranslationServer.translate("comms.open_hint"))
		)
	return text


func _layout() -> void:
	_rects.clear()
	if not visible and card_id < 0:
		return
	var font: Font = get_theme_default_font()
	var phone: bool = is_inside_tree() and LayoutMode.is_phone(LayoutMode.form_of(self))
	var w: float = size.x if fill else minf(size.x - 24.0, MAX_WIDTH)
	var cols: int = 2 if phone and w >= PHONE_TWO_COLS_WIDTH else 1
	var gap: float = float(UiTheme.TOUCH_GAP) if phone else 4.0
	var row_min: float = PHONE_ROW_H if phone else ROW_H
	var row_width: float = (w - 2.0 * PAD - (cols - 1) * gap) / cols
	var body: Vector2 = font.get_multiline_string_size(
		_body(), HORIZONTAL_ALIGNMENT_LEFT, w - 2.0 * PAD, FONT_SIZE
	)
	# A row that doesn't fit on a line wraps and grows (a phone's trade offer).
	var heights: Array[float] = []
	var rows_h: float = 0.0
	for row: CommsRows.Row in _rows:
		var text_h: float = (
			font
			. get_multiline_string_size(
				row.text(), HORIZONTAL_ALIGNMENT_LEFT, row_width - 16.0, FONT_SIZE
			)
			. y
		)
		heights.append(maxf(row_min, text_h + 16.0))
	# Rows go left to right, then down; a line of rows is as tall as its tallest.
	var lines: Array[float] = []
	for i: int in heights.size():
		if i % cols == 0:
			lines.append(0.0)
		lines[-1] = maxf(lines[-1], heights[i])
	for lh: float in lines:
		rows_h += lh + gap
	var trade: bool = trades()
	# A phone too narrow for one foot row puts Buy and Sell on a row of their own.
	_stacked = phone and trade and w < PHONE_TWO_COLS_WIDTH
	var foot: float = 70.0 + (TRADE_FOOT if trade else 0.0)
	if phone:
		foot = PAD + UiTheme.TOUCH_PRIMARY + gap
		if _stacked:
			foot += UiTheme.TOUCH_PRIMARY + gap
	var h: float = PAD + 24.0 + body.y + 12.0 + rows_h + foot
	h = minf(h, size.y - (8.0 if phone else 16.0))
	if fill:
		h = size.y
	_box = Rect2((size.x - w) / 2.0, (size.y - h) / 2.0, w, h)
	var y: float = _box.position.y + PAD + 24.0 + body.y + 12.0
	# The lines that fit above the foot; the rest wait for a swipe (page).
	var room: float = _box.end.y - foot - y
	_line_count = lines.size()
	first_line = clampi(first_line, 0, maxi(_line_count - 1, 0))
	_lines_shown = 0
	var used: float = 0.0
	for k: int in range(first_line, lines.size()):
		if used + lines[k] > room and _lines_shown > 0:
			break
		used += lines[k] + gap
		_lines_shown += 1
	_line_of.clear()
	for i: int in _rows.size():
		var line: int = floori(i / float(cols))
		_line_of.append(line)
		if line < first_line or line >= first_line + _lines_shown:
			_rects.append(Rect2())
			continue
		var x: float = _box.position.x + PAD + (i % cols) * (row_width + gap)
		_rects.append(Rect2(x, y, row_width, lines[line]))
		if i % cols == cols - 1 or i == _rows.size() - 1:
			y += lines[line] + gap
	_place_buttons(phone)
	queue_redraw()


## Buy and Sell: on a phone after the ‹ › buttons (page counter in between), or on a row of
## their own above the foot row when narrow; on a desktop in the room above the hint line.
func _place_trade_buttons(phone: bool, foot_y: float, side: float) -> void:
	var show: bool = trades()
	buy_button.visible = show
	sell_button.visible = show
	if not show:
		return
	var at: Vector2 = Vector2(_foot_text_x(), foot_y)
	var h: float = side
	if _stacked:
		at = Vector2(_box.position.x + PAD, foot_y - side - UiTheme.TOUCH_GAP)
	elif not phone:
		h = TRADE_H
		at = Vector2(_box.position.x + PAD, _box.end.y - 70.0 - TRADE_H - 4.0)
	buy_button.position = at
	sell_button.position = at + Vector2(TRADE_WIDTH + UiTheme.TOUCH_GAP, 0.0)
	for b: RailButton in [buy_button, sell_button]:
		b.size = Vector2(TRADE_WIDTH, h)
		b.custom_minimum_size = Vector2(TRADE_WIDTH, h)


## Where a phone's foot row continues after the ‹ › buttons and the page counter.
func _foot_text_x() -> float:
	var x: float = _box.position.x + PAD
	if _paged():
		x += 2.0 * (UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP) + COUNTER_WIDTH
	return x


func _paged() -> bool:
	return _lines_shown < _line_count


## A phone's foot row (‹ while a page is above, › while one is below, Close at the right)
## and the rows' targets. Each arrow keeps its slot while hidden, so the row doesn't jump.
func _place_buttons(phone: bool) -> void:
	var side: float = UiTheme.TOUCH_PRIMARY
	var y: float = _box.end.y - PAD - side
	var paged: bool = phone and _lines_shown < _line_count
	prev_button.visible = paged and first_line > 0
	next_button.visible = paged and more_below()
	close_button.visible = phone
	var x: float = _box.position.x + PAD
	for b: RailButton in [prev_button, next_button]:
		b.position = Vector2(x, y)
		b.size = Vector2(side, side)
		x += side + UiTheme.TOUCH_GAP
	_place_trade_buttons(phone, y, side)
	close_button.position = Vector2(_box.end.x - PAD - CLOSE_WIDTH, y)
	close_button.size = Vector2(CLOSE_WIDTH, side)
	while _hits.size() < _rects.size():
		var hit: Control = Control.new()
		hit.name = "Row%d" % _hits.size()
		hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit.set_meta("tap", true)
		add_child(hit)
		_hits.append(hit)
	for i: int in _hits.size():
		var r: Rect2 = _rects[i] if i < _rects.size() else Rect2()
		_hits[i].visible = phone and r.size != Vector2.ZERO
		_hits[i].position = r.position
		_hits[i].size = r.size


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press = event.position
		return
	var moved: Vector2 = event.position - _press
	_press = Vector2(-1.0, -1.0)
	var vertical: bool = absf(moved.y) > absf(moved.x)
	# A swipe up shows the rows below; down the rows above, and on the first page closes.
	if moved.y <= -SWIPE_PX and vertical:
		page(true)
		return
	if moved.y >= SWIPE_PX and vertical:
		if not page(false):
			close()
		return
	if moved.length() > 12.0:
		return
	var i: int = row_at(event.position)
	if i >= 0:
		focus = i
		row_activated.emit(_rows[i])
	elif not _box.has_point(event.position):
		close()


# --- Drawing. ---


func _draw() -> void:
	if card_id < 0:
		return
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_rect(_box, Palette.color("panel"))
	draw_rect(_box, Palette.color("accent"), false, 2.0)
	var c: Dictionary = card()
	var x: float = _box.position.x + PAD
	var y: float = _box.position.y + PAD + font.get_ascent(FONT_SIZE)
	var claim: String = (
		TranslationServer.translate("comms.you")
		if holder == own_name and holder != ""
		else (holder if holder != "" else TranslationServer.translate("comms.free"))
	)
	var head: String = (
		"%s > %s"
		% [
			TranslationServer.translate("station.comms"),
			TranslationServer.translate(str(c.get("title", "")))
		]
	)
	if bool(c.get("conv", false)):
		head += "   " + TranslationServer.translate("comms.claimed_by") % claim
	draw_string(
		font, Vector2(x, y), head, 0, _box.size.x - 2.0 * PAD, FONT_SIZE, Palette.color("accent")
	)
	y += 24.0
	var npc: String = str(c.get("npc", ""))
	var body: String = _body()
	if CommsData.node_of(data, card_id).is_empty() or npc == "":
		draw_multiline_string(
			font,
			Vector2(x, y + font.get_ascent(FONT_SIZE) - 6.0),
			body,
			HORIZONTAL_ALIGNMENT_LEFT,
			_box.size.x - 2.0 * PAD,
			FONT_SIZE,
			-1,
			Palette.color("text")
		)
	else:
		draw_multiline_string(
			font,
			Vector2(x, y + font.get_ascent(FONT_SIZE) - 6.0),
			'%s: "%s"' % [npc, body],
			HORIZONTAL_ALIGNMENT_LEFT,
			_box.size.x - 2.0 * PAD,
			FONT_SIZE,
			-1,
			Palette.color("text")
		)
	for i: int in _rows.size():
		_draw_row(font, i)
	var foot_y: float = _box.end.y - PAD
	var hint: String = TranslationServer.translate("comms.overlay_hint")
	var hint_width: float = _box.size.x - 2.0 * PAD
	# A phone has no keys to hint at (#28): its foot row holds the buttons, and the status
	# between them.
	if close_button.visible:
		hint = ""
		var left: float = x
		foot_y = close_button.position.y + (close_button.size.y + font.get_ascent(FONT_SIZE)) / 2.0
		if _paged():
			left = next_button.position.x + next_button.size.x + UiTheme.TOUCH_GAP
			draw_string(
				font,
				Vector2(left, foot_y),
				page_text(),
				0,
				COUNTER_WIDTH,
				FONT_SIZE,
				Palette.color("text")
			)
			left += COUNTER_WIDTH
		if buy_button.visible and not _stacked:
			left = sell_button.position.x + TRADE_WIDTH + UiTheme.TOUCH_GAP
		hint_width = close_button.position.x - UiTheme.TOUCH_GAP - left
		x = left
	elif page_text() != "":
		hint = "%s   %s" % [page_text(), hint]
	if status != "":
		hint = status
	draw_string(
		font,
		Vector2(x, foot_y),
		hint,
		0,
		hint_width,
		FONT_SIZE - 1,
		Palette.color("warn") if status != "" else Palette.color("text_dim")
	)


func _draw_row(font: Font, i: int) -> void:
	var r: Rect2 = _rects[i]
	if r.size == Vector2.ZERO:
		return
	var row: CommsRows.Row = _rows[i]
	var off: bool = row is CommsRows.Reply and not row.enabled
	draw_rect(r, Palette.color("panel_focus") if i == focus else Palette.color("background"))
	if i == focus:
		draw_rect(r, Palette.color("accent"), false, 2.0)
	var text: String = row.text()
	var text_h: float = (
		font
		. get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0, FONT_SIZE)
		. y
	)
	draw_multiline_string(
		font,
		Vector2(
			r.position.x + 8.0,
			r.position.y + (r.size.y - text_h) / 2.0 + font.get_ascent(FONT_SIZE)
		),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - 16.0,
		FONT_SIZE,
		-1,
		Palette.color("text_dim") if off else Palette.color("text")
	)
