class_name RelayMap
extends Control
## Relay's map read-out (§5.5, FT-RLY-001, FT-SPA-006, D124): a freely rotatable 3D view
## of the site, centred on the own ship or a selected item, drawn in 2D with an
## orthographic camera. Everything is in the ship frame (-Z bow, +X starboard, +Y up),
## offsets from the centre taken along the minimum image in world axes (D124),
## so stems drop to the ship's deck plane through the map centre and chips read like
## every other station; the camera turns freely about its own axes, so the map has no
## world-fixed up, no grid squares and no layers. The site's wrapping cube is drawn
## honestly as faint edges: one period P on a side around the own ship, the region the
## minimum image places every item in (D124).
##
## Probes (a ring and dot with the coverage bubble as a circle of its radius), hazard zones
## (the same, amber), routes (dashed lines with an arrow), flagged lanes that cross a
## friendly (red lines, FT-RLY-011) and the site's name as a banner (FT-SPA-027) are drawn
## here from what the panel hands in.
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
## A lane crossing a friendly counts when the friendly is within this of the line (m).
const LANE_R: float = 200.0
## A plane hazard front's bar is this long each way, its arrow this long (px).
const FRONT_HALF_PX: float = 60.0
const FRONT_ARROW_PX: float = 24.0

## The items (ContactPicture); its interpolator gives the own ship's orientation and
## position, to place the cube and turn map points into positions, and
## the site period (no cube without one).
var picture: ContactPicture = ContactPicture.new()
var selected: Dictionary = {}
## The item the map is centred on ({} = own ship).
var centre: Dictionary = {}
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
## The ship's probes (the RELAY block's rows): {"serial", "deployed", "pos" (
## m), "range" (m)}.
var probes: Array = []
## Routes (CrewState.routes): arrays of {"pos"} waypoints.
var routes: Array = []
## Lane flagging is on (the RELAY block's `lanes`): lanes crossing a friendly are drawn.
var lanes_on: bool = false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true


## Pixels per metre.
func ppm() -> float:
	return minf(size.x, size.y) / 2.0 / span_m


## Zoom in (-1) or out (+1) one step.
func zoom(step: int) -> void:
	var top: float = period_m() if period_m() > 0.0 else 1.0e6
	span_m = clampf(span_m * pow(ZOOM_STEP, step), SPAN_MIN_M, top)
	queue_redraw()


## Turns the camera about its own up and right axes (right-drag, right stick).
func rotate_by(delta_px: Vector2) -> void:
	var yaw: Basis = Basis(view.y.normalized(), -delta_px.x * ROTATE_RAD_PER_PX)
	var pitch: Basis = Basis(view.x.normalized(), -delta_px.y * ROTATE_RAD_PER_PX)
	view = (yaw * pitch * view).orthonormalized()
	queue_redraw()


## Site period (m), 0 when unknown.
func period_m() -> float:
	return float(picture.interp.p_units) / NetCodec.POS_Q


## World-axes offset of the centre item from the own ship (ZERO on the ship).
func centre_world() -> Vector3:
	return picture.find(centre).get("world", Vector3.ZERO)


## Ship-frame offset from the map centre of an item (minimum image, D124).
func rel_of(it: Dictionary) -> Vector3:
	return picture.rel(it["world"], centre)


## Screen position (px) of a ship-frame offset from the map centre.
func project(rel: Vector3) -> Vector2:
	var p: Vector3 = view.transposed() * rel
	return size / 2.0 + Vector2(p.x, -p.y) * ppm()


## Ship-frame offset from the map centre of a screen point at `depth` metres along the
## view direction (positive toward the camera; 0 is the plane through the centre).
func unproject(pos: Vector2, depth: float = 0.0) -> Vector3:
	var d: Vector2 = (pos - size / 2.0) / ppm()
	return view * Vector3(d.x, -d.y, depth)


## A ship-frame offset from the map centre as a position (m; the server wraps).
func site_position(rel: Vector3) -> Vector3:
	var interp: SnapshotInterpolator = picture.interp
	return interp.own_position() + centre_world() + interp.own_rotation() * rel


## The ship-frame offset from the own ship of a ship-frame offset from the map centre
## (minimum image).
func from_own(rel: Vector3) -> Vector3:
	var interp: SnapshotInterpolator = picture.interp
	return interp.local(interp.min_image(centre_world() + interp.own_rotation() * rel))


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


## The lanes from the own ship to a hostile or unknown contact that pass within LANE_R of a
## friendly or neutral one (FT-RLY-011, P8): [{"target": id, "friend": id, "label":
## friend's label}]. Items are ContactPicture items (world offsets from the own ship).
static func crossing_lanes(items: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in items:
		if t["kind"] != "contact" or t["allegiance"] not in ["H", "U"]:
			continue
		var line: Vector3 = t["world"]
		var len2: float = line.length_squared()
		if len2 < 1.0:
			continue
		for f: Dictionary in items:
			if f["kind"] != "contact" or f["allegiance"] not in ["F", "N"] or f["id"] == t["id"]:
				continue
			var at: Vector3 = f["world"]
			var along: float = at.dot(line) / len2
			if along <= 0.0 or along >= 1.0:
				continue
			if at.distance_to(line * along) <= LANE_R:
				out.append({"target": t["id"], "friend": f["id"], "label": f["label"]})
	return out


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background"))
	var c: Vector3 = centre_world()
	_draw_cube(c)
	_draw_deck(not centre.is_empty())
	var layout: Array[Dictionary] = _layout()
	_draw_routes()
	_draw_bubbles(layout)
	if lanes_on:
		_draw_lanes(layout, font)
	var sel: Dictionary = {}
	for e: Dictionary in layout:
		if _is_selected(e["item"]):
			sel = e
		else:
			_draw_item(e, false)
	_draw_own(picture.rel(Vector3.ZERO, centre))
	if not sel.is_empty():
		_draw_item(sel, true)
	for e: Dictionary in layout:
		if e["chip"] != "":
			var col: Color = (
				Palette.color("selected") if e == sel else Palette.item_color(e["item"])
			)
			_draw_text(font, e["chip_rect"].position, e["chip"], col)
	for it: Dictionary in picture.items:
		if it["kind"] == "point":
			_draw_pulse(project(rel_of(it)), float(it.get("pulse", 0.0)))
	_draw_probes(font)
	_draw_preview(font)
	if cursor_on:
		var col: Color = Palette.color("accent")
		draw_line(cursor - Vector2(10, 0), cursor + Vector2(10, 0), col, 1.5)
		draw_line(cursor - Vector2(0, 10), cursor + Vector2(0, 10), col, 1.5)
	var scale_text: String = tr("relay.span") % _km(span_m)
	_draw_text(font, Vector2(8.0, size.y - 8.0 - font.get_height(FONT_SIZE)), scale_text, _dim())


## Hazard bubbles: the sphere's silhouette is a circle of its radius; a sim plane front
## (`dir`) is a line across its travel with an arrowhead along it.
func _draw_bubbles(layout: Array[Dictionary]) -> void:
	for e: Dictionary in layout:
		var it: Dictionary = e["item"]
		if it["kind"] == "zone" and it.has("dir"):
			_draw_front(e)
		elif it["kind"] == "zone":
			var col: Color = Palette.item_color(it)
			var r_px: float = float(it.get("radius", 0.0)) * ppm()
			draw_circle(e["pos"], r_px, col * Color(1, 1, 1, 0.12))
			draw_arc(e["pos"], r_px, 0.0, TAU, 48, col * Color(1, 1, 1, 0.6), 1.5, true)


## A plane front: a bar through its nearest point, square to its travel on screen, and an
## arrow along the travel.
func _draw_front(e: Dictionary) -> void:
	var col: Color = Palette.item_color(e["item"])
	var ahead: Vector2 = project(e["rel"] + (e["item"]["dir"] as Vector3) * 1000.0) - e["pos"]
	var along: Vector2 = ahead.normalized() if ahead.length() > 1.0 else Vector2.DOWN
	var across: Vector2 = Vector2(-along.y, along.x)
	draw_line(e["pos"] - across * FRONT_HALF_PX, e["pos"] + across * FRONT_HALF_PX, col, 3.0, true)
	draw_line(e["pos"], e["pos"] + along * FRONT_ARROW_PX, col, 1.5, true)


## Probes: a ring with a dot, solid once on station; a deployed probe's coverage bubble is
## a circle of its range (FT-RLY-001, FT-RLY-004).
func _draw_probes(font: Font) -> void:
	var col: Color = Palette.color("accent")
	for pr: Dictionary in probes:
		var rel: Vector3 = picture.rel(picture.interp.offset_to(pr["pos"]), centre)
		var p: Vector2 = project(rel)
		draw_line(project(Vector3(rel.x, 0.0, rel.z)), p, col * Color(1, 1, 1, 0.5), 1.0, true)
		if pr["deployed"]:
			var r_px: float = float(pr["range"]) * ppm()
			draw_circle(p, r_px, col * Color(1, 1, 1, 0.08))
			draw_arc(p, r_px, 0.0, TAU, 48, col * Color(1, 1, 1, 0.5), 1.0, true)
		draw_arc(p, BLIP_R, 0.0, TAU, 20, col, 2.0, true)
		draw_circle(p, 2.0, col if pr["deployed"] else Palette.color("background"))
		_draw_text(font, p + Vector2(10.0, -8.0), "P%d" % (int(pr["serial"]) + 1), col)


## Routes: dashed lines from the ship through each waypoint, an arrowhead at the end.
func _draw_routes() -> void:
	var col: Color = Palette.color("mark")
	for route: Array in routes:
		if route.is_empty():
			continue
		var last: Vector2 = project(picture.rel(Vector3.ZERO, centre))
		for w: Dictionary in route:
			var rel: Vector3 = picture.rel(picture.interp.offset_to(w["pos"]), centre)
			var p: Vector2 = project(rel)
			draw_dashed_line(last, p, col, 2.0, 6.0, true)
			draw_circle(p, 3.0, col)
			if w == route[-1]:
				var d: Vector2 = (p - last).normalized()
				var n: Vector2 = Vector2(-d.y, d.x)
				draw_colored_polygon(
					PackedVector2Array([p + d * 7.0, p - d * 3.0 + n * 5.0, p - d * 3.0 - n * 5.0]),
					col
				)
			last = p


## Lanes that cross a friendly, red, with "lane x N7" at the friendly (FT-RLY-011).
func _draw_lanes(layout: Array[Dictionary], font: Font) -> void:
	var own: Vector2 = project(picture.rel(Vector3.ZERO, centre))
	var by_id: Dictionary = {}
	for e: Dictionary in layout:
		if e["item"]["kind"] == "contact":
			by_id[e["item"]["id"]] = e
	for lane: Dictionary in crossing_lanes(picture.items):
		var t: Dictionary = by_id.get(lane["target"], {})
		var f: Dictionary = by_id.get(lane["friend"], {})
		if t.is_empty() or f.is_empty():
			continue
		var col: Color = Palette.color("danger")
		draw_line(own, t["pos"], col, 2.0, true)
		_draw_text(font, f["pos"] + Vector2(10.0, 8.0), tr("relay.lane") % lane["label"], col)


## The wrapping cube: one period on a side, world-axis aligned, around the own ship;
## `c` is the centre item's world-axes offset.
func _draw_cube(c: Vector3) -> void:
	if period_m() <= 0.0:
		return
	var h: float = period_m() / 2.0
	var corner: Callable = func(i: int) -> Vector2:
		var w: Vector3 = Vector3(h if i & 1 else -h, h if i & 2 else -h, h if i & 4 else -h)
		return project(picture.interp.local(w - c))
	var col: Color = Palette.color("line") * Color(1, 1, 1, 0.5)
	for i: int in 8:
		for bit: int in [1, 2, 4]:
			if not i & bit:
				draw_line(corner.call(i), corner.call(i | bit), col, 1.0, true)


## A faint ring in the deck plane through the centre (ship axes) with a bow tick, so
## stems have something to land on; not a grid. A cross marks the centre off the ship.
func _draw_deck(centred: bool) -> void:
	var r: float = span_m * 0.6
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 65:
		var a: float = TAU * float(i % 64) / 64.0
		pts.append(project(Vector3(cos(a) * r, 0.0, sin(a) * r)))
	draw_polyline(pts, Palette.color("line"), 1.0, true)
	draw_line(project(Vector3(0, 0, -r * 0.9)), project(Vector3(0, 0, -r)), _dim(), 1.5, true)
	if centred:
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
	var col: Color = Palette.item_color(it)
	var pos: Vector2 = e["pos"]
	var foot: Vector2 = e["foot"]
	var stem: Color = Palette.color("selected") if is_sel else col * Color(1, 1, 1, 0.7)
	draw_line(foot, pos, stem, 2.0 if is_sel else 1.0, true)
	draw_line(foot - Vector2(3, 0), foot + Vector2(3, 0), stem, 1.0, true)
	var pts: PackedVector2Array = Palette.shape_points(Palette.item_shape(it), pos, BLIP_R)
	if (e["rel"] as Vector3).y >= 0.0:
		draw_colored_polygon(pts.slice(0, -1), col)
	else:
		draw_colored_polygon(pts.slice(0, -1), Palette.color("background"))
		draw_polyline(pts, col, 1.5, true)
	if is_sel:
		draw_rect(
			Rect2(pos - Vector2(9, 9), Vector2(18, 18)), Palette.color("selected"), false, 1.5
		)
	_draw_pulse(pos, float(it.get("pulse", 0.0)), it.get("copies", []))


func _draw_pulse(pos: Vector2, pulse: float, copies: Array = []) -> void:
	if pulse <= 0.0:
		return
	var col: Color = Palette.color("ping")
	col.a = pulse
	draw_arc(pos, BLIP_R + 4.0 + (1.0 - pulse) * 22.0, 0.0, TAU, 32, col, 2.0, true)
	if not copies.is_empty():
		var text: String = "+ " + ", ".join(PackedStringArray(copies))
		_draw_text(get_theme_default_font(), pos + Vector2(-8.0, 14.0), text, col)


## The mark being placed: an outline diamond, its stem, a line back to the view plane
## when Shift+drag moved it in depth, and its chip from the own ship.
func _draw_preview(font: Font) -> void:
	if preview.is_empty():
		return
	var rel: Vector3 = preview["rel"]
	var p: Vector2 = project(rel)
	var col: Color = Palette.color("mark")
	draw_line(project(Vector3(rel.x, 0.0, rel.z)), p, col * Color(1, 1, 1, 0.7), 1.0, true)
	draw_line(project(preview["plane"]), p, col * Color(1, 1, 1, 0.4), 1.0, true)
	draw_polyline(Palette.shape_points("diamond", p, BLIP_R + 2.0), col, 2.0, true)
	var label: String = str(preview.get("label", ""))
	_draw_text(font, p + Vector2(12.0, -8.0), say_point(label, rel), col)


## What the map says of a point at `rel` (ship frame from the centre): its chip from the
## own ship, or, past the far band (10 km), the point said relative to the nearest mark
## or the site (`Bravo, 12 high, 3 km`, FT-SPA-006, FT-SPA-026).
func say_point(label: String, rel: Vector3) -> String:
	var interp: SnapshotInterpolator = picture.interp
	var local: Vector3 = from_own(rel)
	if local.length() <= Callout.FAR_M:
		return ChipText.chip(label, local)
	var at: Vector3 = centre_world() + interp.own_rotation() * rel
	var refs: Array[Dictionary] = []
	for it: Dictionary in picture.items:
		if it["kind"] == "mark":
			refs.append({"name": it["label"], "world": it["world"]})
	if not picture.site.is_empty():
		refs.append({"name": picture.site["label"], "world": interp.offset_to(Vector3.ZERO)})
	var best: Vector3 = Vector3.ZERO
	var best_name: String = ""
	var best_d: float = INF
	for r: Dictionary in refs:
		var off: Vector3 = interp.min_image(at - (r["world"] as Vector3))
		if off.length() < best_d:
			best_d = off.length()
			best = off
			best_name = r["name"]
	if best_name == "":
		return ChipText.chip(label, local)
	return "%s: %s" % [label, ChipText.relative(best_name, interp.local(best))]


func _draw_text(font: Font, at: Vector2, text: String, col: Color) -> void:
	var base: Vector2 = at + Vector2(0.0, font.get_ascent(FONT_SIZE))
	Palette.draw_outlined(self, font, base, text, FONT_SIZE, col)


## Per item (point pings left out): {"item", "rel", "pos", "foot", "chip", "chip_rect"}.
func _layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var font: Font = get_theme_default_font()
	for it: Dictionary in picture.items:
		if it["kind"] == "point":
			continue
		var rel: Vector3 = rel_of(it)
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


func _dim() -> Color:
	return Palette.color("text_dim")


static func _km(m: float) -> String:
	return str(snappedf(m / 1000.0, 0.1)) if m < 10_000.0 else str(roundi(m / 1000.0))


static func _ref(it: Dictionary) -> Dictionary:
	return {"kind": it.get("kind", ""), "id": it.get("id", -1)}
