class_name FixtureCards
extends Control
## The list of Comms' mission and contract cards (FT-CPT-004, D190). Until Comms and #10
## exist the cards are fixtures read from content/fixtures/comms_cards.json; the Comms
## half of Approach, Parley, Quartermaster and Intel uses this same widget in phase 3.
## One row per card; `card_at(pos)` names the row under a point so the panel's ping
## (FT-CPT-005) can address it. `draw_card` draws one card large, for the main screen.

const PATH: String = "res://content/fixtures/comms_cards.json"
const ROW_HEIGHT: float = 46.0
const HEADER_HEIGHT: float = 26.0
const FONT_SIZE: int = 15

static var _loaded: Array[Dictionary] = []

## Card ids shown pinged (the main screen's card); -1 for none.
var highlight: int = -1

var _cards: Array[Dictionary] = []


## The fixture cards: {"id", "kind" ("mission" | "contract"), "title", "detail" (i18n
## keys), "time_s"}. Read once.
static func all() -> Array[Dictionary]:
	if _loaded.is_empty() and FileAccess.file_exists(PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			for c: Variant in (data as Dictionary).get("cards", []):
				_loaded.append(c as Dictionary)
	return _loaded


## The card with this id, or {}.
static func find(id: int) -> Dictionary:
	for c: Dictionary in all():
		if int(c["id"]) == id:
			return c
	return {}


## "9:30" for a time in seconds; "" for none.
static func clock(time_s: int) -> String:
	return "" if time_s <= 0 else "%d:%02d" % [time_s / 60, time_s % 60]


## Draws one card in `rect` of `item`: kind and title, detail, time left.
static func draw_card(item: CanvasItem, rect: Rect2, card: Dictionary, size_px: int) -> void:
	var font: Font = ThemeDB.fallback_font
	item.draw_rect(rect, Palette.color("panel"))
	item.draw_rect(rect, Palette.color("accent"), false, 2.0)
	var pad: float = size_px * 0.6
	var kind: String = TranslationServer.translate("card.kind_" + str(card.get("kind", "mission")))
	var y: float = rect.position.y + pad + font.get_ascent(size_px)
	item.draw_string(
		font, Vector2(rect.position.x + pad, y), kind, 0, -1, size_px, Palette.color("text_dim")
	)
	var time: String = clock(int(card.get("time_s", 0)))
	if time != "":
		var w: float = font.get_string_size(time, 0, -1, size_px).x
		item.draw_string(
			font, Vector2(rect.end.x - pad - w, y), time, 0, -1, size_px, Palette.color("warn")
		)
	y += font.get_height(size_px) * 1.1
	var title: String = TranslationServer.translate(str(card.get("title", "")))
	item.draw_string(
		font,
		Vector2(rect.position.x + pad, y),
		title,
		0,
		rect.size.x - 2.0 * pad,
		int(size_px * 1.3),
		Palette.color("text")
	)
	y += font.get_height(size_px) * 1.2
	var detail: String = TranslationServer.translate(str(card.get("detail", "")))
	item.draw_string(
		font,
		Vector2(rect.position.x + pad, y),
		detail,
		0,
		rect.size.x - 2.0 * pad,
		size_px,
		Palette.color("text_dim")
	)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lists `cards` (default: the fixtures).
func setup(cards: Array[Dictionary] = []) -> void:
	_cards = cards if not cards.is_empty() else all()
	custom_minimum_size = Vector2(0, HEADER_HEIGHT + ROW_HEIGHT * _cards.size())
	queue_redraw()


## The id of the card whose row holds `pos` (local), or -1.
func card_at(pos: Vector2) -> int:
	var row: int = int(floorf((pos.y - HEADER_HEIGHT) / ROW_HEIGHT))
	if pos.y < HEADER_HEIGHT or row < 0 or row >= _cards.size() or pos.x < 0.0 or pos.x > size.x:
		return -1
	return int(_cards[row]["id"])


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_string(
		font,
		Vector2(0.0, font.get_ascent(FONT_SIZE) + 2.0),
		TranslationServer.translate("captain.cards"),
		0,
		-1,
		FONT_SIZE,
		Palette.color("text_dim")
	)
	for i: int in _cards.size():
		var c: Dictionary = _cards[i]
		var r: Rect2 = Rect2(0.0, HEADER_HEIGHT + i * ROW_HEIGHT, size.x, ROW_HEIGHT - 4.0)
		if int(c["id"]) == highlight:
			draw_rect(r, Palette.color("panel_focus"))
			draw_rect(r, Palette.color("accent"), false, 2.0)
		else:
			draw_rect(r, Palette.color("panel"))
		var base: float = r.position.y + 4.0 + font.get_ascent(FONT_SIZE)
		var title: String = TranslationServer.translate(str(c["title"]))
		draw_string(
			font, Vector2(8.0, base), title, 0, size.x - 80.0, FONT_SIZE, Palette.color("text")
		)
		var time: String = clock(int(c.get("time_s", 0)))
		if time != "":
			var w: float = font.get_string_size(time, 0, -1, FONT_SIZE).x
			draw_string(
				font, Vector2(size.x - 8.0 - w, base), time, 0, -1, FONT_SIZE, Palette.color("warn")
			)
		var kind: String = TranslationServer.translate("card.kind_" + str(c["kind"]))
		draw_string(
			font, Vector2(8.0, base + 18.0), kind, 0, -1, FONT_SIZE - 2, Palette.color("text_dim")
		)
