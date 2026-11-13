class_name ScienceCard
extends Control
## The contact card (§5.4, FT-SCI-002, D28, D51): class, identity, intent, weak points,
## resistances and hack access of the selected contact, each with a confidence bar. The
## bar is the scan confidence. The server says which parts it revealed (the card's
## `revealed` bits, BlockSchema.SCIENCE_REVEALED, 12r-23); until then the value reads "??"
## (never sent: the section carries a part only once it is revealed). The own ship shows
## its self-scan.

const FONT_SIZE: int = 14
const ROW_H: float = 46.0
const BAR_H: float = 6.0
## A phone's Card page shows the whole card without a scroll (#28 follow-up, design 2.4):
## the callsign and confidence share one line, and each part's row is shorter.
const COMPACT_HEAD_H: float = 40.0
const COMPACT_ROW_H: float = 40.0
## Intent texts by the card's intent code: 0 unknown, 1 no pilot, 2 + AiTable.Mode.
const INTENT_KEYS: Array[String] = [
	"sci.intent_none",
	"sci.intent_idle",
	"sci.intent_hold",
	"sci.intent_attack",
	"sci.intent_keep_range",
	"sci.intent_retreat"
]

## The shared callsign ("H2") and the section's card row ({} for a contact with none).
var callsign: String = ""
var card: Dictionary = {}
## Seconds left of a hack window on this contact: {"sub": index, "left": s} rows.
var hacks: Array = []
## The phone's compact layout (COMPACT_HEAD_H, COMPACT_ROW_H).
var compact: bool = false:
	set(value):
		compact = value
		queue_redraw()


## The height the card's rows need (compact: a phone's Card page, #28).
static func content_height(is_compact: bool = false) -> float:
	if is_compact:
		return COMPACT_HEAD_H + 6.0 * COMPACT_ROW_H
	return 24.0 + 60.0 + 6.0 * ROW_H


func set_card(p_callsign: String, p_card: Dictionary, p_hacks: Array) -> void:
	callsign = p_callsign
	card = p_card
	hacks = p_hacks
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("panel"))
	if card.is_empty():
		_text(font, Vector2(10, 24), tr("sci.card_none"), Palette.color("text_dim"))
		return
	var scan: float = float(card.get("scan", 0.0))
	var detect: float = float(card.get("detect", 0.0))
	var y: float = 24.0 if not compact else 20.0
	_text(font, Vector2(10, y), callsign, Palette.color("text"), FONT_SIZE + 3)
	var conf: String = (
		"%s %d%% (%s)   %s %d%%"
		% [
			tr("sci.scan_conf"),
			roundi(scan * 100.0),
			confidence_word(scan),
			tr("sci.detect"),
			roundi(detect * 100.0)
		]
	)
	if compact:
		var cw: float = (
			font.get_string_size(callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 3).x
		)
		_text(font, Vector2(22.0 + cw, y), conf, Palette.color("text_dim"), FONT_SIZE - 2)
		_bar(Vector2(10, y + 8.0), size.x - 20.0, scan, true)
		y = COMPACT_HEAD_H
	else:
		_bar(Vector2(10, y + 8.0), size.x - 20.0, scan, true)
		_text(font, Vector2(10, y + 32.0), conf, Palette.color("text_dim"), FONT_SIZE - 2)
		y += 60.0
	for part: String in ["class", "identity", "intent", "weak_points", "resistances", "hack"]:
		_row(font, part, y, scan)
		y += COMPACT_ROW_H if compact else ROW_H


## The scan confidence in a word: "sure" from 85 %, "likely" from 50 %, else "a guess".
static func confidence_word(scan: float) -> String:
	if scan >= 0.85:
		return TranslationServer.translate("sci.conf_sure")
	return TranslationServer.translate("sci.conf_likely" if scan >= 0.5 else "sci.conf_guess")


## Whether the server revealed the card's part (BlockSchema.SCIENCE_REVEALED's names).
static func is_revealed(row: Dictionary, part: StringName) -> bool:
	var bit: int = BlockSchema.SCIENCE_REVEALED.find(part)
	return bit >= 0 and (int(row.get("revealed", 0)) >> bit) & 1 == 1


func _row(font: Font, part: String, y: float, scan: float) -> void:
	var shown: bool = is_revealed(card, StringName(part))
	# Compact: label, value and bar 13, 30 and 33 px down a 40 px row.
	var label_y: float = y + (13.0 if compact else 0.0)
	_text(
		font, Vector2(10, label_y), tr("sci.part_" + part), Palette.color("text_dim"), FONT_SIZE - 2
	)
	var value: String = _value(part) if shown else "??"
	_text(
		font,
		Vector2(10, y + (30.0 if compact else 18.0)),
		value,
		Palette.color("text") if shown else Palette.color("text_dim"),
		FONT_SIZE
	)
	_bar(Vector2(10, y + (33.0 if compact else 26.0)), size.x - 20.0, scan, shown)


func _value(part: String) -> String:
	var out: String = ""
	match part:
		"class":
			var def: ShipDef = ScienceLookup.ship_class(int(card.get("class_id", 0)))
			out = def.display_name if def != null else "??"
		"identity":
			out = callsign
		"intent":
			out = tr(INTENT_KEYS[clampi(int(card.get("intent", 0)), 0, INTENT_KEYS.size() - 1)])
		"weak_points":
			out = _weak_points()
		"resistances":
			out = _resistances()
		"hack":
			out = _hack()
	return out


func _weak_points() -> String:
	var def: ShipDef = ScienceLookup.ship_class(int(card.get("class_id", 0)))
	var mask: int = int(card.get("weak_mask", 0))
	if def == null or mask == 0:
		return tr("sci.none")
	var names: PackedStringArray = []
	for i: int in def.subsystems.size():
		if (mask >> i) & 1 == 1:
			names.append(String(def.subsystems[i].id))
	return ", ".join(names)


func _resistances() -> String:
	var parts: PackedStringArray = []
	for r: Dictionary in card.get("resist", []):
		parts.append(
			(
				"%s %d%%"
				% [ScienceLookup.damage_name(int(r["type"])), roundi(float(r["factor"]) * 100.0)]
			)
		)
	return ", ".join(parts) if not parts.is_empty() else tr("sci.none")


func _hack() -> String:
	for h: Dictionary in hacks:
		return tr("sci.hack_window") % roundf(float(h["left"]))
	return tr("sci.hack_ready")


## A confidence bar from x: "ok" once its part is revealed, else "warn".
func _bar(at: Vector2, width: float, value: float, revealed: bool) -> void:
	BarPaint.draw(
		self,
		Rect2(at, Vector2(width, BAR_H)),
		value,
		Palette.color("ok") if revealed else Palette.color("warn"),
		Palette.color("background")
	)


func _text(font: Font, at: Vector2, text: String, col: Color, fs: int = FONT_SIZE) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, size.x - at.x - 6.0, fs, col)
