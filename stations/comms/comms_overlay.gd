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

signal row_activated(row: Dictionary)
signal closed

const FONT_SIZE: int = 15
const ROW_H: float = 40.0
const PAD: float = 14.0
const MAX_W: float = 760.0
## A swipe down of this many pixels closes the overlay (touch).
const SWIPE_PX: float = 60.0
## Replies are numbered 1 to MAX_REPLIES.
const MAX_REPLIES: int = 4
## A phone's rows (#28): touch-sized with 8 px gaps, in two columns when the box is this wide
## (a phone on its side), and no keyboard hint under them.
const PHONE_ROW_H: float = 48.0
const PHONE_TWO_COLS_W: float = 520.0
## The Close button's width on a phone.
const CLOSE_W: float = 112.0

## The COMMS block, the open card, and the focused row (index into `rows()`).
var data: Dictionary = {}
var card_id: int = -1
var focus: int = 0
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

var _rows: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _box: Rect2 = Rect2()
var _press: Vector2 = Vector2(-1.0, -1.0)
## The line each row is on, and the lines a page shows (see first_line).
var _line_of: Array[int] = []
var _lines_shown: int = 0
var _line_count: int = 0
## One tap target per row shown on a phone, for TapAudit (the rows are drawn).
var _hits: Array[Control] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	clip_contents = true
	prev_button = _foot_button("Prev", "‹", func() -> void: page(false))
	next_button = _foot_button("Next", "›", func() -> void: page(true))
	close_button = _foot_button("Close", TouchText.of("comms.close", "Close"), close)


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
	visible = true
	_layout()


func close() -> void:
	visible = false
	card_id = -1
	closed.emit()


func card() -> Dictionary:
	return CommsData.card(data, card_id)


## The actionable rows: {"kind": "reply" (id, n, enabled, verify), "buy" (item, price, sell,
## stock), "module" (module, slot, price, old, trade_in) or "sell_module" (slot, module,
## pay), "text"}.
func rows() -> Array[Dictionary]:
	return _rows


## The row's text.
func row_text(row: Dictionary) -> String:
	match row["kind"]:
		"reply":
			var t: String = "%d  %s" % [row["n"], TranslationServer.translate(str(row["text"]))]
			return t + ("  " + TranslationServer.translate("comms.verify")) if row["verify"] else t
		"buy":
			var item: String = str(row["item"])
			var t: String = (
				TranslationServer.translate("comms.buy_line")
				% [CommsData.item_text(item), int(row["price"])]
			)
			if int(row["sell"]) > 0:
				t += "  " + TranslationServer.translate("comms.sell_at") % int(row["sell"])
			if int(row["stock"]) >= 0:
				t += "  " + TranslationServer.translate("comms.stock") % int(row["stock"])
			var step: int = CommsData.step_of(item)
			if step > 1:
				t += "  " + TranslationServer.translate("comms.per_press") % step
			return t
		"module":
			var t: String = (
				TranslationServer.translate("comms.module_line")
				% [
					TranslationServer.translate(str(row["name"])),
					int(row["slot"]) + 1,
					int(row["price"]),
				]
			)
			if str(row["old"]) != "":
				t += (
					"  "
					+ (
						TranslationServer.translate("comms.module_swap")
						% [
							CommsData.module_text(str(row["old"])),
							int(row["trade_in"]),
							int(row["price"]) - int(row["trade_in"]),
						]
					)
				)
			return t
		"sell_module":
			var t: String = (
				TranslationServer.translate("comms.sell_module")
				% [CommsData.module_text(str(row["module"])), int(row["slot"]) + 1]
			)
			if int(row["pay"]) > 0:
				t += "  " + TranslationServer.translate("comms.sells_for") % int(row["pay"])
			return t
	return str(row.get("text", ""))


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
		if _rows[i]["kind"] == "reply" and int(_rows[i]["n"]) == n:
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


func _make_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var node: Dictionary = CommsData.node_of(data, card_id)
	var n: int = 0
	for o: Dictionary in node.get("options", []):
		n += 1
		if n > MAX_REPLIES:
			break
		(
			out
			. append(
				{
					"kind": "reply",
					"id": o["id"],
					"n": n,
					"text": o["text"],
					"enabled": o["enabled"],
					"verify": o["verify"],
				}
			)
		)
	for o: Dictionary in CommsData.offers_of(data, card_id):
		(
			out
			. append(
				{
					"kind": "buy",
					"item": o["item"],
					"price": o["price"],
					"sell": o["sell"],
					"stock": o["stock"],
				}
			)
		)
	var sell_pay: Dictionary = {}
	for m: Dictionary in CommsData.modules_of(data, card_id):
		(
			out
			. append(
				{
					"kind": "module",
					"module": m["module"],
					"name": m["name"],
					"slot": m["slot"],
					"price": m["price"],
					"old": m["old"],
					"trade_in": m["trade_in"],
				}
			)
		)
		if str(m["old"]) != "":
			sell_pay[int(m["slot"])] = int(m["trade_in"])
	if not CommsData.offers_of(data, card_id).is_empty() or sell_pay.size() > 0:
		for f: Dictionary in data.get("fitted", []):
			if str(f["module"]) != "":
				(
					out
					. append(
						{
							"kind": "sell_module",
							"slot": f["slot"],
							"module": f["module"],
							"pay": sell_pay.get(int(f["slot"]), 0),
						}
					)
				)
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
			+ (
				TouchText.of("comms.opening", "Opening the channel…")
				if phone
				else TranslationServer.translate("comms.open_hint")
			)
		)
	return text


func _layout() -> void:
	_rects.clear()
	if not visible and card_id < 0:
		return
	var font: Font = get_theme_default_font()
	var phone: bool = is_inside_tree() and LayoutMode.is_phone(LayoutMode.form_of(self))
	var w: float = size.x if fill else minf(size.x - 24.0, MAX_W)
	var cols: int = 2 if phone and w >= PHONE_TWO_COLS_W else 1
	var gap: float = float(UiTheme.TOUCH_GAP) if phone else 4.0
	var row_min: float = PHONE_ROW_H if phone else ROW_H
	var row_w: float = (w - 2.0 * PAD - (cols - 1) * gap) / cols
	var body: Vector2 = font.get_multiline_string_size(
		_body(), HORIZONTAL_ALIGNMENT_LEFT, w - 2.0 * PAD, FONT_SIZE
	)
	# A row that doesn't fit on a line wraps and grows (a phone's trade offer).
	var heights: Array[float] = []
	var rows_h: float = 0.0
	for row: Dictionary in _rows:
		var text_h: float = (
			font
			. get_multiline_string_size(
				row_text(row), HORIZONTAL_ALIGNMENT_LEFT, row_w - 16.0, FONT_SIZE
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
	var foot: float = 70.0
	if phone:
		foot = PAD + UiTheme.TOUCH_PRIMARY + gap
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
		var x: float = _box.position.x + PAD + (i % cols) * (row_w + gap)
		_rects.append(Rect2(x, y, row_w, lines[line]))
		if i % cols == cols - 1 or i == _rows.size() - 1:
			y += lines[line] + gap
	_place_buttons(phone)
	queue_redraw()


## A phone's foot row (‹ › while the rows page, Close at the right) and the rows' targets.
func _place_buttons(phone: bool) -> void:
	var side: float = UiTheme.TOUCH_PRIMARY
	var y: float = _box.end.y - PAD - side
	var paged: bool = phone and _lines_shown < _line_count
	prev_button.visible = paged
	next_button.visible = paged
	close_button.visible = phone
	prev_button.disabled = first_line == 0
	next_button.disabled = not more_below()
	var x: float = _box.position.x + PAD
	for b: RailButton in [prev_button, next_button]:
		b.position = Vector2(x, y)
		b.size = Vector2(side, side)
		x += side + UiTheme.TOUCH_GAP
	close_button.position = Vector2(_box.end.x - PAD - CLOSE_W, y)
	close_button.size = Vector2(CLOSE_W, side)
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
	var hint_w: float = _box.size.x - 2.0 * PAD
	# A phone has no keys to hint at (#28): its foot row holds the buttons, and the status
	# between them.
	if close_button.visible:
		hint = ""
		var left: float = x
		if next_button.visible:
			left = next_button.position.x + next_button.size.x + UiTheme.TOUCH_GAP
		hint_w = close_button.position.x - UiTheme.TOUCH_GAP - left
		x = left
		foot_y = close_button.position.y + (close_button.size.y + font.get_ascent(FONT_SIZE)) / 2.0
	if status != "":
		hint = status
	draw_string(
		font,
		Vector2(x, foot_y),
		hint,
		0,
		hint_w,
		FONT_SIZE - 1,
		Palette.color("warn") if status != "" else Palette.color("text_dim")
	)


func _draw_row(font: Font, i: int) -> void:
	var r: Rect2 = _rects[i]
	if r.size == Vector2.ZERO:
		return
	var row: Dictionary = _rows[i]
	var off: bool = row["kind"] == "reply" and not bool(row["enabled"])
	draw_rect(r, Palette.color("panel_focus") if i == focus else Palette.color("background"))
	if i == focus:
		draw_rect(r, Palette.color("accent"), false, 2.0)
	var text: String = row_text(row)
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
