class_name ControlsDiagram
extends Control
## The controls as a picture (FT-STN-011, D185): one keyboard-and-mouse or controller
## diagram with every binding of the game on it. The keys of the screen's stations are
## filled in their station colour and named in callouts ("Surge S / W"), the common
## actions and the always-live set are outlined and named, every other station's keys
## carry only small station-coloured ticks (hover for the names). Labels come from
## Bindings through ControlsModel, so a rebind redraws at once; the text list stays the
## fallback (ControlsPane). Drawn in code in design pixels (DESIGN_W wide) and scaled to
## the width it gets; the height follows.

## The design width: two label columns around the hardware zone.
const DESIGN_W: float = 1412.0
const COL_W: float = 340.0
const ZONE_X: float = 356.0
const TOP: float = 6.0
const LINE_H: float = 17.0
const FONT: int = 14
const CAPTION: int = 11
const LEGEND_H: float = 26.0
const MIN_SCALE: float = 0.25
const MAX_SCALE: float = 1.25
## Where the keyboard's left half ends (figure pixels), and the mouse's parts.
const HALF_X: float = 206.0
const MOUSE_IDS: Array[String] = ["LMB", "RMB", "WheelUp", "MMB", "WheelDown", "Mouse"]
const ZONE_TOP: String = "top"
const ZONE_LEFT: String = "left"
const ZONE_RIGHT: String = "right"
const ZONE_NUMPAD: String = "numpad"
const ZONE_MOUSE: String = "mouse"

var model: ControlsModel = ControlsModel.new()

var _bindings: Bindings = null
var _stations: Array = []
var _device: String = IntentTable.KBM
var _labels: Array[Dictionary] = []
var _leaders: Array[Dictionary] = []
var _origin: Vector2 = Vector2.ZERO
var _height: float = 0.0
var _scale: float = 1.0
## How far the mouse sits below its default place (the right half's labels go between).
var _dy: float = 0.0
var _box: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true


## Shows `device` ("kbm" or "pad") for `stations`; follows later rebinds.
func build(bindings: Bindings, stations: Array, device: String) -> void:
	if _bindings != null and _bindings.changed.is_connected(_rebuild):
		_bindings.changed.disconnect(_rebuild)
	_bindings = bindings
	_stations = stations
	_device = device
	_bindings.changed.connect(_rebuild)
	_rebuild()


## The callout labels, in design pixels: [{"rect", "name", "keys", "id", "binding",
## "anchors", "side", "emphasis", "group"}]; tests check they don't overlap or leave
## [0, DESIGN_W] x [0, design_height()].
func labels() -> Array[Dictionary]:
	return _labels


## The leader lines, in design pixels: [{"id", "points"}], one polyline per key a label
## points at; tests check that none of two labels crosses another.
func leaders() -> Array[Dictionary]:
	return _leaders


## The whole drawing's height in design pixels.
func design_height() -> float:
	return _height


## How `id` is shown: "station", "common" or "other" by the strongest entry on it, ""
## when no binding lands there.
func part_emphasis(id: String) -> String:
	var best: String = ""
	for e: Dictionary in model.on_part(id):
		if e["emphasis"] == ControlsModel.STATION:
			return ControlsModel.STATION
		if e["emphasis"] == ControlsModel.COMMON or best == "":
			best = e["emphasis"]
	return best


## The colour of a station's group.
static func group_color(group: String) -> Color:
	if Palette.ROLES.has("st_" + group):
		return Palette.color("st_" + group)
	return Palette.color("text")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _bindings != null:
		_rebuild()
	elif what == NOTIFICATION_RESIZED:
		_fit()


func _rebuild() -> void:
	model.build(_bindings, _stations, _device)
	_layout()
	_fit()
	queue_redraw()


## Sizes the labels and puts each in its zone, ordered by its key's position so the
## leader lines don't cross: the function row labels upwards, the left half of the
## keyboard to the left column, the right half below the keyboard beside the mouse, the
## numpad to its own column, the mouse buttons beside the mouse. The controller splits
## into a left and a right column by key position.
func _layout() -> void:
	_labels.clear()
	_leaders.clear()
	var fig: Dictionary = ControlsFigure.get_figure(_device, _dy)
	var size: Vector2 = fig["size"]
	var zones: Dictionary = {}
	var items: Array[Dictionary] = []
	for e: Dictionary in model.callouts():
		items.append_array(_per_key(e))
	_split_into_zones(items, zones)
	var tiers: int = zones.get(ZONE_TOP, []).size()
	_dy = maxf(0.0, zones.get(ZONE_RIGHT, []).size() * LINE_H - 20.0)
	fig = ControlsFigure.get_figure(_device, _dy)
	size = fig["size"]
	_origin = Vector2(ZONE_X + (ControlsFigure.ZONE_W - size.x) * 0.5, TOP + tiers * LINE_H + 14.0)
	for l: Dictionary in items:
		var mean: Vector2 = Vector2.ZERO
		for id: String in l["parts"]:
			mean += _rect_of(id).get_center() / float(l["parts"].size())
		l["mean"] = mean
	var hardware_h: float = _origin.y + size.y
	var bottom: float = hardware_h
	for zone: String in [ZONE_LEFT, ZONE_NUMPAD]:
		bottom = maxf(bottom, TOP + zones.get(zone, []).size() * LINE_H)
	var spec: Dictionary = _zone_specs()
	for zone: String in [ZONE_TOP, ZONE_LEFT, ZONE_RIGHT, ZONE_NUMPAD, ZONE_MOUSE]:
		if not zones.has(zone):
			continue
		var list: Array = zones[zone]
		for l: Dictionary in list:
			l["side"] = _side_of(zone)
		if zone == ZONE_TOP:
			_place_vertical(list, true, 0.0)
		elif zone == ZONE_RIGHT:
			_place_vertical(list, false, float(spec[ZONE_RIGHT]["y0"]))
		else:
			bottom = maxf(bottom, _place(list, spec[zone], bottom))
	_height = bottom + 8.0 + LEGEND_H


## An entry whose keys are alternatives ("S / W") becomes one callout per key, so every
## leader ends on a single key and none has to hop between keys.
func _per_key(e: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys: PackedStringArray = str(e["keys"]).split(" / ")
	if e["parts"].size() < 2 or keys.size() != e["parts"].size():
		out.append(e.duplicate())
		return out
	for i: int in keys.size():
		var one: Dictionary = e.duplicate()
		one["keys"] = keys[i]
		one["parts"] = [e["parts"][i]]
		out.append(one)
	return out


func _side_of(zone: String) -> String:
	return "left" if zone in [ZONE_LEFT, ZONE_MOUSE] else ("top" if zone == ZONE_TOP else "right")


## Puts every label in `zones` ({zone: Array of labels}) by where its parts sit.
func _split_into_zones(items: Array[Dictionary], zones: Dictionary) -> void:
	if _device == IntentTable.PAD:
		var xs: Array[float] = []
		for l: Dictionary in items:
			xs.append(_mean_rect(l).get_center().x)
		xs.sort()
		var split: float = xs[xs.size() / 2] if not xs.is_empty() else 0.0
		for l: Dictionary in items:
			var zone: String = ZONE_LEFT if _mean_rect(l).get_center().x < split else ZONE_NUMPAD
			(zones.get_or_add(zone, []) as Array).append(l)
		return
	for l: Dictionary in items:
		(zones.get_or_add(_zone_of(l), []) as Array).append(l)
	# Function row: leftmost label on the highest tier, so the vertical leaders stay clear.
	if zones.has(ZONE_TOP):
		(zones[ZONE_TOP] as Array).sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return _mean_rect(a).get_center().x < _mean_rect(b).get_center().x
		)


func _mean_rect(l: Dictionary) -> Rect2:
	var c: Vector2 = Vector2.ZERO
	for id: String in l["parts"]:
		c += ControlsFigure.part(_device, id, _dy)["rect"].get_center() / float(l["parts"].size())
	return Rect2(c, Vector2.ZERO)


func _zone_of(l: Dictionary) -> String:
	var top: bool = true
	var numpad: bool = true
	var mouse: bool = true
	for id: String in l["parts"]:
		top = top and ControlsFigure.part(_device, id, _dy)["rect"].position.y < 1.0
		numpad = numpad and id.begins_with("Kp ")
		mouse = mouse and MOUSE_IDS.has(id)
	if top:
		return ZONE_TOP
	if numpad:
		return ZONE_NUMPAD
	if mouse:
		return ZONE_MOUSE
	return ZONE_LEFT if _mean_rect(l).get_center().x < HALF_X else ZONE_RIGHT


## Where each zone's labels sit: the text edge nearest the hardware, which way the text
## runs from it, the room, which edge of a key the leader ends on, and (for the zones with
## a fixed run of rows) where they start.
func _zone_specs() -> Dictionary:
	var size: Vector2 = ControlsFigure.get_figure(_device, _dy)["size"]
	var kb_bottom: float = _origin.y + size.y
	var mouse_right: float = _origin.x
	var mouse_top: float = _origin.y
	if _device == IntentTable.KBM:
		var lmb: Rect2 = _rect_of("LMB")
		var rmb: Rect2 = _rect_of("RMB")
		mouse_right = rmb.end.x + 4.0
		mouse_top = lmb.position.y - 4.0
		kb_bottom = _rect_of("Escape").position.y + 6.0 * ControlsFigure.U + 14.0
	return {
		ZONE_LEFT: {"edge": COL_W - 4.0, "dir": -1.0, "room": COL_W - 8.0, "anchor": "left"},
		ZONE_NUMPAD:
		{"edge": DESIGN_W - COL_W + 4.0, "dir": 1.0, "room": COL_W - 8.0, "anchor": "right"},
		ZONE_RIGHT: {"y0": kb_bottom},
		ZONE_MOUSE:
		{
			"edge": mouse_right + 24.0,
			"dir": 1.0,
			"room": DESIGN_W - 8.0 - mouse_right - 24.0,
			"anchor": "centre",
			"y0": mouse_top + 6.0
		},
	}


## Sizes `l` for `room` and sets its "name", the text that fits, and "w".
func _fit_label(l: Dictionary, room: float) -> void:
	var font: Font = get_theme_default_font()
	var keys_w: float = font.get_string_size(l["keys"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	var name_text: String = l["label"]
	var avail: float = room - keys_w - 10.0
	while name_text.length() > 1 and _text_w(font, name_text) > avail:
		name_text = name_text.left(name_text.length() - 2).strip_edges() + "…"
	l["name"] = name_text
	l["w"] = _text_w(font, name_text) + 10.0 + keys_w


func _anchor_of(id: String, kind: String) -> Vector2:
	var r: Rect2 = _rect_of(id)
	match kind:
		"left":
			return Vector2(r.position.x, r.get_center().y)
		"right":
			return Vector2(r.end.x, r.get_center().y)
		"bottom":
			return Vector2(r.get_center().x, r.end.y)
		"top":
			return Vector2(r.get_center().x, r.position.y)
	return r.get_center()


## Places a column of labels: `spec` as in _zone_specs. Rows follow the keys' vertical
## order (the zones with a "y0" run down from it in that order); then labels whose
## leaders would cross trade rows until none do. Returns the bottom of the column.
func _place(list: Array, spec: Dictionary, bottom: float) -> float:
	if list.is_empty():
		return 0.0
	var dir: float = spec["dir"]
	var kind: String = spec["anchor"]
	for l: Dictionary in list:
		var anchors: Array[Vector2] = []
		for id: String in l["parts"]:
			anchors.append(_anchor_of(id, kind))
		# One leader to the key nearest the column, then short hops to the label's others.
		var near_x: float = float(spec["edge"]) - dir * 18.0
		anchors.sort_custom(
			func(a: Vector2, b: Vector2) -> bool: return absf(a.x - near_x) < absf(b.x - near_x)
		)
		var chain: Array[Vector2] = [anchors[0]]
		var rest: Array[Vector2] = anchors.slice(1)
		while not rest.is_empty():
			rest.sort_custom(
				func(a: Vector2, b: Vector2) -> bool:
					return a.distance_to(chain[-1]) < b.distance_to(chain[-1])
			)
			chain.append(rest.pop_front())
		l["anchors"] = chain
		l["lead"] = [chain[0]]
		_fit_label(l, spec["room"])
	# Order by the key's row, then the farther key first so the leaders fan out.
	list.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(a["mean"].y, b["mean"].y):
				return a["mean"].y < b["mean"].y
			if kind == "bottom" or kind == "centre":
				return a["mean"].x < b["mean"].x
			return a["mean"].x * dir > b["mean"].x * dir
	)
	var ys: Array[float] = []
	if spec.has("y0"):
		for i: int in list.size():
			ys.append(float(spec["y0"]) + i * LINE_H)
	else:
		var prev: float = TOP - LINE_H
		for l: Dictionary in list:
			prev = maxf(l["mean"].y - LINE_H * 0.5, prev + LINE_H)
			ys.append(prev)
		var limit: float = bottom
		for i: int in range(list.size() - 1, -1, -1):
			ys[i] = minf(ys[i], limit - LINE_H)
			limit = ys[i]
	var elbow_x: float = spec["edge"] - dir * 18.0
	_uncross(list, ys, elbow_x)
	for i: int in list.size():
		var l: Dictionary = list[i]
		var x: float = spec["edge"] if dir > 0.0 else spec["edge"] - l["w"]
		l["rect"] = Rect2(x, ys[i], l["w"], LINE_H - 2.0)
		_labels.append(l)
		var y: float = ys[i] + (LINE_H - 2.0) * 0.5
		var chain: Array = l["anchors"]
		_add_leader(
			l,
			PackedVector2Array(
				[Vector2(spec["edge"] - dir * 4.0, y), Vector2(elbow_x, y), chain[0]]
			)
		)
		for k: int in range(1, chain.size()):
			_add_leader(l, PackedVector2Array([chain[k - 1], chain[k]]))
	return ys[ys.size() - 1] + LINE_H


## Orders the rows so few leaders cross, then trades rows while that lowers the number of
## crossings (labels with several keys can't always be uncrossed by pairs, then their
## total length); `ys` are the rows' tops, `elbow_x` where the leaders bend.
func _uncross(list: Array, ys: Array[float], elbow_x: float) -> void:
	# First trade the rows of any two labels whose leaders cross: for one key each that
	# shortens the total length, so it ends with none crossing.
	var swapped: bool = true
	var rounds: int = 0
	while swapped and rounds < 300:
		swapped = false
		rounds += 1
		for i: int in list.size():
			for j: int in range(i + 1, list.size()):
				if _labels_cross(list[i], ys[i], list[j], ys[j], elbow_x):
					var t: Variant = list[i]
					list[i] = list[j]
					list[j] = t
					swapped = true
	var best: float = _cost(list, ys, elbow_x)
	var improved: bool = true
	var guard: int = 0
	while improved and guard < 60:
		improved = false
		guard += 1
		for i: int in list.size():
			for j: int in range(i + 1, list.size()):
				var tmp: Variant = list[i]
				list[i] = list[j]
				list[j] = tmp
				var c: float = _cost(list, ys, elbow_x)
				if c < best - 0.001:
					best = c
					improved = true
				else:
					list[j] = list[i]
					list[i] = tmp


## A million per pair of crossing leaders, plus the leaders' total length.
func _labels_cross(a: Dictionary, ya: float, b: Dictionary, yb: float, elbow_x: float) -> bool:
	var ea: Vector2 = Vector2(elbow_x, ya + (LINE_H - 2.0) * 0.5)
	var eb: Vector2 = Vector2(elbow_x, yb + (LINE_H - 2.0) * 0.5)
	for p: Vector2 in a["lead"]:
		for q: Vector2 in b["lead"]:
			if segments_cross(ea, p, eb, q):
				return true
	return false


func _cost(list: Array, ys: Array[float], elbow_x: float) -> float:
	var segs: Array = []
	var length: float = 0.0
	for i: int in list.size():
		var e: Vector2 = Vector2(elbow_x, ys[i] + (LINE_H - 2.0) * 0.5)
		for a: Vector2 in list[i]["lead"]:
			segs.append([i, e, a])
			length += e.distance_to(a)
		var chain: Array = list[i]["anchors"]
		for k: int in range(1, chain.size()):
			segs.append([i, chain[k - 1], chain[k]])
	var crossings: int = 0
	for i: int in segs.size():
		for j: int in range(i + 1, segs.size()):
			if (
				segs[i][0] != segs[j][0]
				and segments_cross(segs[i][1], segs[i][2], segs[j][1], segs[j][2])
			):
				crossings += 1
	return crossings * 1000000.0 + length


## True when segments a1-a2 and b1-b2 cross at a point inside both.
static func segments_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1: float = (a2 - a1).cross(b1 - a1)
	var d2: float = (a2 - a1).cross(b2 - a1)
	var d3: float = (b2 - b1).cross(a1 - b1)
	var d4: float = (b2 - b1).cross(a2 - b1)
	return d1 * d2 < -0.0001 and d3 * d4 < -0.0001


## Labels on tiers above (the function row) or below (the right half) the keyboard, each
## leader straight to its key. The leftmost key's label is farthest from the keyboard, so
## a label's text never lies across the leader of the key to its right; `y0` is where the
## tiers below start.
func _place_vertical(list: Array, above: bool, y0: float) -> void:
	for l: Dictionary in list:
		var anchors: Array[Vector2] = []
		for id: String in l["parts"]:
			anchors.append(_anchor_of(id, "top" if above else "bottom"))
		l["anchors"] = anchors
	list.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _min_x(a["anchors"]) < _min_x(b["anchors"])
	)
	# Keys closer than a leader's width in x get their lines apart.
	var last_x: float = -INF
	for l: Dictionary in list:
		for i: int in l["anchors"].size():
			var a: Vector2 = l["anchors"][i]
			if a.x < last_x + 6.0:
				a.x = last_x + 6.0
				l["anchors"][i] = a
			last_x = a.x
	for t: int in list.size():
		var l: Dictionary = list[t]
		var left: float = _min_x(l["anchors"])
		_fit_label(l, DESIGN_W - 8.0 - left)
		var tier: int = t if above else list.size() - 1 - t
		var y: float = (TOP if above else y0) + tier * LINE_H
		var rect: Rect2 = Rect2(left + 6.0, y, l["w"], LINE_H - 2.0)
		l["rect"] = rect
		_labels.append(l)
		for a: Vector2 in l["anchors"]:
			var from_y: float = rect.get_center().y
			if a.x >= rect.position.x:
				from_y = rect.end.y + 1.0 if above else rect.position.y - 1.0
			_add_leader(l, PackedVector2Array([Vector2(a.x, from_y), a]))


func _min_x(points: Array) -> float:
	var m: float = INF
	for p: Vector2 in points:
		m = minf(m, p.x)
	return m


func _add_leader(l: Dictionary, points: PackedVector2Array) -> void:
	_leaders.append({"id": l["id"], "points": points})


## The drawn rect of part `id`, in design pixels.
func _rect_of(id: String) -> Rect2:
	var r: Rect2 = ControlsFigure.part(_device, id, _dy)["rect"]
	return Rect2(r.position + _origin, r.size)


static func _text_w(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x


## The minimum height for the width: the drawing scales to fit and keeps its shape.
func _fit() -> void:
	_scale = clampf(size.x / DESIGN_W, MIN_SCALE, MAX_SCALE)
	var want: float = ceilf(_height * _scale)
	if not is_equal_approx(custom_minimum_size.y, want):
		custom_minimum_size = Vector2(0.0, want)
	queue_redraw()


func _draw() -> void:
	if _bindings == null:
		return
	var ox: float = maxf(0.0, (size.x - DESIGN_W * _scale) * 0.5)
	draw_set_transform(Vector2(ox, 0.0), 0.0, Vector2(_scale, _scale))
	var fig: Dictionary = ControlsFigure.get_figure(_device, _dy)
	for pass_index: int in 2:
		for b: Dictionary in fig["body"]:
			var r: Rect2 = Rect2(b["rect"].position + _origin, b["rect"].size)
			var edge: bool = pass_index == 0
			_shape(
				b["shape"],
				r.grow(3.0) if edge else r,
				Palette.color("hardware_edge" if edge else "hardware"),
				b.get("radius", 14.0) + (3.0 if edge else 0.0)
			)
	for p: Dictionary in fig["parts"]:
		_draw_part(p)
	_draw_leaders()
	_draw_labels()
	_draw_legend()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _shape(shape: String, r: Rect2, col: Color, radius: float = 5.0) -> void:
	if shape == "circle":
		draw_circle(r.get_center(), minf(r.size.x, r.size.y) * 0.5, col)
		return
	_box.bg_color = col
	_box.set_corner_radius_all(roundi(minf(radius, minf(r.size.x, r.size.y) * 0.5)))
	draw_style_box(_box, r)


func _draw_part(p: Dictionary) -> void:
	var r: Rect2 = Rect2(p["rect"].position + _origin, p["rect"].size)
	var id: String = p["id"]
	var entries: Array[Dictionary] = []
	if id != "":
		entries = model.on_part(id)
	var emphasis: String = part_emphasis(id) if id != "" else ""
	var fill: Color = Palette.color("key")
	var text: Color = Palette.color("text_dim")
	var primary: String = ""
	if emphasis == ControlsModel.STATION:
		for e: Dictionary in entries:
			if e["emphasis"] == ControlsModel.STATION:
				primary = e["group"]
				break
		fill = group_color(primary)
		text = Palette.color("background")
	elif emphasis == ControlsModel.COMMON:
		text = Palette.color("text")
	if emphasis == "":
		fill.a = 0.6
	if emphasis == ControlsModel.COMMON or _has(entries, ControlsModel.COMMON):
		_shape(p["shape"], r.grow(1.5), Palette.color("text"), 6.0)
	_shape(p["shape"], r, fill, 5.0)
	var caption: String = p["caption"]
	var font: Font = get_theme_default_font()
	var w: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION).x
	if caption != "":
		draw_string(
			font,
			r.get_center() + Vector2(-w * 0.5, CAPTION * 0.36),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			CAPTION,
			text
		)
	# Ticks: the other stations' colours on the key's lower edge.
	var seen: Array[String] = [primary]
	var x: float = r.position.x + 2.0
	for e: Dictionary in entries:
		var g: String = e["group"]
		if g in seen or g in [IntentTable.COMMON, IntentTable.LIVE]:
			continue
		seen.append(g)
		var c: Color = group_color(g)
		c.a = 0.95 if e["emphasis"] == ControlsModel.STATION else 0.6
		draw_rect(Rect2(x, r.end.y - 4.0, 6.0, 3.0), c)
		x += 8.0


static func _has(entries: Array[Dictionary], emphasis: String) -> bool:
	return entries.any(func(e: Dictionary) -> bool: return e["emphasis"] == emphasis)


func _draw_leaders() -> void:
	var by_id: Dictionary = {}
	for l: Dictionary in _labels:
		by_id[l["id"]] = l
	for ld: Dictionary in _leaders:
		var col: Color = _line_color(by_id[ld["id"]])
		var pts: PackedVector2Array = ld["points"]
		draw_polyline(pts, col, 1.4, true)
		var a: Vector2 = pts[pts.size() - 1]
		draw_circle(a, 3.4, Palette.color("background"))
		draw_circle(a, 2.2, col.lightened(0.2))


func _line_color(l: Dictionary) -> Color:
	var col: Color = (
		group_color(l["group"])
		if l["emphasis"] == ControlsModel.STATION
		else Palette.color("text_dim")
	)
	col.a = 0.9
	return col


func _draw_labels() -> void:
	var font: Font = get_theme_default_font()
	for l: Dictionary in _labels:
		var rect: Rect2 = l["rect"]
		var base: Vector2 = Vector2(rect.position.x, rect.end.y - 4.0)
		var station: bool = l["emphasis"] == ControlsModel.STATION
		var name_col: Color = group_color(l["group"]) if station else Palette.color("text_dim")
		draw_string(font, base, l["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, name_col)
		var kx: float = base.x + _text_w(font, l["name"]) + 10.0
		draw_string(
			font,
			Vector2(kx, base.y),
			l["keys"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT,
			Palette.color("text")
		)


func _draw_legend() -> void:
	var font: Font = get_theme_default_font()
	var y: float = _height - LEGEND_H + 4.0
	var x: float = 0.0
	var chips: Array[Dictionary] = []
	for s: Variant in _stations:
		chips.append(
			{
				"text": tr("station." + str(s)),
				"col": group_color(str(s)),
				"ring": false,
				"tick": false
			}
		)
	chips.append(
		{"text": tr("overlay.common"), "col": Palette.color("key"), "ring": true, "tick": false}
	)
	chips.append(
		{"text": tr("controls.other"), "col": Palette.color("key"), "ring": false, "tick": true}
	)
	for c: Dictionary in chips:
		if c["ring"]:
			draw_rect(Rect2(x - 1.5, y - 1.5, 17.0, 17.0), Palette.color("text"))
		draw_rect(Rect2(x, y, 14.0, 14.0), c["col"])
		if c["tick"]:
			draw_rect(Rect2(x + 1.0, y + 10.0, 5.0, 3.0), group_color("weapons"))
		draw_string(
			font,
			Vector2(x + 22.0, y + 12.0),
			c["text"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT,
			Palette.color("text_dim")
		)
		x += 40.0 + _text_w(font, c["text"])


func _get_tooltip(at_position: Vector2) -> String:
	var ox: float = maxf(0.0, (size.x - DESIGN_W * _scale) * 0.5)
	var p: Vector2 = Vector2((at_position.x - ox) / _scale, at_position.y / _scale)
	for part: Dictionary in ControlsFigure.get_figure(_device, _dy)["parts"]:
		var r: Rect2 = Rect2(part["rect"].position + _origin, part["rect"].size)
		if part["id"] == "" or not r.has_point(p):
			continue
		var lines: PackedStringArray = []
		for e: Dictionary in model.on_part(part["id"]):
			lines.append("%s: %s" % [e["label"], e["keys"]])
		return "\n".join(lines)
	return ""
