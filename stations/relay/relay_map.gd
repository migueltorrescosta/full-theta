class_name RelayMap
extends Control
## Relay's map read-out (§5.5, FT-RLY-001, FT-SPA-006, D124): a freely rotatable 3D view
## of the site, centred on the own ship or a selected item, drawn in 2D with an
## orthographic camera. Everything is in the ship frame (-Z bow, +X starboard, +Y up),
## so stems drop to the ship's deck plane through the map centre and chips read like
## every other station; the camera turns freely about its own axes, so the map has no
## world-fixed up, no grid squares and no layers. The site's wrapping cube is drawn
## honestly as faint edges: one period P on a side around the own ship, the region the
## minimum image places every item in (D124).
##
## The panel (RelayPanel) owns input; this control only draws and maps between screen
## points and ship-frame offsets: project() and unproject() at a depth along the view
## direction (0 = the plane through the map centre perpendicular to the view, FT-RLY-002).

const FONT_SIZE: int = 13
const BLIP_R: float = 6.0
## item_at picks the nearest item within this distance (px).
const HIT_PX: float = 12.0
## Half the map's smaller side in metres: zoom limits and step.
const SPAN_MIN_M: float = 500.0
const SPAN_DEFAULT_M: float = 10000.0
const ZOOM_STEP: float = 1.25
const ROTATE_RAD_PER_PX: float = 0.01
## The camera starts 35° above the deck plane behind the ship (a start, not an up).
const START_TILT_DEG: float = 35.0

## ContactPicture.build items (ship frame from the own ship).
var items: Array[Dictionary] = []
var selected: Dictionary = {}
## The item the map is centred on ({} = own ship).
var centre: Dictionary = {}
## Site period (m); 0 draws no cube.
var period_m: float = 0.0
## Own ship orientation and site-local position, to place the cube and to turn map
## points into site positions.
var own_rot: Quaternion = Quaternion.IDENTITY
var own_pos: Vector3 = Vector3.ZERO
## Camera orientation in the ship frame: it looks along -view.z, screen right is
## view.x and screen up view.y.
var view: Basis = Basis.from_euler(Vector3(deg_to_rad(-START_TILT_DEG), 0.0, 0.0))
var span_m: float = SPAN_DEFAULT_M
## Chips next to items (off in the docked view).
var chips: bool = true
## The point being placed or moved: {"rel" (ship frame from the centre), "plane" (the
## same at depth 0)}, or {}.
var preview: Dictionary = {}
## The controller cursor (px), drawn when cursor_on.
var cursor: Vector2 = Vector2.ZERO
var cursor_on: bool = false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true


## Pixels per metre.
func ppm() -> float:
	return minf(size.x, size.y) / 2.0 / span_m


## Zoom in (-1) or out (+1) one step.
func zoom(step: int) -> void:
	var top: float = period_m if period_m > 0.0 else 1.0e6
	span_m = clampf(span_m * pow(ZOOM_STEP, step), SPAN_MIN_M, top)
	queue_redraw()


## Turns the camera about its own up and right axes (right-drag, right stick).
func rotate_by(delta_px: Vector2) -> void:
	var yaw: Basis = Basis(view.y.normalized(), -delta_px.x * ROTATE_RAD_PER_PX)
	var pitch: Basis = Basis(view.x.normalized(), -delta_px.y * ROTATE_RAD_PER_PX)
	view = (yaw * pitch * view).orthonormalized()
	queue_redraw()


## Ship-frame offset of the centre item from the own ship (ZERO on the ship).
func centre_local() -> Vector3:
	if centre.is_empty():
		return Vector3.ZERO
	for it: Dictionary in items:
		if _ref(it) == _ref(centre):
			return it["local"]
	return Vector3.ZERO


## Screen position (px) of a ship-frame offset from the map centre.
func project(rel: Vector3) -> Vector2:
	var p: Vector3 = view.transposed() * rel
	return size / 2.0 + Vector2(p.x, -p.y) * ppm()


## Ship-frame offset from the map centre of a screen point at `depth` metres along the
## view direction (positive toward the camera; 0 is the plane through the centre).
func unproject(pos: Vector2, depth: float = 0.0) -> Vector3:
	var d: Vector2 = (pos - size / 2.0) / ppm()
	return view * Vector3(d.x, -d.y, depth)


## A ship-frame offset from the map centre as a site-local position (m; the server wraps).
func site_position(rel: Vector3) -> Vector3:
	return own_pos + own_rot * (rel + centre_local())


## The item drawn under `pos` ({"kind", "id"}), or {}: the selected item first, then the
## nearest within HIT_PX, then a chip. Point pings are never picked.
func item_at(pos: Vector2) -> Dictionary:
	var layout: Array[Dictionary] = _layout()
	var best: Dictionary = {}
	var best_d: float = HIT_PX
	for e: Dictionary in layout:
		var d: float = (e["pos"] as Vector2).distance_to(pos)
		if _is_selected(e["item"]) and d <= HIT_PX:
			return _ref(e["item"])
		if d <= best_d:
			best_d = d
			best = e["item"]
	if not best.is_empty():
		return _ref(best)
	for e: Dictionary in layout:
		if (e["chip_rect"] as Rect2).has_point(pos):
			return _ref(e["item"])
	return {}


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background"))
	var c: Vector3 = centre_local()
	_draw_cube(c)
	_draw_deck(c)
	var layout: Array[Dictionary] = _layout()
	var sel: Dictionary = {}
	for e: Dictionary in layout:
		if _is_selected(e["item"]):
			sel = e
		else:
			_draw_item(e, false)
	_draw_own(-c)
	if not sel.is_empty():
		_draw_item(sel, true)
	for e: Dictionary in layout:
		if e["chip"] != "":
			var col: Color = Palette.color("selected") if e == sel else _item_color(e["item"])
			_draw_text(font, e["chip_rect"].position, e["chip"], col)
	for it: Dictionary in items:
		if it["kind"] == "point":
			_draw_pulse(project(it["local"] - c), float(it.get("pulse", 0.0)))
	_draw_preview(font, c)
	if cursor_on:
		var col: Color = Palette.color("accent")
		draw_line(cursor - Vector2(10, 0), cursor + Vector2(10, 0), col, 1.5)
		draw_line(cursor - Vector2(0, 10), cursor + Vector2(0, 10), col, 1.5)
	var scale_text: String = tr("relay.span") % _km(span_m)
	_draw_text(font, Vector2(8.0, size.y - 8.0 - font.get_height(FONT_SIZE)), scale_text, _dim())


## The wrapping cube: one period on a side, world-axis aligned, around the own ship.
func _draw_cube(c: Vector3) -> void:
	if period_m <= 0.0:
		return
	var h: float = period_m / 2.0
	var inv: Quaternion = own_rot.inverse()
	var corner: Callable = func(i: int) -> Vector2:
		var w: Vector3 = Vector3(h if i & 1 else -h, h if i & 2 else -h, h if i & 4 else -h)
		return project(inv * w - c)
	var col: Color = Palette.color("line") * Color(1, 1, 1, 0.5)
	for i: int in 8:
		for bit: int in [1, 2, 4]:
			if not i & bit:
				draw_line(corner.call(i), corner.call(i | bit), col, 1.0, true)


## A faint ring in the deck plane through the centre (ship axes) with a bow tick, so
## stems have something to land on; not a grid.
func _draw_deck(c: Vector3) -> void:
	var r: float = span_m * 0.6
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 65:
		var a: float = TAU * float(i % 64) / 64.0
		pts.append(project(Vector3(cos(a) * r, 0.0, sin(a) * r)))
	draw_polyline(pts, Palette.color("line"), 1.0, true)
	draw_line(project(Vector3(0, 0, -r * 0.9)), project(Vector3(0, 0, -r)), _dim(), 1.5, true)
	if c != Vector3.ZERO:
		draw_line(
			project(Vector3.ZERO) - Vector2(4, 0), project(Vector3.ZERO) + Vector2(4, 0), _dim()
		)


func _draw_own(rel: Vector3) -> void:
	var col: Color = Palette.color("own")
	var p: Vector2 = project(rel)
	draw_line(project(Vector3(rel.x, 0.0, rel.z)), p, col * Color(1, 1, 1, 0.6), 1.0, true)
	var bow: Vector2 = project(rel + Vector3(0.0, 0.0, -span_m * 0.08)) - p
	var d: Vector2 = bow.normalized() if bow.length() > 1.0 else Vector2.UP
	var n: Vector2 = Vector2(-d.y, d.x)
	draw_colored_polygon(
		PackedVector2Array(
			[p + d * 9.0, p - d * 5.0 + n * 6.0, p - d * 2.0, p - d * 5.0 - n * 6.0]
		),
		col
	)


func _draw_item(e: Dictionary, is_sel: bool) -> void:
	var it: Dictionary = e["item"]
	var col: Color = _item_color(it)
	var pos: Vector2 = e["pos"]
	var foot: Vector2 = e["foot"]
	var stem: Color = Palette.color("selected") if is_sel else col * Color(1, 1, 1, 0.7)
	draw_line(foot, pos, stem, 2.0 if is_sel else 1.0, true)
	draw_line(foot - Vector2(3, 0), foot + Vector2(3, 0), stem, 1.0, true)
	var shape: String = "diamond" if it["kind"] == "mark" else _shape(it)
	var pts: PackedVector2Array = Palette.shape_points(shape, pos, BLIP_R)
	if (e["rel"] as Vector3).y >= 0.0:
		draw_colored_polygon(pts.slice(0, -1), col)
	else:
		draw_colored_polygon(pts.slice(0, -1), Palette.color("background"))
		draw_polyline(pts, col, 1.5, true)
	if is_sel:
		draw_rect(
			Rect2(pos - Vector2(9, 9), Vector2(18, 18)), Palette.color("selected"), false, 1.5
		)
	_draw_pulse(pos, float(it.get("pulse", 0.0)))


func _draw_pulse(pos: Vector2, pulse: float) -> void:
	if pulse <= 0.0:
		return
	var col: Color = Palette.color("ping")
	col.a = pulse
	draw_arc(pos, BLIP_R + 4.0 + (1.0 - pulse) * 22.0, 0.0, TAU, 32, col, 2.0, true)


## The mark being placed: an outline diamond, its stem, a line back to the view plane
## when Shift+drag moved it in depth, and its chip from the own ship.
func _draw_preview(font: Font, c: Vector3) -> void:
	if preview.is_empty():
		return
	var rel: Vector3 = preview["rel"]
	var p: Vector2 = project(rel)
	var col: Color = Palette.color("mark")
	draw_line(project(Vector3(rel.x, 0.0, rel.z)), p, col * Color(1, 1, 1, 0.7), 1.0, true)
	draw_line(project(preview["plane"]), p, col * Color(1, 1, 1, 0.4), 1.0, true)
	draw_polyline(Palette.shape_points("diamond", p, BLIP_R + 2.0), col, 2.0, true)
	var label: String = str(preview.get("label", ""))
	_draw_text(font, p + Vector2(12.0, -8.0), ChipText.chip(label, rel + c), col)


func _draw_text(font: Font, at: Vector2, text: String, col: Color) -> void:
	var base: Vector2 = at + Vector2(0.0, font.get_ascent(FONT_SIZE))
	var bg: Color = Palette.color("background")
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, bg)
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


## Per item (point pings left out): {"item", "rel", "pos", "foot", "chip", "chip_rect"}.
func _layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var font: Font = get_theme_default_font()
	var c: Vector3 = centre_local()
	for it: Dictionary in items:
		if it["kind"] == "point":
			continue
		var rel: Vector3 = (it["local"] as Vector3) - c
		var pos: Vector2 = project(rel)
		var chip: String = ChipText.chip(it["label"], it["local"]) if chips else ""
		var rect: Rect2 = Rect2(pos, Vector2.ZERO)
		if chip != "":
			var sz: Vector2 = font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			sz.y = font.get_height(FONT_SIZE)
			rect = Rect2(Vector2(pos.x + 10.0, pos.y - sz.y / 2.0), sz)
		(
			out
			. append(
				{
					"item": it,
					"rel": rel,
					"pos": pos,
					"foot": project(Vector3(rel.x, 0.0, rel.z)),
					"chip": chip,
					"chip_rect": rect,
				}
			)
		)
	return out


func _is_selected(it: Dictionary) -> bool:
	return not selected.is_empty() and _ref(it) == _ref(selected)


func _shape(it: Dictionary) -> String:
	return Palette.ALLEGIANCE_SHAPES.get(it.get("allegiance", ""), "circle")


func _item_color(it: Dictionary) -> Color:
	if it["kind"] == "mark":
		return Palette.color("mark")
	return Palette.allegiance_color(it.get("allegiance", ""))


func _dim() -> Color:
	return Palette.color("text_dim")


static func _km(m: float) -> String:
	return str(snappedf(m / 1000.0, 0.1)) if m < 10_000.0 else str(roundi(m / 1000.0))


static func _ref(it: Dictionary) -> Dictionary:
	return {"kind": it.get("kind", ""), "id": it.get("id", -1)}
