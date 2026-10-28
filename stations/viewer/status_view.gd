class_name StatusView
extends Control
## The main screen's status view (FT-MSC-006, D60): hull, shields, each subsystem's
## health, the active objectives and the alert level, big enough to read across a room.
## `model()` turns the blocks into the rows it draws, so tests check the numbers without
## a renderer. Read-only, like the whole main screen.

const FONT_SIZE: int = 22
const BAR_HEIGHT: float = 18.0
const ROW_GAP: float = 12.0
## The bar colour role of each health band (D193: split at 75, 50 and 25 %).
const BAR_ROLES: Array[String] = ["ok", "warn", "warn", "danger"]

## Space (px) kept free at the top: the phone's view-top row over the Captain's mirror.
var top: float = 0.0:
	set(value):
		if value != top:
			top = value
			queue_redraw()

var _model: Dictionary = {}


## The rows to draw: {"hull": 0..1, "shields": 0..1, "alert": level, "subsystems":
## [{"id", "frac"}], "objectives": [text]}. `status` is the STATUS block, `captain` the
## CAPTAIN block (either may be {} before the first snapshot) and `def` the ship's
## definition (null: fractions of the largest value seen are not guessed, they are 0).
static func model(status: Dictionary, captain: Dictionary, def: ShipDef, alert: int) -> Dictionary:
	var hull_max: float = def.hull_max if def != null else 0.0
	var shield_max: float = def.shields.max_strength if def != null and def.shields != null else 0.0
	var subs: Array[Dictionary] = []
	var rows: Array = captain.get("subsystems", [])
	for i: int in rows.size():
		var sd: SubsystemDef = null
		if def != null and i < def.subsystems.size():
			sd = def.subsystems[i]
		var max_h: float = sd.health_max if sd != null else 0.0
		var id: String = String(sd.id) if sd != null else str(i)
		subs.append({"id": id, "frac": _frac(float(rows[i]["health"]), max_h)})
	var objectives: Array[String] = []
	for o: Dictionary in captain.get("objectives", []):
		objectives.append(objective_text(int(o["kind"]), int(o["left"])))
	return {
		"hull": _frac(float(status.get("hull", 0.0)), hull_max),
		"shields": _frac(float(status.get("shields", 0.0)), shield_max),
		"alert": alert,
		"subsystems": subs,
		"objectives": objectives,
	}


## The line for an objective of the CAPTAIN block (StationViews.OBJECTIVE_*), `left` to do.
static func objective_text(kind: int, left: int) -> String:
	match kind:
		StationViews.OBJECTIVE_DESTROY_HOSTILES:
			return TranslationServer.translate("status.obj_hostiles") % left
	return TranslationServer.translate("status.obj_unknown")


static func _frac(value: float, max_value: float) -> float:
	return clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


## The palette role of a bar filled to `frac` (0..1).
static func bar_role(frac: float) -> String:
	return BAR_ROLES[HealthBand.band_of(frac)]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Takes the next frame's model and redraws when it changed.
func show_model(m: Dictionary) -> void:
	if m == _model:
		return
	_model = m
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background"))
	if _model.is_empty():
		return
	var font: Font = get_theme_default_font()
	var x: float = 32.0
	var y: float = 20.0 + top
	var w: float = size.x * 0.5 - 2.0 * x
	y = _bar(font, x, y, w, TranslationServer.translate("status.hull"), _model["hull"])
	y = _bar(font, x, y, w, TranslationServer.translate("status.shields"), _model["shields"])
	var alert: Dictionary = Palette.alert(int(_model["alert"]))
	var role: Color = Palette.color(alert["role"])
	var label: String = (
		"%s: %s"
		% [TranslationServer.translate("status.alert"), TranslationServer.translate(alert["key"])]
	)
	var base: Vector2 = Vector2(x, y + font.get_ascent(FONT_SIZE))
	var chip: PackedVector2Array = Palette.shape_points(
		alert["shape"], base + Vector2(10.0, -8.0), 11.0
	)
	draw_colored_polygon(chip.slice(0, -1), role)
	draw_string(font, base + Vector2(30.0, 0.0), label, 0, -1, FONT_SIZE, role)
	y += font.get_height(FONT_SIZE) + ROW_GAP * 2.0
	# Objectives under the alert.
	var head: String = TranslationServer.translate("status.objectives")
	draw_string(
		font,
		Vector2(x, y + font.get_ascent(FONT_SIZE)),
		head,
		0,
		-1,
		FONT_SIZE,
		Palette.color("text_dim")
	)
	y += font.get_height(FONT_SIZE) + 4.0
	var objectives: Array = _model["objectives"]
	if objectives.is_empty():
		objectives = [TranslationServer.translate("status.no_objectives")]
	for text: String in objectives:
		draw_string(
			font,
			Vector2(x + 12.0, y + font.get_ascent(FONT_SIZE)),
			text,
			0,
			w,
			FONT_SIZE,
			Palette.color("text")
		)
		y += font.get_height(FONT_SIZE) + 4.0
	# Subsystem health on the right.
	var rx: float = size.x * 0.5 + x
	var ry: float = 20.0 + top
	var sub_head: String = TranslationServer.translate("status.subsystems")
	draw_string(
		font,
		Vector2(rx, ry + font.get_ascent(FONT_SIZE)),
		sub_head,
		0,
		-1,
		FONT_SIZE,
		Palette.color("text_dim")
	)
	ry += font.get_height(FONT_SIZE) + ROW_GAP
	for s: Dictionary in _model["subsystems"]:
		var name: String = TranslationServer.translate("eng.name." + str(s["id"]))
		ry = _bar(font, rx, ry, w, name, float(s["frac"]))


## One labelled bar; returns the y below it. Colour follows the fraction, the percentage
## is printed too (colour is never the only code, FT-STN-006).
func _bar(font: Font, x: float, y: float, w: float, name: String, frac: float) -> float:
	draw_string(
		font,
		Vector2(x, y + font.get_ascent(FONT_SIZE)),
		name,
		0,
		-1,
		FONT_SIZE,
		Palette.color("text")
	)
	var pct: String = "%d%%" % roundi(frac * 100.0)
	var pw: float = font.get_string_size(pct, 0, -1, FONT_SIZE).x
	draw_string(
		font,
		Vector2(x + w - pw, y + font.get_ascent(FONT_SIZE)),
		pct,
		0,
		-1,
		FONT_SIZE,
		Palette.color("text")
	)
	y += font.get_height(FONT_SIZE) + 4.0
	var r: Rect2 = Rect2(x, y, w, BAR_HEIGHT)
	draw_rect(r, Palette.color("panel"))
	var role: String = bar_role(frac)
	draw_rect(Rect2(x, y, w * frac, BAR_HEIGHT), Palette.color(role))
	draw_rect(r, Palette.color("line"), false, 1.0)
	return y + BAR_HEIGHT + ROW_GAP
