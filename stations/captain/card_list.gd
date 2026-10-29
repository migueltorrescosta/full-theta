class_name CardList
extends Control
## The list of Comms' cards, read-only (FT-CPT-004, D190): the Captain's list of missions and
## contracts, and the Comms half of Approach, Parley, Quartermaster and Intel. Rows are the
## live card rows of the COMMS block (CommsView; `rows` lists them from a view). One row per
## card; `card_at(pos)` names the row under a point so the panel's ping (FT-CPT-005) can
## address it. `draw_card` draws one card large, for the main screen.

## CommsView's card kinds (StoryTable.Kind) and the two live states, as numbers: stations
## never name sim/ (FT-ARC-011).
const MISSION: int = 0
const CONTRACT: int = 1
const OFFER: int = 2
const HAIL: int = 3
## A card that only tells (Q23): nothing to accept.
const INFO: int = 4
const KIND_NAMES: Array[String] = ["mission", "contract", "offer", "hail", "info"]
const STATE_OPEN: int = 0
const STATE_ACCEPTED: int = 1

const ROW_HEIGHT: float = 46.0
const HEADER_HEIGHT: float = 26.0
const HEADING_H: float = 24.0
## The rows stop this far from the right edge (a scrollbar can sit there).
const MARGIN_R: float = 6.0
const FONT_SIZE: int = 15

## A station's name above the header ("Comms" in a joint view), "" for none.
var heading: String = ""
## Card id shown pinged (the main screen's card); -1 for none.
var highlight: int = -1

var _cards: Array[Dictionary] = []


## The live card rows of the view's COMMS block of the given kinds (all when empty).
static func rows(view: NetViewState, kinds: Array[int] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in view.blocks.get(StationViews.Section.COMMS, {}).get("cards", []):
		if is_live(c) and (kinds.is_empty() or int(c["kind"]) in kinds):
			out.append(c)
	return out


static func is_live(card: Dictionary) -> bool:
	return int(card["state"]) in [STATE_OPEN, STATE_ACCEPTED]


## The card's kind word, translated ("Mission").
static func kind_text(card: Dictionary) -> String:
	var kind: int = clampi(int(card["kind"]), 0, KIND_NAMES.size() - 1)
	return TranslationServer.translate("card.kind_" + KIND_NAMES[kind])


## "9:30" for a time left in seconds; "" for none (a negative time).
static func clock(time_s: float) -> String:
	if time_s < 0.0:
		return ""
	var s: int = ceili(time_s)
	return "%d:%02d" % [s / 60, s % 60]


## Draws one card in `rect` of `item`: kind and title, detail, time left.
static func draw_card(item: CanvasItem, rect: Rect2, card: Dictionary, size_px: int) -> void:
	var font: Font = UiTheme.font()
	item.draw_rect(rect, Palette.color("panel"))
	item.draw_rect(rect, Palette.color("accent"), false, 2.0)
	var pad: float = size_px * 0.6
	var y: float = rect.position.y + pad + font.get_ascent(size_px)
	item.draw_string(
		font,
		Vector2(rect.position.x + pad, y),
		kind_text(card),
		0,
		-1,
		size_px,
		Palette.color("text_dim")
	)
	var time: String = clock(float(card.get("expires", -1.0)))
	if time != "":
		var w: float = font.get_string_size(time, 0, -1, size_px).x
		item.draw_string(
			font, Vector2(rect.end.x - pad - w, y), time, 0, -1, size_px, Palette.color("warn")
		)
	y += font.get_height(size_px) * 1.1
	item.draw_string(
		font,
		Vector2(rect.position.x + pad, y),
		TranslationServer.translate(str(card.get("title", ""))),
		0,
		rect.size.x - 2.0 * pad,
		int(size_px * 1.3),
		Palette.color("text")
	)
	y += font.get_height(size_px) * 1.2
	var detail: String = str(card.get("detail", ""))
	if detail != "":
		item.draw_string(
			font,
			Vector2(rect.position.x + pad, y),
			TranslationServer.translate(detail),
			0,
			rect.size.x - 2.0 * pad,
			size_px,
			Palette.color("text_dim")
		)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lists `cards` (rows of the COMMS block).
func setup(cards: Array[Dictionary]) -> void:
	if cards == _cards:
		return
	_cards = cards
	_fit()
	queue_redraw()


## Sets the heading, which sits above the header.
func set_heading(text: String) -> void:
	if text == heading:
		return
	heading = text
	_fit()
	queue_redraw()


func _top() -> float:
	return HEADING_H if heading != "" else 0.0


func _fit() -> void:
	custom_minimum_size = Vector2(0, _top() + HEADER_HEIGHT + ROW_HEIGHT * maxi(_cards.size(), 1))


## The id of the card whose row holds `pos` (local), or -1.
func card_at(pos: Vector2) -> int:
	var row: int = int(floorf((pos.y - _top() - HEADER_HEIGHT) / ROW_HEIGHT))
	if (
		pos.y < _top() + HEADER_HEIGHT
		or row < 0
		or row >= _cards.size()
		or pos.x < 0.0
		or pos.x > size.x
	):
		return -1
	return int(_cards[row]["id"])


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var top: float = _top()
	var wide: float = size.x - (MARGIN_R if heading != "" else 0.0)
	if heading != "":
		draw_string(
			font,
			Vector2(0.0, font.get_ascent(FONT_SIZE) + 2.0),
			heading,
			0,
			-1,
			FONT_SIZE,
			Palette.color("accent")
		)
	draw_string(
		font,
		Vector2(0.0, top + font.get_ascent(FONT_SIZE) + 2.0),
		TranslationServer.translate("captain.cards"),
		0,
		-1,
		FONT_SIZE,
		Palette.color("text_dim")
	)
	if _cards.is_empty():
		draw_string(
			font,
			Vector2(8.0, top + HEADER_HEIGHT + font.get_ascent(FONT_SIZE) + 4.0),
			TranslationServer.translate("cards.none"),
			0,
			-1,
			FONT_SIZE - 2,
			Palette.color("text_dim")
		)
	for i: int in _cards.size():
		var c: Dictionary = _cards[i]
		var r: Rect2 = Rect2(0.0, top + HEADER_HEIGHT + i * ROW_HEIGHT, wide, ROW_HEIGHT - 4.0)
		if i > 0:
			ListLines.between(
				self, Rect2(0.0, r.position.y - ROW_HEIGHT, wide, ROW_HEIGHT - 4.0), r
			)
		if int(c["id"]) == highlight:
			draw_rect(r, Palette.color("panel_focus"))
			draw_rect(r, Palette.color("accent"), false, 2.0)
		else:
			draw_rect(r, Palette.color("panel"))
		var base: float = r.position.y + 4.0 + font.get_ascent(FONT_SIZE)
		var title: String = TranslationServer.translate(str(c["title"]))
		draw_string(
			font, Vector2(8.0, base), title, 0, wide - 80.0, FONT_SIZE, Palette.color("text")
		)
		var time: String = clock(float(c["expires"]))
		if time != "":
			var w: float = font.get_string_size(time, 0, -1, FONT_SIZE).x
			draw_string(
				font, Vector2(wide - 8.0 - w, base), time, 0, -1, FONT_SIZE, Palette.color("warn")
			)
		draw_string(
			font,
			Vector2(8.0, base + 18.0),
			kind_text(c),
			0,
			-1,
			FONT_SIZE - 2,
			Palette.color("text_dim")
		)
