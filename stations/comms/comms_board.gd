class_name CommsBoard
extends Control
## Comms' card board (§5.6, D87, FT-COM-008): missions, contracts, and offers with hails
## as cards in three columns, the docked flag and credits above, reputation per faction
## below. Each card shows its title, kind and state, reward and the reputation range where
## the data makes it visible (FT-COM-005), the time left and who holds its conversation
## (FT-COM-006, D18). It only draws and answers where things are; the panel decides what a
## card does. One card is selected (arrows, Tab, a click, a tap); `card_activated` fires for
## a click or tap on a card. A narrow board (a phone) shows one column at a time and a
## horizontal swipe changes it. On a phone's pages (#28 follow-up, D287) the board shows the
## page's column alone (`page_column`), without its header, footer and column title (the
## Rep page and the tab show them), with taller cards.

signal card_selected(id: int)
signal card_activated(id: int)

const HEADER_H: float = 34.0
const TITLE_H: float = 26.0
const FOOTER_H: float = 34.0
const CARD_H: float = 66.0
const GAP: float = 6.0
const FONT_SIZE: int = 15
## Under this width one column is shown at a time.
const NARROW_W: float = 640.0
## A press that moves less than this is a tap (px); a sideways move of SWIPE_PX is a swipe.
const TAP_PX: float = 12.0
const SWIPE_PX: float = 60.0
## A card's height on a phone's pages (design 2.6).
const PHONE_CARD_H: float = 72.0

## The COMMS block (CommsView) the board draws.
var data: Dictionary = {}
## The selected card's id, or -1.
var selected: int = -1
## Card id -> name of the session holding its conversation, "" for free.
var claim_names: Dictionary = {}
## The docked site's name ("" when the scenario names none or the ship is not docked).
var site_name: String = ""
## The session's own name, for "you" in the claimer line.
var own_name: String = ""
## The column a phone's page shows (0 to 2), or -1 for the board as on a desktop.
var page_column: int = -1:
	set(value):
		if value != page_column:
			page_column = value
			_fit()
			queue_redraw()

var _cols: Array = [[], [], []]
## First visible card of each column.
var _top: Array[int] = [0, 0, 0]
var _col_shown: int = 0
var _press: Vector2 = Vector2(-1.0, -1.0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()
		queue_redraw()


## Takes a new block; keeps the selection if its card is still there, else picks the first.
func set_data(blk: Dictionary) -> void:
	data = blk
	_cols = CommsData.columns(blk)
	if _find(selected).x < 0:
		selected = -1
		for i: int in CommsData.COLUMNS:
			if selected < 0 and not (_cols[i] as Array).is_empty():
				selected = int(_cols[i][0]["id"])
	_col_shown = _find(selected).x if selected >= 0 else clampi(_col_shown, 0, 2)
	_fit()
	queue_redraw()


## The selected card's row, or {}; {} too while a phone's page shows a column without it.
func selected_row() -> Dictionary:
	if page_column >= 0 and _find(selected).x != page_column:
		return {}
	return CommsData.card(data, selected)


## The column card `id` is in, or -1.
func column_of(id: int) -> int:
	return _find(id).x


## Shows column `col` on a phone's page and selects its first card unless the selection is
## already there.
func show_column(col: int) -> void:
	page_column = col
	var rows: Array = _cols[col]
	if _find(selected).x != col and not rows.is_empty():
		select(int(rows[0]["id"]))


func narrow() -> bool:
	return size.x < NARROW_W


## The column shown in a narrow board or on a phone's page.
func column_shown() -> int:
	return page_column if page_column >= 0 else _col_shown


## Moves the selection: dx columns (skipping empty ones, wrapping), dy cards in the column.
func move(dx: int, dy: int) -> void:
	var at: Vector2i = _find(selected)
	if at.x < 0:
		return
	if dx != 0:
		var col: int = at.x
		for _i: int in CommsData.COLUMNS:
			col = posmod(col + dx, CommsData.COLUMNS)
			if not (_cols[col] as Array).is_empty():
				break
		var rows: Array = _cols[col]
		select(int(rows[mini(at.y, rows.size() - 1)]["id"]))
	elif dy != 0:
		var rows: Array = _cols[at.x]
		select(int(rows[clampi(at.y + dy, 0, rows.size() - 1)]["id"]))


func select(id: int) -> void:
	if id == selected:
		return
	selected = id
	_col_shown = _find(id).x
	_fit()
	card_selected.emit(id)
	queue_redraw()


## Scrolls each column so the first visible card is in range and the selection shows.
func _fit() -> void:
	var per: int = _cards_per_column()
	for i: int in CommsData.COLUMNS:
		_top[i] = clampi(_top[i], 0, maxi(0, (_cols[i] as Array).size() - per))
	var at: Vector2i = _find(selected)
	if at.x < 0:
		return
	if at.y < _top[at.x]:
		_top[at.x] = at.y
	elif at.y >= _top[at.x] + per:
		_top[at.x] = at.y - per + 1


## Where the card sits: (column, row), or (-1, -1).
func _find(id: int) -> Vector2i:
	for i: int in CommsData.COLUMNS:
		for j: int in (_cols[i] as Array).size():
			if int(_cols[i][j]["id"]) == id:
				return Vector2i(i, j)
	return Vector2i(-1, -1)


# --- Layout. ---


## The columns drawn: all three, or the one shown when narrow.
func _drawn_columns() -> Array[int]:
	var out: Array[int] = [0, 1, 2]
	if page_column >= 0:
		out = [page_column]
	elif narrow():
		out = [_col_shown]
	return out


## The header, column title, footer and card heights: none of the first three on a page.
func _header_h() -> float:
	return 0.0 if page_column >= 0 else HEADER_H


func _title_h() -> float:
	return 0.0 if page_column >= 0 else TITLE_H


func _footer_h() -> float:
	return 0.0 if page_column >= 0 else FOOTER_H


func _card_h() -> float:
	return PHONE_CARD_H if page_column >= 0 else CARD_H


func _col_rect(col: int) -> Rect2:
	var shown: Array[int] = _drawn_columns()
	var w: float = size.x / shown.size()
	var at: int = shown.find(col)
	if at < 0:
		return Rect2()
	return Rect2(at * w, _header_h(), w, size.y - _header_h() - _footer_h())


func _cards_per_column() -> int:
	var h: float = size.y - _header_h() - _title_h() - _footer_h()
	return maxi(1, int(floorf((h + GAP) / (_card_h() + GAP))))


## The rectangle of a card in the board, or an empty one when it is scrolled out or hidden.
func card_rect(id: int) -> Rect2:
	var at: Vector2i = _find(id)
	if at.x < 0:
		return Rect2()
	var col: Rect2 = _col_rect(at.x)
	if col.size == Vector2.ZERO:
		return Rect2()
	var slot: int = at.y - _top[at.x]
	if slot < 0 or slot >= _cards_per_column():
		return Rect2()
	return Rect2(
		col.position.x + 4.0,
		col.position.y + _title_h() + slot * (_card_h() + GAP),
		col.size.x - 8.0,
		_card_h()
	)


## The id of the card under `pos` (local), or -1.
func card_at(pos: Vector2) -> int:
	for i: int in _drawn_columns():
		var rows: Array = _cols[i]
		for j: int in rows.size():
			if card_rect(int(rows[j]["id"])).has_point(pos):
				return int(rows[j]["id"])
	return -1


# --- Input. ---


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press = event.position
		return
	var moved: Vector2 = event.position - _press
	_press = Vector2(-1.0, -1.0)
	var one: bool = narrow() or page_column >= 0
	if one and absf(moved.x) >= SWIPE_PX and absf(moved.x) > absf(moved.y):
		_swipe(-1 if moved.x > 0.0 else 1)
	elif moved.length() <= TAP_PX:
		var id: int = card_at(event.position)
		if id >= 0:
			select(id)
			card_activated.emit(id)


## Swipes to the next non-empty column (dx +1: the column to the right).
func _swipe(dx: int) -> void:
	var col: int = column_shown()
	for _i: int in CommsData.COLUMNS:
		col = posmod(col + dx, CommsData.COLUMNS)
		if not (_cols[col] as Array).is_empty():
			break
	var rows: Array = _cols[col]
	if not rows.is_empty():
		select(int(rows[0]["id"]))


# --- Drawing. ---


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background"))
	if page_column < 0:
		_draw_header(font)
		_draw_footer(font)
	for i: int in _drawn_columns():
		_draw_column(font, i)


## "COMMS   docked: Kappa", or the same with "not docked".
func header_text() -> String:
	return "%s   %s" % [TranslationServer.translate("station.comms"), where_text()]


## "docked: Kappa", "docked" or "not docked".
func where_text() -> String:
	if not bool(data.get("docked", false)):
		return TranslationServer.translate("comms.undocked")
	return (
		TranslationServer.translate("comms.docked") % site_name
		if site_name != ""
		else TranslationServer.translate("comms.docked_unnamed")
	)


## "hull ok   cr 1200": Comms' only view of condition, the hull band (FT-PAIR-010), and credits.
func status_text() -> String:
	var bands: Array[String] = ["ok", "scratched", "damaged", "critical"]
	var band: String = bands[clampi(int(data.get("hull_band", 0)), 0, bands.size() - 1)]
	return (
		"%s   %s"
		% [
			TranslationServer.translate("comms.hull") % TranslationServer.translate("band." + band),
			TranslationServer.translate("comms.credits") % int(data.get("credits", 0)),
		]
	)


## "Reputation  F1 +12   F2 -2": the standing with each faction (FT-COM-005).
func rep_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for r: Dictionary in data.get("rep", []):
		parts.append(
			(
				TranslationServer.translate("comms.rep_row")
				% [int(r["faction"]), roundi(float(r["value"]))]
			)
		)
	return TranslationServer.translate("comms.rep") + "  " + "   ".join(parts)


func _draw_header(font: Font) -> void:
	var right: String = status_text()
	var base: float = (HEADER_H + font.get_ascent(FONT_SIZE)) / 2.0 - 2.0
	draw_string(
		font, Vector2(8.0, base), header_text(), 0, size.x * 0.6, FONT_SIZE, Palette.color("text")
	)
	var w: float = font.get_string_size(right, 0, -1, FONT_SIZE).x
	draw_string(
		font, Vector2(size.x - w - 8.0, base), right, 0, -1, FONT_SIZE, Palette.color("accent")
	)
	draw_line(Vector2(0, HEADER_H - 1.0), Vector2(size.x, HEADER_H - 1.0), Palette.color("line"))


func _draw_column(font: Font, col: int) -> void:
	var rect: Rect2 = _col_rect(col)
	var rows: Array = _cols[col]
	var title: String = TranslationServer.translate(CommsData.COLUMN_KEYS[col])
	if narrow():
		title += "  (%d/%d)" % [col + 1, CommsData.COLUMNS]
	if page_column < 0:
		draw_string(
			font,
			Vector2(rect.position.x + 8.0, rect.position.y + font.get_ascent(FONT_SIZE) + 2.0),
			title,
			0,
			rect.size.x - 16.0,
			FONT_SIZE,
			Palette.color("text_dim")
		)
	if rows.is_empty():
		draw_string(
			font,
			Vector2(
				rect.position.x + 8.0, rect.position.y + _title_h() + font.get_ascent(FONT_SIZE)
			),
			TranslationServer.translate("comms.empty"),
			0,
			rect.size.x - 16.0,
			FONT_SIZE - 2,
			Palette.color("text_dim")
		)
		return
	var above: Rect2 = Rect2()
	for j: int in rows.size():
		var r: Rect2 = card_rect(int(rows[j]["id"]))
		if r.size != Vector2.ZERO:
			_draw_card(font, r, rows[j])
			if above.size != Vector2.ZERO:
				ListLines.between(self, above, r)
			above = r


func _draw_card(font: Font, r: Rect2, c: Dictionary) -> void:
	var live: bool = CardList.is_live(c)
	var sel: bool = int(c["id"]) == selected
	draw_rect(r, Palette.color("panel_focus") if sel else Palette.color("panel"))
	if sel:
		draw_rect(r, Palette.color("accent"), false, 2.0)
	var text: Color = Palette.color("text") if live else Palette.color("text_dim")
	var dim: Color = Palette.color("text_dim")
	var x: float = r.position.x + 8.0
	var y: float = r.position.y + 4.0 + font.get_ascent(FONT_SIZE)
	var time: String = CardList.clock(float(c["expires"])) if live else ""
	var tw: float = font.get_string_size(time, 0, -1, FONT_SIZE).x if time != "" else 0.0
	var mark: String = "! " if (int(c["kind"]) == CardList.HAIL and int(c["state"]) == 0) else ""
	draw_string(
		font,
		Vector2(x, y),
		mark + TranslationServer.translate(str(c["title"])),
		0,
		r.size.x - 20.0 - tw,
		FONT_SIZE,
		Palette.color("warn") if mark != "" else text
	)
	if time != "":
		draw_string(
			font, Vector2(r.end.x - 8.0 - tw, y), time, 0, -1, FONT_SIZE, Palette.color("warn")
		)
	y += FONT_SIZE + 3.0
	var line: String = "%s · %s" % [CardList.kind_text(c), CommsData.state_text(int(c["state"]))]
	if str(c["npc"]) != "":
		line += " · " + str(c["npc"])
	draw_string(font, Vector2(x, y), line, 0, r.size.x - 16.0, FONT_SIZE - 2, dim)
	y += FONT_SIZE
	var extra: PackedStringArray = PackedStringArray()
	if int(c["reward"]) != 0:
		extra.append(TranslationServer.translate("comms.reward") % int(c["reward"]))
	var range_text: String = CommsData.range_text(c)
	if range_text != "":
		extra.append(range_text)
	var holder: String = str(claim_names.get(int(c["id"]), ""))
	if holder != "":
		extra.append(
			(
				TranslationServer.translate("comms.claimed_by")
				% (TranslationServer.translate("comms.you") if holder == own_name else holder)
			)
		)
	draw_string(font, Vector2(x, y), " · ".join(extra), 0, r.size.x - 16.0, FONT_SIZE - 2, dim)


func _draw_footer(font: Font) -> void:
	var y: float = size.y - FOOTER_H
	draw_line(Vector2(0, y), Vector2(size.x, y), Palette.color("line"))
	draw_string(
		font,
		Vector2(8.0, y + (FOOTER_H + font.get_ascent(FONT_SIZE)) / 2.0 - 2.0),
		rep_text(),
		0,
		size.x - 16.0,
		FONT_SIZE,
		Palette.color("text")
	)
