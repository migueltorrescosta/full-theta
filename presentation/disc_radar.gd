class_name DiscRadar
extends Control
## The shared disc radar (spec §6.2, D42, D43, D124; FT-STN-002, FT-SPA-007-011,
## FT-SPA-024, FT-SPA-025): the deck plane of the own ship as a disc with clock numbers on
## the rim, each item a blip with a stem to the disc (solid above, hollow below), a
## range ring through the selected item's stem foot, an optional elevation side strip,
## fixed range steps with beyond-scale arrows on the rim, the selected stem drawn on
## top, marks as diamonds with stems, contact chips (ChipText) and ping pulses. Ship
## frame always; optionally centred on a selected mark, site or contact while keeping
## the ship's axes (no world-fixed up, D124). Drawn in 2D with a fixed or orbitable
## camera angle (FT-SPA-011). Mouse: wheel zooms, a click on the range label steps the
## range, right-drag orbits when orbitable; other clicks pass to the screen (item_at).
##
## Projection: ship frame (-Z bow, +X starboard, +Y up) relative to the centre item,
## from the minimum image of the world-axes difference (D124, ContactPicture.rel); the
## camera sits `tilt_deg` above the disc plane, turned `yaw_deg` around the ship's
## up axis; at yaw 0 the bow points up the screen and starboard right.

## Range steps (m) (FT-SPA-024).
const RANGES_M: Array[float] = [2000.0, 10000.0, 50000.0]
const TILT_MIN: float = 10.0
const TILT_MAX: float = 90.0
const FONT_SIZE: int = 13
## Width of the elevation side strip (px).
const STRIP_W: float = 44.0
## Room around the disc for the clock numbers (px).
const PAD: float = 24.0
const BLIP_R: float = 6.0
## item_at picks the nearest blip within this distance (px).
const HIT_PX: float = 12.0
const ORBIT_DEG_PER_PX: float = 0.4

## The items to draw (ContactPicture). "point" items (point pings) draw only their
## pulse and are never picked.
var picture: ContactPicture = ContactPicture.new()
## {"kind", "id"} of the shared selection, or {}.
var selected: Dictionary = {}
## The item the disc is centred on ({} = own ship).
var centre: Dictionary = {}
var range_index: int = 1
var side_strip: bool = false
var orbitable: bool = false
## Camera: tilt above the disc plane and yaw around the ship's up axis (degrees).
var tilt_deg: float = 35.0
var yaw_deg: float = 0.0
## Draw chips next to contacts (off on small insets).
var chips: bool = true

var _orbiting: bool = false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	clip_contents = true


func set_picture(p_picture: ContactPicture, p_selected: Dictionary) -> void:
	picture = p_picture
	selected = p_selected
	queue_redraw()


## One range step in (-1) or out (+1).
func zoom(step: int) -> void:
	range_index = clampi(range_index + step, 0, RANGES_M.size() - 1)
	queue_redraw()


func toggle_strip() -> void:
	side_strip = not side_strip
	queue_redraw()


## The item drawn under local_pos ({"kind", "id"}), or {}: the selected item first,
## then the nearest blip or mark within HIT_PX, then a chip under the pointer.
func item_at(local_pos: Vector2) -> Dictionary:
	var layout: Array[Dictionary] = _layout()
	for e: Dictionary in layout:
		if _is_selected(e["item"]) and _hits(e, local_pos):
			return _ref(e["item"])
	var best: Dictionary = {}
	var best_d: float = HIT_PX
	for e: Dictionary in layout:
		var d: float = (e["pos"] as Vector2).distance_to(local_pos)
		if d <= best_d:
			best_d = d
			best = e["item"]
	if not best.is_empty():
		return _ref(best)
	for e: Dictionary in layout:
		if (e["chip_rect"] as Rect2).has_point(local_pos):
			return _ref(e["item"])
	return {}


## Bearing and mark of the item under local_pos, for hover only (FT-SPA-005); "" if none.
func hover_text(local_pos: Vector2) -> String:
	var it: Dictionary = picture.find(item_at(local_pos))
	return ChipText.precise(it["local"]) if not it.is_empty() else ""


## Screen position (px, this control's coordinates) of an item at `local` (ship frame
## from the own ship, m), within range or not.
func project(local: Vector3) -> Vector2:
	return _screen(_rel(local))


## True when an item at `local` is above the disc plane (solid blip, stem up).
func is_above(local: Vector3) -> bool:
	return _rel(local).y >= 0.0


## True when an item at `local` is beyond the range step (an arrow on the rim).
func is_beyond(local: Vector3) -> bool:
	return _rel(local).length() > RANGES_M[range_index]


## The disc centre (px).
func disc_centre() -> Vector2:
	var area: Rect2 = _area()
	return area.position + area.size / 2.0


## The disc radius (px): fits the width and leaves room for stems above and below.
func disc_radius() -> float:
	var half: Vector2 = _area().size / 2.0 - Vector2(PAD, PAD)
	var t: float = deg_to_rad(tilt_deg)
	return maxf(8.0, minf(half.x, half.y / (sin(t) + 0.35 * cos(t))))


func _get_tooltip(at_position: Vector2) -> String:
	if _range_rect().has_point(at_position):
		return tr("radar.range_tip")
	return hover_text(at_position)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1)
		elif (
			mb.pressed
			and mb.button_index == MOUSE_BUTTON_LEFT
			and _range_rect().has_point(mb.position)
		):
			range_index = (range_index + 1) % RANGES_M.size()
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and orbitable:
			_orbiting = mb.pressed
		else:
			return
		accept_event()
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _orbiting:
		yaw_deg = fposmod(yaw_deg + mm.relative.x * ORBIT_DEG_PER_PX, 360.0)
		tilt_deg = clampf(tilt_deg - mm.relative.y * ORBIT_DEG_PER_PX, TILT_MIN, TILT_MAX)
		queue_redraw()
		accept_event()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var c: Vector2 = disc_centre()
	var r: float = RANGES_M[range_index]
	_draw_disc(font, c, r)
	var layout: Array[Dictionary] = _layout()
	var sel: Dictionary = {}
	for e: Dictionary in layout:
		if _is_selected(e["item"]):
			sel = e
		else:
			_draw_item(e, false)
	_draw_own()
	if not sel.is_empty():
		# FT-SPA-008: the range ring through the selected stem foot; FT-SPA-025: on top.
		var rel: Vector3 = sel["rel"]
		var ring: float = minf(Vector2(rel.x, rel.z).length(), r)
		draw_polyline(_ring(ring), Palette.color("selected") * Color(1, 1, 1, 0.6), 1.0, true)
		_draw_item(sel, true)
	for e: Dictionary in layout:
		if e["chip"] != "" and e != sel:
			_draw_text(font, e["chip_rect"], e["chip"], Palette.item_color(e["item"]))
	if not sel.is_empty() and sel["chip"] != "":
		_draw_text(font, sel["chip_rect"], sel["chip"], Palette.color("selected"))
	for it: Dictionary in picture.items:
		if it["kind"] == "point":
			_draw_pulse(_screen(_rel_item(it)), float(it.get("pulse", 0.0)))
	var label: Rect2 = _range_rect()
	draw_rect(label, Palette.color("panel_focus"))
	draw_rect(label, Palette.color("line"), false, 1.0)
	_draw_text(font, label.grow(-4.0), _range_text(), Palette.color("text"))
	if side_strip:
		_draw_strip(font)


## The disc, half-range ring, clock ticks every 30° and the numbers 12, 3, 6, 9.
func _draw_disc(font: Font, c: Vector2, r: float) -> void:
	var rim: PackedVector2Array = _ring(r)
	draw_colored_polygon(rim.slice(0, -1), Palette.color("panel") * Color(1, 1, 1, 0.85))
	draw_polyline(_ring(r / 2.0), Palette.color("line"), 1.0, true)
	draw_polyline(rim, Palette.color("text_dim"), 1.5, true)
	for hour: int in 12:
		var b: float = deg_to_rad(30.0 * hour)
		var dir: Vector3 = Vector3(sin(b), 0.0, -cos(b))
		var outer: Vector2 = _screen(dir * r)
		draw_line(_screen(dir * r * 0.92), outer, Palette.color("text_dim"), 1.0, true)
		if hour % 3 == 0:
			var text: String = str(12 if hour == 0 else hour)
			var out: Vector2 = (outer - c).normalized() * 12.0
			var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			_draw_text(font, Rect2(outer + out - sz / 2.0, sz), text, Palette.color("text"))


## The own ship: a chevron pointing at the bow, with a stem when off-centre.
func _draw_own() -> void:
	var off: Vector3 = picture.rel(Vector3.ZERO, centre)
	var p: Vector2 = _screen(off)
	var col: Color = Palette.color("own")
	if off != Vector3.ZERO:
		draw_line(_screen(Vector3(off.x, 0.0, off.z)), p, col * Color(1, 1, 1, 0.6), 1.0, true)
	var bow: Vector2 = _screen(off + Vector3(0.0, 0.0, -RANGES_M[range_index] * 0.1)) - p
	var d: Vector2 = bow.normalized() if bow.length() > 0.01 else Vector2.UP
	var n: Vector2 = Vector2(-d.y, d.x)
	draw_colored_polygon(
		PackedVector2Array(
			[p + d * 8.0, p - d * 5.0 + n * 6.0, p - d * 2.0, p - d * 5.0 - n * 6.0]
		),
		col
	)


func _draw_item(e: Dictionary, is_sel: bool) -> void:
	var it: Dictionary = e["item"]
	if it["kind"] == "point":
		return
	var col: Color = Palette.item_color(it)
	var pos: Vector2 = e["pos"]
	var solid: bool = (e["rel"] as Vector3).y >= 0.0
	if e["beyond"]:
		# FT-SPA-024: an arrow on the rim pointing outward.
		var d: Vector2 = (pos - disc_centre()).normalized()
		var n: Vector2 = Vector2(-d.y, d.x)
		var tri: PackedVector2Array = PackedVector2Array(
			[pos + d * 7.0, pos - d * 4.0 + n * 6.0, pos - d * 4.0 - n * 6.0, pos + d * 7.0]
		)
		_draw_shape(tri, col, solid)
	else:
		var foot: Vector2 = e["foot"]
		var stem: Color = Palette.color("selected") if is_sel else col * Color(1, 1, 1, 0.7)
		draw_line(foot, pos, stem, 2.0 if is_sel else 1.0, true)
		draw_line(foot - Vector2(3, 0), foot + Vector2(3, 0), stem, 1.0, true)
		_draw_shape(Palette.shape_points(Palette.item_shape(it), pos, BLIP_R), col, solid)
	if is_sel:
		draw_rect(
			Rect2(pos - Vector2(9, 9), Vector2(18, 18)), Palette.color("selected"), false, 1.5
		)
	_draw_pulse(pos, float(it.get("pulse", 0.0)))


func _draw_shape(pts: PackedVector2Array, col: Color, solid: bool) -> void:
	if solid:
		draw_colored_polygon(pts.slice(0, -1), col)
	else:
		draw_colored_polygon(pts.slice(0, -1), Palette.color("background"))
		draw_polyline(pts, col, 1.5, true)


## FT-SPA-016: a ring that grows and fades as the ping's pulse runs out.
func _draw_pulse(pos: Vector2, pulse: float) -> void:
	if pulse <= 0.0:
		return
	var col: Color = Palette.color("ping")
	col.a = pulse
	draw_arc(pos, BLIP_R + 4.0 + (1.0 - pulse) * 22.0, 0.0, TAU, 32, col, 2.0, true)


## FT-SPA-009: elevation -90..+90 of every item from the own ship, one tick each.
func _draw_strip(font: Font) -> void:
	var x0: float = size.x - STRIP_W
	var top: float = PAD
	var bottom: float = size.y - PAD
	draw_rect(Rect2(x0, 0.0, STRIP_W, size.y), Palette.color("panel"))
	var mid: float = x0 + STRIP_W * 0.6
	var y_of: Callable = func(el: float) -> float: return remap(el, 90.0, -90.0, top, bottom)
	var band: Rect2 = Rect2(mid - 8.0, y_of.call(15.0), 16.0, y_of.call(-15.0) - y_of.call(15.0))
	draw_rect(band, Palette.color("panel_focus"))
	draw_line(Vector2(mid, top), Vector2(mid, bottom), Palette.color("line"), 1.0)
	for el: float in [90.0, 0.0, -90.0]:
		var text: String = "%+d" % int(el) if el != 0.0 else "0"
		var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2)
		var at: Vector2 = Vector2(x0 + 2.0, y_of.call(el) + sz.y / 3.0)
		draw_string(
			font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, Palette.color("text_dim")
		)
	for it: Dictionary in picture.items:
		if it["kind"] == "point":
			continue
		var y: float = y_of.call(Callout.elevation_deg(it["local"]))
		var is_sel: bool = _is_selected(it)
		var w: float = 10.0 if is_sel else 6.0
		var col: Color = Palette.color("selected") if is_sel else Palette.item_color(it)
		draw_line(Vector2(mid - w, y), Vector2(mid + w, y), col, 3.0 if is_sel else 2.0)


func _draw_text(font: Font, rect: Rect2, text: String, col: Color) -> void:
	var base: Vector2 = rect.position + Vector2(0.0, font.get_ascent(FONT_SIZE))
	Palette.draw_outlined(self, font, base, text, FONT_SIZE, col)


## Per item (points last): {"item", "rel" (from the centre), "pos", "foot", "beyond",
## "chip" (text or ""), "chip_rect"}.
func _layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var font: Font = get_theme_default_font()
	var c: Vector2 = disc_centre()
	var r: float = RANGES_M[range_index]
	for it: Dictionary in picture.items:
		if it["kind"] == "point":
			continue
		var local: Vector3 = it["local"]
		var rel: Vector3 = _rel_item(it)
		var beyond: bool = rel.length() > r
		var pos: Vector2 = _screen(rel)
		var foot: Vector2 = _screen(Vector3(rel.x, 0.0, rel.z))
		if beyond:
			var h: Vector3 = Vector3(rel.x, 0.0, rel.z)
			h = h.normalized() if h.length() > 0.001 else Vector3.FORWARD
			pos = _screen(h * r)
			foot = pos
		var chip: String = ""
		if chips:
			chip = it["label"] if it["kind"] != "contact" else ChipText.chip(it["label"], local)
		var rect: Rect2 = Rect2(pos, Vector2.ZERO)
		if chip != "":
			var sz: Vector2 = font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			sz.y = font.get_height(FONT_SIZE)
			# Right of the blip; arrows on the rim put it on the inner side.
			var left: bool = beyond and pos.x > c.x
			var x: float = pos.x - 10.0 - sz.x if left else pos.x + 10.0
			rect = Rect2(Vector2(x, pos.y - sz.y / 2.0), sz)
		(
			out
			. append(
				{
					"item": it,
					"rel": rel,
					"pos": pos,
					"foot": foot,
					"beyond": beyond,
					"chip": chip,
					"chip_rect": rect,
				}
			)
		)
	return out


## Screen position of a ship-frame offset from the centre item (m).
func _screen(rel: Vector3) -> Vector2:
	var yaw: float = deg_to_rad(yaw_deg)
	var t: float = deg_to_rad(tilt_deg)
	var s: float = disc_radius() / RANGES_M[range_index]
	var fwd: float = -rel.z
	var right: float = rel.x * cos(yaw) - fwd * sin(yaw)
	var ahead: float = rel.x * sin(yaw) + fwd * cos(yaw)
	return disc_centre() + Vector2(right, -ahead * sin(t) - rel.y * cos(t)) * s


## A closed ring of radius `radius` (m) in the disc plane.
func _ring(radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 65:
		var a: float = TAU * float(i % 64) / 64.0
		pts.append(_screen(Vector3(cos(a), 0.0, sin(a)) * radius))
	return pts


## Ship-frame offset from the centre item of a point at `local` (ship frame from the
## own ship).
func _rel(local: Vector3) -> Vector3:
	return picture.rel(picture.interp.own_rotation() * local, centre)


## Ship-frame offset of an item from the centre item.
func _rel_item(it: Dictionary) -> Vector3:
	return picture.rel(it["world"], centre)


func _area() -> Rect2:
	return Rect2(Vector2.ZERO, size - Vector2(STRIP_W if side_strip else 0.0, 0.0))


func _range_rect() -> Rect2:
	var font: Font = get_theme_default_font()
	var sz: Vector2 = font.get_string_size(_range_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	sz = Vector2(sz.x, font.get_height(FONT_SIZE)) + Vector2(8.0, 8.0)
	return Rect2(Vector2(6.0, size.y - sz.y - 6.0), sz)


func _range_text() -> String:
	return tr("radar.km") % str(int(RANGES_M[range_index] / 1000.0))


func _hits(e: Dictionary, p: Vector2) -> bool:
	return (e["pos"] as Vector2).distance_to(p) <= HIT_PX or (e["chip_rect"] as Rect2).has_point(p)


func _is_selected(it: Dictionary) -> bool:
	return not selected.is_empty() and _ref(it) == _ref(selected)


static func _ref(it: Dictionary) -> Dictionary:
	return {"kind": it.get("kind", ""), "id": it.get("id", -1)}
