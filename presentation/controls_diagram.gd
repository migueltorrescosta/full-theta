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

var model: ControlsModel = ControlsModel.new()

var _bindings: Bindings = null
var _stations: Array = []
var _device: String = IntentTable.KBM
var _labels: Array[Dictionary] = []
var _origin: Vector2 = Vector2.ZERO
var _height: float = 0.0
var _scale: float = 1.0
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


## Sizes the labels and puts them in the two columns.
func _layout() -> void:
	_labels.clear()
	var fig: Dictionary = ControlsFigure.get_figure(_device)
	var size: Vector2 = fig["size"]
	_origin = Vector2(ZONE_X + (ControlsFigure.ZONE_W - size.x) * 0.5, TOP + 14.0)
	var items: Array[Dictionary] = []
	for e: Dictionary in model.callouts():
		var label: Dictionary = e.duplicate()
		var mean: Vector2 = Vector2.ZERO
		for id: String in e["parts"]:
			mean += _rect_of(id).get_center() / float(e["parts"].size())
		label["mean"] = mean
		items.append(label)
	# The halves by key position: the same number of labels in each column.
	var xs: Array[float] = []
	for l: Dictionary in items:
		xs.append(l["mean"].x)
	xs.sort()
	var split: float = xs[xs.size() / 2] if not xs.is_empty() else 0.0
	var sides: Dictionary = {"left": [], "right": []}
	for l: Dictionary in items:
		var side: String = "left" if l["mean"].x < split else "right"
		l["side"] = side
		var anchors: Array[Vector2] = []
		for id: String in l["parts"]:
			var r: Rect2 = _rect_of(id)
			anchors.append(Vector2(r.position.x if side == "left" else r.end.x, r.get_center().y))
		l["anchors"] = anchors
		sides[side].append(l)
	var hardware_h: float = _origin.y + size.y
	var rows: int = maxi(sides["left"].size(), sides["right"].size())
	var bottom: float = maxf(hardware_h, TOP + rows * LINE_H)
	for side: String in sides:
		_place(sides[side], side, bottom)
	_height = bottom + 8.0 + LEGEND_H


func _place(list: Array, side: String, bottom: float) -> void:
	var sign_x: float = -1.0 if side == "left" else 1.0
	# Same row: the farther key gets the upper label, so leaders don't cross.
	list.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(a["mean"].y, b["mean"].y):
				return a["mean"].y < b["mean"].y
			return a["mean"].x * -sign_x < b["mean"].x * -sign_x
	)
	var ys: Array[float] = []
	var prev: float = TOP - LINE_H
	for l: Dictionary in list:
		prev = maxf(l["mean"].y - LINE_H * 0.5, prev + LINE_H)
		ys.append(prev)
	var limit: float = bottom
	for i: int in range(list.size() - 1, -1, -1):
		ys[i] = minf(ys[i], limit - LINE_H)
		limit = ys[i]
	var font: Font = get_theme_default_font()
	for i: int in list.size():
		var l: Dictionary = list[i]
		var keys_w: float = font.get_string_size(l["keys"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
		var name_text: String = l["label"]
		var room: float = COL_W - 8.0 - keys_w - 10.0
		while name_text.length() > 1 and _text_w(font, name_text) > room:
			name_text = name_text.left(name_text.length() - 2).strip_edges() + "…"
		var w: float = _text_w(font, name_text) + 10.0 + keys_w
		var x: float = COL_W - 4.0 - w if side == "left" else DESIGN_W - COL_W + 4.0
		l["name"] = name_text
		l["rect"] = Rect2(x, ys[i], w, LINE_H - 2.0)
		_labels.append(l)


## The drawn rect of part `id`, in design pixels.
func _rect_of(id: String) -> Rect2:
	var r: Rect2 = ControlsFigure.part(_device, id)["rect"]
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
	var fig: Dictionary = ControlsFigure.get_figure(_device)
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
	for l: Dictionary in _labels:
		var rect: Rect2 = l["rect"]
		var left: bool = l["side"] == "left"
		var y: float = rect.get_center().y
		var edge: float = rect.end.x + 4.0 if left else rect.position.x - 4.0
		var elbow: float = edge + (14.0 if left else -14.0)
		var col: Color = _line_color(l)
		for a: Vector2 in l["anchors"]:
			draw_polyline(
				PackedVector2Array([Vector2(edge, y), Vector2(elbow, y), a]), col, 1.4, true
			)
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
	for part: Dictionary in ControlsFigure.get_figure(_device)["parts"]:
		var r: Rect2 = Rect2(part["rect"].position + _origin, part["rect"].size)
		if part["id"] == "" or not r.has_point(p):
			continue
		var lines: PackedStringArray = []
		for e: Dictionary in model.on_part(part["id"]):
			lines.append("%s: %s" % [e["label"], e["keys"]])
		return "\n".join(lines)
	return ""
