class_name Palette
extends RefCounted
## The UI palette (FT-STN-006, station-ui §2): colour-blind safe, after Okabe and Ito,
## and checked by tools/check_palette.py, which simulates protanopia, deuteranopia and
## tritanopia and fails when two roles of a group come too close. Colour is never the
## only code: allegiance also shows its letter (the callsign prefix) and a blip shape,
## alert level its letter and a chip shape.
##
## Keep every colour a `"role": Color("#rrggbb")` literal in ROLES: the checker parses
## them. GROUPS lists the roles that must stay apart from each other.

const ROLES: Dictionary = {
	# Allegiance (callsign prefixes, spec §6.1).
	"hostile": Color("#ff5a36"),
	"unknown": Color("#f0e442"),
	"friendly": Color("#56b4e9"),
	"neutral": Color("#c080a0"),
	"own": Color("#ffffff"),
	# Marks, pings and the selection.
	"mark": Color("#a0ffc0"),
	"ping": Color("#ffffff"),
	"selected": Color("#e0e0ff"),
	# Alert levels (provisional, asked of the owner): Normal, Yellow, Red.
	"alert_normal": Color("#3fbf7f"),
	"alert_yellow": Color("#e69f00"),
	"alert_red": Color("#d7263d"),
	# Seat load in the lobby (D187): intense, busy, light. Red is the deepest red that
	# still reads on a button in every colour-vision check.
	"load_intense": Color("#ff7a70"),
	"load_busy": Color("#f2c94c"),
	"load_light": Color("#35c9a0"),
	# Chrome.
	"background": Color("#0b0f14"),
	"panel": Color("#151b23"),
	"panel_focus": Color("#1f2a36"),
	"line": Color("#3a4654"),
	"text": Color("#e6edf3"),
	"text_dim": Color("#8b98a5"),
	"accent": Color("#58a6ff"),
	"warn": Color("#e69f00"),
	"danger": Color("#d7263d"),
	"ok": Color("#3fbf7f"),
}

## Roles that must stay distinguishable from each other under each simulated
## deficiency (tools/check_palette.py).
const GROUPS: Dictionary = {
	"allegiance": ["hostile", "unknown", "friendly", "neutral", "own"],
	"radar": ["hostile", "unknown", "friendly", "neutral", "mark", "selected"],
	"alert": ["alert_normal", "alert_yellow", "alert_red"],
	"load": ["load_intense", "load_busy", "load_light"],
}
## [foreground, background] pairs that must keep a readable contrast ratio under each
## simulated deficiency (tools/check_palette.py).
const CONTRAST: Array[Array] = [
	["text", "background"],
	["text", "panel"],
	["text", "panel_focus"],
	["text_dim", "background"],
	["text_dim", "panel"],
	["accent", "background"],
	["accent", "panel"],
	["load_intense", "panel"],
	["load_intense", "panel_focus"],
	["load_busy", "panel"],
	["load_busy", "panel_focus"],
	["load_light", "panel"],
	["load_light", "panel_focus"],
]

## Allegiance letter -> blip shape (station-ui §1.5; marks are diamonds everywhere, D44).
const ALLEGIANCE_SHAPES: Dictionary = {
	"H": "triangle",
	"U": "circle",
	"F": "square",
	"N": "hexagon",
	"": "circle",
}
## Allegiance letter -> role.
const ALLEGIANCE_ROLES: Dictionary = {
	"H": "hostile",
	"U": "unknown",
	"F": "friendly",
	"N": "neutral",
	"": "own",
}

## Alert levels (provisional): 0 Normal, 1 Yellow, 2 Red, each with role, letter,
## shape and translation key.
const ALERTS: Array[Dictionary] = [
	{"role": "alert_normal", "letter": "N", "shape": "circle", "key": "alert.normal"},
	{"role": "alert_yellow", "letter": "Y", "shape": "triangle", "key": "alert.yellow"},
	{"role": "alert_red", "letter": "R", "shape": "square", "key": "alert.red"},
]


static func color(role: String) -> Color:
	return ROLES.get(role, Color.MAGENTA)


## The allegiance letter of a callsign ("H2" -> "H"); "" for own ships and names.
static func allegiance(callsign: String) -> String:
	var letter: String = callsign.left(1)
	return letter if letter in ["H", "U", "F", "N"] and callsign.substr(1).is_valid_int() else ""


static func allegiance_color(letter: String) -> Color:
	return color(ALLEGIANCE_ROLES.get(letter, "own"))


static func alert(level: int) -> Dictionary:
	return ALERTS[clampi(level, 0, ALERTS.size() - 1)]


## Points of a shape ("circle", "triangle", "square", "hexagon", "diamond", "octagon") of radius
## r around c, for draw_polygon / draw_polyline (closed: first point repeated).
static func shape_points(shape: String, c: Vector2, r: float) -> PackedVector2Array:
	var n: int = 16
	var start: float = -PI / 2.0
	match shape:
		"triangle":
			n = 3
		"square":
			n = 4
			start = -PI / 4.0
		"diamond":
			n = 4
		"hexagon":
			n = 6
			start = 0.0
		"octagon":
			n = 8
			start = PI / 8.0
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n + 1:
		var a: float = start + TAU * float(i % n) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## A radar item's colour (ContactPicture items): marks in the mark colour, zones amber
## (hazard) or blue (scan position), else the allegiance colour.
static func item_color(it: Dictionary) -> Color:
	if it.get("kind", "") == "mark":
		return color("mark")
	if it.get("kind", "") == "zone":
		return color("warn" if it.get("zone", "") == "hazard" else "accent")
	if it.get("kind", "") == "site":
		return color("accent")
	return allegiance_color(it.get("allegiance", ""))


## A radar item's shape: diamonds for marks, octagons for zones, else the allegiance shape.
static func item_shape(it: Dictionary) -> String:
	if it.get("kind", "") == "mark":
		return "diamond"
	if it.get("kind", "") == "zone" or it.get("kind", "") == "site":
		return "octagon"
	return ALLEGIANCE_SHAPES.get(it.get("allegiance", ""), "circle")


## Text on `canvas` at baseline `base` with a background-coloured outline, readable over
## any view.
static func draw_outlined(
	canvas: CanvasItem, font: Font, base: Vector2, text: String, size: int, col: Color
) -> void:
	var bg: Color = color("background")
	canvas.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, bg)
	canvas.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
