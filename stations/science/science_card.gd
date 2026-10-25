class_name ScienceCard
extends Control
## The contact card (§5.4, FT-SCI-002, D28, D51): class, identity, intent, weak points,
## resistances and hack access of the selected contact, each with a confidence bar. The
## bar is the scan confidence; its tick is the confidence at which the server reveals the
## part (ScienceDef). Below the tick the value reads "??" (never shown, never sent: the
## section carries a part only once it is revealed). The own ship shows its self-scan.

const FONT_SIZE: int = 14
const ROW_H: float = 46.0
const BAR_H: float = 6.0
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
var self_scanned: bool = false
var own: bool = false


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
	var y: float = 24.0
	_text(font, Vector2(10, y), callsign, Palette.color("text"), FONT_SIZE + 3)
	_bar(Vector2(10, y + 8.0), size.x - 20.0, scan, -1.0)
	_text(
		font,
		Vector2(10, y + 32.0),
		(
			"%s %d%%   %s %d%%"
			% [tr("sci.scan_conf"), roundi(scan * 100.0), tr("sci.detect"), roundi(detect * 100.0)]
		),
		Palette.color("text_dim"),
		FONT_SIZE - 2
	)
	y += 60.0
	for part: String in ["class", "identity", "intent", "weak_points", "resistances", "hack"]:
		_row(font, part, y, scan)
		y += ROW_H


func _row(font: Font, part: String, y: float, scan: float) -> void:
	var need: float = ScienceLookup.threshold(StringName(part))
	var shown: bool = scan >= need and scan > 0.0
	_text(font, Vector2(10, y), tr("sci.part_" + part), Palette.color("text_dim"), FONT_SIZE - 2)
	var value: String = _value(part) if shown else "??"
	_text(
		font,
		Vector2(10, y + 18.0),
		value,
		Palette.color("text") if shown else Palette.color("text_dim"),
		FONT_SIZE
	)
	_bar(Vector2(10, y + 26.0), size.x - 20.0, scan, need)


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
	if not bool(card.get("hack", false)):
		return "??"
	for h: Dictionary in hacks:
		return tr("sci.hack_window") % roundf(float(h["left"]))
	return tr("sci.hack_ready")


## A confidence bar from x, with a tick at `need` (negative: none).
func _bar(at: Vector2, width: float, value: float, need: float) -> void:
	draw_rect(Rect2(at, Vector2(width, BAR_H)), Palette.color("background"))
	draw_rect(
		Rect2(at, Vector2(width * clampf(value, 0.0, 1.0), BAR_H)),
		Palette.color("ok") if need < 0.0 or value >= need else Palette.color("warn")
	)
	if need >= 0.0 and need <= 1.0:
		var x: float = at.x + width * need
		draw_line(
			Vector2(x, at.y - 2.0), Vector2(x, at.y + BAR_H + 2.0), Palette.color("text"), 1.0
		)


func _text(font: Font, at: Vector2, text: String, col: Color, fs: int = FONT_SIZE) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, size.x - at.x - 6.0, fs, col)
