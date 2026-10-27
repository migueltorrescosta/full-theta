class_name ControlsFigure
extends RefCounted
## The hardware drawn by the controls diagram (FT-STN-011, D185): a keyboard with its
## navigation cluster and numpad plus a mouse for KB/M, a controller for the pad. Pure
## geometry in design pixels, built once per device; ControlsDiagram draws it and
## ControlsModel maps binding tokens (input/README.md grammar) onto its parts.
##
## A part is {"id", "shape" ("rect", "round" or "circle"), "rect", "caption"}. Its `id`
## is the binding token that lands on it ("W", "Kp 1", "LMB", "LB", "Up"); "" for
## decorative parts. Several parts may share an id (the two Shift keys): the first is
## the callout anchor. `body` is the outline drawn behind the parts.

## The hardware zone's width and the keyboard's key pitch.
const ZONE_W: float = 700.0
const U: float = 30.0
const KEY: float = 28.0
## A caption that is meant to be empty (an empty one falls back to the id).
const BLANK: String = " "

static var _cache: Dictionary = {}


## {"parts": Array[Dictionary], "body": Array[Dictionary], "size": Vector2} of `device`.
## `dy` moves the mouse that far down (room for labels under the keyboard).
static func get_figure(device: String, dy: float = 0.0) -> Dictionary:
	var key: String = "%s:%d" % [device, roundi(dy)]
	if not _cache.has(key):
		_cache[key] = _pad() if device == IntentTable.PAD else _kbm(dy)
	return _cache[key]


## The part ids a binding token can land on for `device`.
static func ids(device: String) -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in get_figure(device)["parts"]:
		if p["id"] != "":
			out[p["id"]] = true
	return out


## The first part with `id`, or {}.
static func part(device: String, id: String, dy: float = 0.0) -> Dictionary:
	for p: Dictionary in get_figure(device, dy)["parts"]:
		if p["id"] == id:
			return p
	return {}


static func _part(
	id: String, rect: Rect2, caption: String = "", shape: String = "rect"
) -> Dictionary:
	return {"id": id, "rect": rect, "caption": caption if caption != "" else id, "shape": shape}


## A key at column `c` and row `r` of the key grid (units of U), `w` units wide.
static func _key(
	id: String, c: float, r: float, w: float = 1.0, caption: String = ""
) -> Dictionary:
	return _part(id, Rect2(c * U, r * U, w * U - (U - KEY), KEY), caption)


## A numpad key two rows tall.
static func _tall(id: String, c: float, r: float, caption: String) -> Dictionary:
	return _part(id, Rect2(c * U, r * U, KEY, U + KEY), caption)


static func _kbm(dy: float) -> Dictionary:
	var parts: Array[Dictionary] = []
	# Function row.
	parts.append(_key("Escape", 0, 0, 1, "Esc"))
	for i: int in 12:
		var c: float = 2.0 + i + 0.5 * floorf(i / 4.0)
		parts.append(_key("F%d" % (i + 1), c, 0))
	# Number row.
	parts.append(_key("QuoteLeft", 0, 1.5, 1, "`"))
	for i: int in 10:
		parts.append(_key(str((i + 1) % 10), 1.0 + i, 1.5))
	parts.append(_key("Minus", 11, 1.5, 1, "-"))
	parts.append(_key("Equal", 12, 1.5, 1, "="))
	parts.append(_key("Backspace", 13, 1.5, 2, "Bksp"))
	# Top letter row.
	parts.append(_key("Tab", 0, 2.5, 1.5))
	_letters(parts, "QWERTYUIOP", 1.5, 2.5)
	parts.append(_key("BracketLeft", 11.5, 2.5, 1, "["))
	parts.append(_key("BracketRight", 12.5, 2.5, 1, "]"))
	parts.append(_key("Backslash", 13.5, 2.5, 1.5, "\\"))
	# Home row.
	parts.append(_key("", 0, 3.5, 1.75, "Caps"))
	_letters(parts, "ASDFGHJKL", 1.75, 3.5)
	parts.append(_key("Semicolon", 10.75, 3.5, 1, ";"))
	parts.append(_key("Apostrophe", 11.75, 3.5, 1, "'"))
	parts.append(_key("Enter", 12.75, 3.5, 2.25))
	# Bottom letter row.
	parts.append(_key("Shift", 0, 4.5, 2.25))
	_letters(parts, "ZXCVBNM", 2.25, 4.5)
	parts.append(_key("Comma", 9.25, 4.5, 1, ","))
	parts.append(_key("Period", 10.25, 4.5, 1, "."))
	parts.append(_key("?", 11.25, 4.5))
	parts.append(_key("Shift", 12.25, 4.5, 2.75))
	# Space row.
	parts.append(_key("Ctrl", 0, 5.5, 1.25))
	parts.append(_key("", 1.25, 5.5, 1.25, "Win"))
	parts.append(_key("Alt", 2.5, 5.5, 1.25))
	parts.append(_key("Space", 3.75, 5.5, 6.25))
	parts.append(_key("Alt", 10.0, 5.5, 1.25))
	parts.append(_key("", 11.25, 5.5, 1.25, "Win"))
	parts.append(_key("", 12.5, 5.5, 1.25, "Fn"))
	parts.append(_key("Ctrl", 13.75, 5.5, 1.25))
	# Navigation cluster and arrows.
	var nav: float = 15.3
	for i: int in 3:
		var top: String = ["Insert", "Home", "PageUp"][i]
		var low: String = ["Delete", "End", "PageDown"][i]
		parts.append(_key(top, nav + i, 1.5, 1, ["Ins", "Home", "PgUp"][i]))
		parts.append(_key(low, nav + i, 2.5, 1, ["Del", "End", "PgDn"][i]))
	parts.append(_key("Up", nav + 1, 4.5))
	for i: int in 3:
		parts.append(_key(["Left", "Down", "Right"][i], nav + i, 5.5))
	# Numpad.
	var pad: float = 18.6
	for r: int in 3:
		for c: int in 3:
			var n: int = 7 - 3 * r + c
			parts.append(_key("Kp %d" % n, pad + c, 2.5 + r, 1, str(n)))
	parts.append(_key("Kp 0", pad, 5.5, 2, "0"))
	parts.append(_key("Kp Period", pad + 2, 5.5, 1, "."))
	parts.append(_key("", pad, 1.5, 1, "Num"))
	parts.append(_key("Kp Divide", pad + 1, 1.5, 1, "/"))
	parts.append(_key("Kp Multiply", pad + 2, 1.5, 1, "*"))
	parts.append(_key("Kp Subtract", pad + 3, 1.5, 1, "-"))
	parts.append(_tall("Kp Add", pad + 3, 2.5, "+"))
	parts.append(_tall("Kp Enter", pad + 3, 4.5, "Ent"))
	var kb_w: float = 22.6 * U
	var kb_h: float = 6.0 * U + 2.0
	var body: Array[Dictionary] = [
		{"shape": "round", "rect": Rect2(-10, -10, kb_w + 8, kb_h + 18)},
	]
	# The mouse, below the keyboard, centred on the zone.
	var mx: float = kb_w * 0.5 - 55.0
	var my: float = kb_h + 30.0 + dy
	body.append({"shape": "round", "rect": Rect2(mx, my, 110, 170), "radius": 48.0})
	parts.append(_part("LMB", Rect2(mx + 4, my + 4, 46, 76), "L", "round"))
	parts.append(_part("RMB", Rect2(mx + 60, my + 4, 46, 76), "R", "round"))
	parts.append(_part("WheelUp", Rect2(mx + 50, my + 10, 10, 16), BLANK, "round"))
	parts.append(_part("MMB", Rect2(mx + 50, my + 28, 10, 20), BLANK, "round"))
	parts.append(_part("WheelDown", Rect2(mx + 50, my + 50, 10, 16), BLANK, "round"))
	parts.append(_part("Mouse", Rect2(mx + 16, my + 92, 78, 66), BLANK, "round"))
	return {"parts": parts, "body": body, "size": Vector2(kb_w, my + 180.0)}


static func _letters(parts: Array[Dictionary], letters: String, c0: float, row: float) -> void:
	for i: int in letters.length():
		parts.append(_key(letters[i], c0 + i, row))


static func _pad() -> Dictionary:
	var cx: float = ZONE_W * 0.5 - 14.0
	var parts: Array[Dictionary] = []
	var body: Array[Dictionary] = [
		{"shape": "round", "rect": Rect2(cx - 215, 66, 430, 170), "radius": 70.0},
		{"shape": "circle", "rect": Rect2(cx - 245, 190, 120, 120)},
		{"shape": "circle", "rect": Rect2(cx + 125, 190, 120, 120)},
	]
	parts.append(_part("LT", Rect2(cx - 180, 4, 76, 32), "LT", "round"))
	parts.append(_part("LB", Rect2(cx - 195, 40, 100, 18), "LB", "round"))
	parts.append(_part("RT", Rect2(cx + 104, 4, 76, 32), "RT", "round"))
	parts.append(_part("RB", Rect2(cx + 95, 40, 100, 18), "RB", "round"))
	parts.append(_part("LS", _disc(Vector2(cx - 140, 120), 28), "LS", "circle"))
	parts.append(_part("RS", _disc(Vector2(cx + 60, 200), 28), "RS", "circle"))
	var dp: Vector2 = Vector2(cx - 60, 200)
	parts.append(_part("Up", Rect2(dp.x - 12, dp.y - 36, 24, 24), "^"))
	parts.append(_part("Down", Rect2(dp.x - 12, dp.y + 12, 24, 24), "v"))
	parts.append(_part("Left", Rect2(dp.x - 36, dp.y - 12, 24, 24), "<"))
	parts.append(_part("Right", Rect2(dp.x + 12, dp.y - 12, 24, 24), ">"))
	var fb: Vector2 = Vector2(cx + 140, 120)
	parts.append(_part("Y", _disc(fb + Vector2(0, -32), 15), "Y", "circle"))
	parts.append(_part("A", _disc(fb + Vector2(0, 32), 15), "A", "circle"))
	parts.append(_part("X", _disc(fb + Vector2(-32, 0), 15), "X", "circle"))
	parts.append(_part("B", _disc(fb + Vector2(32, 0), 15), "B", "circle"))
	parts.append(_part("View", _disc(Vector2(cx - 28, 112), 10), BLANK, "circle"))
	parts.append(_part("Menu", _disc(Vector2(cx + 28, 112), 10), BLANK, "circle"))
	return {"parts": parts, "body": body, "size": Vector2(ZONE_W, 310.0)}


static func _disc(c: Vector2, r: float) -> Rect2:
	return Rect2(c.x - r, c.y - r, 2.0 * r, 2.0 * r)
