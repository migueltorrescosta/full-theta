class_name DiscRadar
extends Control
## The shared disc radar (spec §6.2, D42, D43, D124; FT-STN-002, FT-SPA-007-011,
## FT-SPA-024, FT-SPA-025): the deck plane of the own ship as a disc with clock numbers on
## the rim, each item a blip with a stem to the disc (solid above, hollow below), a
## range ring through the selected item's stem foot, an optional elevation side strip,
## fixed range steps with beyond-scale arrows on the rim, the selected stem drawn on
## top, marks as diamonds with stems, hazard zones and scan positions as octagons, the
## site's name as a banner (SiteBanner, FT-SPA-027), contact chips (ChipText) and ping
## pulses. Ship
## frame always; optionally centred on a selected mark, site or contact while keeping
## the ship's axes (no world-fixed up, D124). Drawn in 2D with a fixed or orbitable
## camera angle (FT-SPA-011). Mouse: wheel zooms, a click on the range label steps the
## range, right-drag orbits when orbitable; other clicks pass to the screen (item_at).
## Touch: a two-finger drag orbits when orbitable (spec §5.4 touch, #28).
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
## Least space (px) between a chip and the edge of the view.
const CHIP_MARGIN: float = 2.0
## A chip stays within this distance (px) of its own blip: when no spot is free that near,
## the chip is shortened before it is moved farther (D319).
const CHIP_REACH: float = 48.0
## The nearer reach tried first (px): a shorter chip close to its blip reads better than
## the full chip a line away.
const CHIP_NEAR: float = 24.0
## item_at picks the nearest blip within this distance (px).
const HIT_PX: float = 12.0
const ORBIT_DEG_PER_PX: float = 0.4
## Under this disc radius (px) the radar is small (a phone's side column, rail or flat
## mirror strip, #28): chips
## carry the callsign alone and take a free spot beside, above or below their blip, clear
## of the clock numbers, the own ship, the other blips and each other, or are left out
## (the selected item's never is).
const SMALL_R: float = 80.0
## A burst ring lasts this long (ms); most at once.
const BURST_MS: int = 900
const MAX_BURSTS: int = 6
## Under this width the range box drops its "Range" word.
const SMALL_RADAR_W: float = 360.0

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
## Contact id -> blip size factor (Science's detection confidence, FT-SCI-001); a contact
## not listed draws at the usual size.
var blip_scale: Dictionary = {}
## The part of the control the disc, the range label and the site banner keep to, in its
## coordinates; empty for all of it. Overlay thumb rails cover the rest (#28).
var view_rect: Rect2 = Rect2():
	set(value):
		view_rect = value
		queue_redraw()
## The least side (px) of the range label and of the site banner's tap area, 0 for the
## text's size; above 0 each also gets a control with the `tap` meta, so TapAudit sees
## them (a phone, #28).
var touch_min: float = 0.0:
	set(value):
		touch_min = value
		queue_redraw()

var _orbiting: bool = false
var _ctx: StationContext
## Rings of the destroyed contacts and hits on the own ship: {rel, from (ms), role}.
var _bursts: Array[Dictionary] = []
## Fingers down on the radar: index -> position (two orbit).
var _fingers: Dictionary = {}
var _taps: Array[Control] = []


func _init() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	clip_contents = true
	set_process(false)


## The blip radius in px: BLIP_R, grown at UI scales under 100 % to stay that many physical px (C2).
func blip_r() -> float:
	return Palette.blip_radius(BLIP_R, self)


## Sets the picture and the selection; `ctx` (once is enough) lets the radar ring a destroyed
## contact and a hit on the own ship (#12), unless comfort is on.
func set_picture(
	p_picture: ContactPicture, p_selected: Dictionary, ctx: StationContext = null
) -> void:
	picture = p_picture
	selected = p_selected
	if ctx != null and _ctx != ctx:
		_ctx = ctx
		ctx.crew.sim_event.connect(on_sim_event)
	queue_redraw()


## A sim event: a ring at a destroyed contact (red), or round the own ship when it is hit
## (amber). Nothing with comfort on.
func on_sim_event(kind: StringName, p: Dictionary) -> void:
	if _ctx == null or _ctx.settings.comfort:
		return
	var id: int = int(p.get("ship", -1))
	if kind == &"hit" and id == _ctx.crew.ship:
		_add_burst(Vector3.ZERO, "warn")
	elif kind == &"destroyed":
		for it: Dictionary in picture.items:
			if it["kind"] == "contact" and int(it["id"]) == id:
				_add_burst(_rel_item(it), "danger")
				return


func _add_burst(rel: Vector3, role: String) -> void:
	_bursts.append({"rel": rel, "from": Time.get_ticks_msec(), "role": role})
	if _bursts.size() > MAX_BURSTS:
		_bursts.pop_front()
	set_process(true)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	_bursts = _bursts.filter(func(b: Dictionary) -> bool: return now - int(b["from"]) < BURST_MS)
	if _bursts.is_empty():
		set_process(false)
	queue_redraw()


## Rings that grow and fade as a burst runs out.
func _draw_bursts() -> void:
	var now: int = Time.get_ticks_msec()
	for b: Dictionary in _bursts:
		var t: float = clampf(float(now - int(b["from"])) / float(BURST_MS), 0.0, 1.0)
		var col: Color = Palette.color(str(b["role"]))
		col.a = 1.0 - t
		draw_arc(_screen(b["rel"]), blip_r() + 4.0 + t * 30.0, 0.0, TAU, 32, col, 2.0, true)


## One range step in (-1) or out (+1).
func zoom(step: int) -> void:
	range_index = clampi(range_index + step, 0, RANGES_M.size() - 1)
	queue_redraw()


func toggle_strip() -> void:
	side_strip = not side_strip
	queue_redraw()


## The item drawn under local_pos ({"kind", "id"}), or {}: the selected item first,
## then the nearest blip or mark within `reach` px (HIT_PX; a controller cursor snaps
## from farther), then a chip under the pointer.
func item_at(local_pos: Vector2, reach: float = HIT_PX) -> Dictionary:
	if _site_rect().has_point(local_pos):
		return _ref(picture.site)
	var layout: Array[Dictionary] = _layout()
	for e: Dictionary in layout:
		if _is_selected(e["item"]) and _hits(e, local_pos):
			return _ref(e["item"])
	var best: Dictionary = {}
	var best_d: float = reach
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
	if _touch(event):
		return
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


## Two fingers orbit an orbitable radar: the yaw follows their mean sideways move, the tilt
## their mean up-down move. One finger passes on (its emulated mouse taps and selects).
## True when the event was used.
func _touch(event: InputEvent) -> bool:
	var st: InputEventScreenTouch = event as InputEventScreenTouch
	if st != null:
		if st.pressed:
			_fingers[st.index] = st.position
		else:
			_fingers.erase(st.index)
		return false
	var sd: InputEventScreenDrag = event as InputEventScreenDrag
	if sd == null:
		return false
	_fingers[sd.index] = sd.position
	if not orbitable or _fingers.size() < 2:
		return false
	var step: Vector2 = sd.relative / float(_fingers.size())
	yaw_deg = fposmod(yaw_deg + step.x * ORBIT_DEG_PER_PX, 360.0)
	tilt_deg = clampf(tilt_deg - step.y * ORBIT_DEG_PER_PX, TILT_MIN, TILT_MAX)
	queue_redraw()
	accept_event()
	return true


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var c: Vector2 = disc_centre()
	var r: float = RANGES_M[range_index]
	_draw_disc(font, c, r)
	var layout: Array[Dictionary] = _layout()
	var covers: Array[Rect2] = SheetCover.over(self)
	hide_covered(layout, covers)
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
	_draw_bursts()
	var label: Rect2 = _range_rect()
	if not SheetCover.touches(label, covers):
		draw_rect(label, Palette.color("panel_focus"))
		draw_rect(label, Palette.color("line"), false, 1.0)
		var text: String = _range_text()
		var tsz: Vector2 = Vector2(
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x,
			font.get_height(FONT_SIZE)
		)
		_draw_text(font, Rect2(label.get_center() - tsz / 2.0, tsz), text, Palette.color("text"))
	if not SheetCover.touches(_site_rect(), covers):
		draw_set_transform(_view().position)
		SiteBanner.draw(self, font, picture.site, _is_selected(picture.site), _roomy())
		draw_set_transform(Vector2.ZERO)
	if side_strip:
		_draw_strip(font)
	_sync_taps()


## The disc, half-range ring, clock ticks every 30° and the numbers 12, 3, 6, 9.
func _draw_disc(font: Font, c: Vector2, r: float) -> void:
	var rim: PackedVector2Array = _ring(r)
	draw_colored_polygon(rim.slice(0, -1), Palette.color("panel") * Color(1, 1, 1, 0.85))
	draw_polyline(_ring(r / 2.0), Palette.color("line"), 1.0, true)
	draw_polyline(rim, Palette.color("text_dim"), 1.5, true)
	for hour: int in 12:
		var b: float = deg_to_rad(30.0 * hour)
		var dir: Vector3 = Vector3(sin(b), 0.0, -cos(b))
		draw_line(_screen(dir * r * 0.92), _screen(dir * r), Palette.color("text_dim"), 1.0, true)
	var numerals: Dictionary = _numerals(font, c, r)
	for text: String in numerals:
		_draw_text(font, numerals[text], text, Palette.color("text"))


## The clock numbers 12, 3, 6 and 9 and their boxes, just outside the rim.
func _numerals(font: Font, c: Vector2, r: float) -> Dictionary:
	var out: Dictionary = {}
	for hour: int in [0, 3, 6, 9]:
		var b: float = deg_to_rad(30.0 * hour)
		var outer: Vector2 = _screen(Vector3(sin(b), 0.0, -cos(b)) * r)
		var text: String = str(12 if hour == 0 else hour)
		var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		out[text] = Rect2(outer + (outer - c).normalized() * 12.0 - sz / 2.0, sz)
	return out


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
		var radius: float = (
			blip_r() * float(blip_scale.get(it["id"], 1.0)) if it["kind"] == "contact" else blip_r()
		)
		_draw_shape(Palette.shape_points(Palette.item_shape(it), pos, radius), col, solid)
	if it.get("zone", "") == "probe" and not e["beyond"]:
		# The probe's coverage bubble, as a ring in the disc plane.
		var ring: PackedVector2Array = PackedVector2Array()
		for i: int in 65:
			var a: float = TAU * float(i % 64) / 64.0
			ring.append(
				_screen((e["rel"] as Vector3) + Vector3(cos(a), 0.0, sin(a)) * float(it["radius"]))
			)
		draw_polyline(ring, col * Color(1, 1, 1, 0.5), 1.0, true)
	if is_sel:
		draw_rect(
			Rect2(pos - Vector2(9, 9), Vector2(18, 18)), Palette.color("selected"), false, 1.5
		)
	_draw_pulse(pos, float(it.get("pulse", 0.0)), it.get("copies", []))


func _draw_shape(pts: PackedVector2Array, col: Color, solid: bool) -> void:
	if solid:
		draw_colored_polygon(pts.slice(0, -1), col)
	else:
		draw_colored_polygon(pts.slice(0, -1), Palette.color("background"))
		draw_polyline(pts, col, 1.5, true)


## FT-SPA-016: a ring that grows and fades as the ping's pulse runs out.
func _draw_pulse(pos: Vector2, pulse: float, copies: Array = []) -> void:
	if pulse <= 0.0:
		return
	var col: Color = Palette.color("ping")
	col.a = pulse
	draw_arc(pos, blip_r() + 4.0 + (1.0 - pulse) * 22.0, 0.0, TAU, 32, col, 2.0, true)
	_draw_copies(pos, col, copies)


## FT-SPA-031: "+ Bo, Cy" under a pulse names the stations that copied the ping.
func _draw_copies(pos: Vector2, col: Color, copies: Array) -> void:
	if copies.is_empty():
		return
	var font: Font = get_theme_default_font()
	var text: String = "+ " + ", ".join(PackedStringArray(copies))
	Palette.draw_outlined(self, font, pos + Vector2(-8.0, 26.0), text, FONT_SIZE, col)


## FT-SPA-009: elevation -90..+90 of every item from the own ship, one tick each.
func _draw_strip(font: Font) -> void:
	var x0: float = _view().end.x - STRIP_W
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
		if small():
			chip = it["label"] if chips else ""
		var rect: Rect2 = Rect2(pos, Vector2.ZERO)
		var variants: Array[String] = []
		var sizes: Array[Vector2] = []
		if chip != "" and not small():
			# A small radar (a phone's 180 px column) drops the range band, then the clock,
			# until the chip fits beside its blip; the callsign alone may slide over it.
			var parts: PackedStringArray = chip.split(ChipText.SEP)
			for n: int in range(parts.size(), 0, -1):
				chip = ChipText.SEP.join(parts.slice(0, n))
				rect = _chip_rect(font, chip, pos, beyond and pos.x > c.x)
				if rect.position.x > pos.x + blip_r() or rect.end.x < pos.x - blip_r():
					break
			var forms: Array = chip_forms(font, chip)
			variants.assign(forms[0])
			sizes.assign(forms[1])
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
					"variants": variants,
					"sizes": sizes,
					"selected": _is_selected(it),
				}
			)
		)
	if small():
		_place_small(out, font)
	else:
		var rim: float = disc_radius()
		var tilt: float = sin(deg_to_rad(tilt_deg))
		var fixed: Array = _numerals(font, c, r).values()
		fixed.append_array([_range_rect(), _site_rect(), _own_box()])
		_declutter(
			out,
			fixed,
			_view().grow(-CHIP_MARGIN),
			Rect2(c - Vector2(rim, rim * tilt), Vector2(rim, rim * tilt) * 2.0),
			blip_r() + 3.0
		)
	return out


## A chip a sheet would cut in half is not drawn at all (D319): `layout`'s chips under
## `covers` (SheetCover.over) are emptied.
static func hide_covered(layout: Array[Dictionary], covers: Array[Rect2]) -> void:
	if covers.is_empty():
		return
	for e: Dictionary in layout:
		if e["chip"] != "" and SheetCover.touches(e["chip_rect"], covers):
			e["chip"] = ""


## A chip's shorter forms, longest first ("H2 · 4 high · mid", "H2 · 4 high", "H2"), with
## their sizes (px): [Array[String], Array[Vector2]]. The placement falls back on them when
## no spot near the blip is free (D319).
static func chip_forms(font: Font, chip: String) -> Array:
	var variants: Array[String] = []
	var sizes: Array[Vector2] = []
	var all: PackedStringArray = chip.split(ChipText.SEP)
	for n: int in range(all.size(), 0, -1):
		var form: String = ChipText.SEP.join(all.slice(0, n))
		variants.append(form)
		sizes.append(
			Vector2(
				font.get_string_size(form, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x,
				font.get_height(FONT_SIZE)
			)
		)
	return [variants, sizes]


## True when the disc is under SMALL_R in radius.
func small() -> bool:
	return disc_radius() < SMALL_R


## Small radar: each chip (the selected item's first) takes the first free spot of right,
## left, above and below its blip; a chip with no free spot is left out unless selected.
func _place_small(entries: Array[Dictionary], font: Font) -> void:
	var v: Rect2 = _view().grow(-CHIP_MARGIN)
	if v.size.x <= 0.0 or v.size.y <= 0.0:
		# (not laid out yet: no room for a chip)
		for e: Dictionary in entries:
			e["chip"] = ""
			e["chip_rect"] = Rect2(e["pos"], Vector2.ZERO)
		return
	var c: Vector2 = disc_centre()
	var taken: Array[Rect2] = []
	var numerals: Array = _numerals(font, c, RANGES_M[range_index]).values()
	taken.append_array(numerals)
	taken.append_array([_range_rect(), _site_rect()])
	taken.append(_own_box())
	var half: Vector2 = Vector2(blip_r(), blip_r()) + Vector2(3, 3)
	for e: Dictionary in entries:
		taken.append(Rect2((e["pos"] as Vector2) - half, half * 2.0))
	var order: Array[Dictionary] = entries.duplicate()
	order.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _is_selected(a["item"]) and not _is_selected(b["item"])
	)
	for e: Dictionary in order:
		if e["chip"] == "":
			continue
		var sz: Vector2 = Vector2(
			font.get_string_size(e["chip"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x,
			font.get_height(FONT_SIZE)
		)
		var p: Vector2 = e["pos"]
		var spots: Array[Vector2] = [
			Vector2(p.x + half.x + 1.0, p.y - sz.y / 2.0),
			Vector2(p.x - half.x - 1.0 - sz.x, p.y - sz.y / 2.0),
			Vector2(p.x - sz.x / 2.0, p.y - half.y - sz.y),
			Vector2(p.x - sz.x / 2.0, p.y + half.y),
		]
		var pick: Rect2 = Rect2()
		for at: Vector2 in spots:
			var r: Rect2 = Rect2(at, sz)
			if not v.encloses(r):
				continue
			if taken.all(func(o: Rect2) -> bool: return not o.intersects(r)):
				pick = r
				break
		if not pick.has_area() and _is_selected(e["item"]):
			# The selection's chip always shows: the first spot, kept inside the view, that
			# clears the range numerals.
			for at: Vector2 in spots:
				var r: Rect2 = Rect2(at.clamp(v.position, (v.end - sz).max(v.position)), sz)
				if not pick.has_area():
					pick = r
				if numerals.all(func(o: Rect2) -> bool: return not o.intersects(r)):
					pick = r
					break
		if pick.has_area():
			taken.append(pick)
			e["chip_rect"] = pick
		else:
			e["chip"] = ""
			e["chip_rect"] = Rect2(p, Vector2.ZERO)


## The own ship's box (px), which no chip covers.
func _own_box() -> Rect2:
	return Rect2(_screen(picture.rel(Vector3.ZERO, centre)) - Vector2(9, 9), Vector2(18, 18))


## A chip's box: right of the blip at `pos`, left of it when `left` (an arrow on the right
## rim) or when only that side fits, then shifted to stay inside the view: a small radar
## never clips a chip at its edge (#28).
func _chip_rect(font: Font, chip: String, pos: Vector2, left: bool) -> Rect2:
	var sz: Vector2 = font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	sz.y = font.get_height(FONT_SIZE)
	var v: Rect2 = _view().grow(-CHIP_MARGIN)
	var right_x: float = pos.x + 10.0
	var left_x: float = pos.x - 10.0 - sz.x
	var x: float = left_x if left else right_x
	if not left and right_x + sz.x > v.end.x and left_x >= v.position.x:
		x = left_x
	elif left and left_x < v.position.x and right_x + sz.x <= v.end.x:
		x = right_x
	x = clampf(x, v.position.x, maxf(v.position.x, v.end.x - sz.x))
	var y: float = clampf(pos.y - sz.y / 2.0, v.position.y, maxf(v.position.y, v.end.y - sz.y))
	return Rect2(Vector2(x, y), sz)


## Places each chip next to its own blip, then moves it by the least that clears what it
## must not cover (spots tried: beside the default, right, left, above, below, a line off).
## Hard obstacles: the clock numbers and other boxes in `fixed`, every blip's box (entries
## with a "pos"), the chips already placed and the other items' stems; a spot also has to
## keep inside `limit` and within CHIP_REACH of its own blip. When no spot is free, the
## chip is shortened (its "variants", longest first, with their "sizes"), then may cross
## other stems (soft, as is leaving `disc`'s ellipse, charged as a cost), then takes the
## free spot nearest its blip with the callsign alone. Selected chips are placed first,
## then top to bottom. Without a blip a chip with no free spot drops below what it overlaps.
static func _declutter(
	entries: Array[Dictionary],
	fixed: Array = [],
	limit: Rect2 = Rect2(),
	disc: Rect2 = Rect2(),
	blip: float = 9.0
) -> void:
	var boxes: Array[Rect2] = []
	var blocked: Array[Rect2] = []
	var stems: Array[Dictionary] = []
	for f: Variant in fixed:
		boxes.append(f as Rect2)
	for e: Dictionary in entries:
		if not e.has("pos"):
			continue
		var p: Vector2 = e["pos"]
		blocked.append(Rect2(p - Vector2(blip, blip), Vector2(blip, blip) * 2.0))
		if e.has("foot") and not e.get("beyond", false):
			var f: Vector2 = e["foot"]
			(
				stems
				. append(
					{
						"rect": Rect2(minf(f.x, p.x) - 1.0, minf(f.y, p.y), 2.0, absf(f.y - p.y)),
						"owner": e,
					}
				)
			)
	var order: Array[Dictionary] = entries.filter(
		func(e: Dictionary) -> bool: return e["chip"] != ""
	)
	order.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.get("selected", false) != b.get("selected", false):
				return a.get("selected", false)
			return (a["chip_rect"] as Rect2).position.y < (b["chip_rect"] as Rect2).position.y
	)
	blocked.append_array(boxes)
	var placed: Array[Rect2] = []
	for e: Dictionary in order:
		var home: Rect2 = e["chip_rect"]
		var variants: Array = e.get("variants", [])
		var sizes: Array = e.get("sizes", [])
		var n: int = maxi(variants.size(), 1)
		var pick: Rect2 = Rect2()
		var text: String = e["chip"]
		# (near, then up to CHIP_REACH, with the other stems hard, then soft: every form, the
		# longest first, at each step)
		for step: Array in [
			[CHIP_NEAR, true], [CHIP_REACH, true], [CHIP_NEAR, false], [CHIP_REACH, false]
		]:
			for k: int in n:
				var h: Rect2 = home if k == 0 else _home_for(home, e["pos"], sizes[k])
				pick = _best_spot(e, h, blocked, placed, stems, limit, disc, blip, step[1], step[0])
				if pick.has_area():
					text = variants[k] if k > 0 else text
					break
			if pick.has_area():
				break
		if pick.has_area():
			e["chip"] = text
		else:
			# No free spot near the blip: the callsign alone, nearest to it that is free of
			# the hard boxes, else stepped down below what it overlaps.
			if n > 1:
				e["chip"] = variants[n - 1]
				home = _home_for(home, e["pos"], sizes[n - 1])
			pick = home
			for _pass: int in order.size() + boxes.size():
				var hit: bool = false
				for o: Rect2 in boxes + placed:
					if o.intersects(pick):
						pick.position.y = o.end.y
						hit = true
				if not hit:
					break
		e["chip_rect"] = pick
		placed.append(pick)


## `home` resized to `size`, on the same side of the blip at `pos`.
static func _home_for(home: Rect2, pos: Vector2, size: Vector2) -> Rect2:
	var x: float = home.position.x if home.position.x >= pos.x else home.end.x - size.x
	return Rect2(Vector2(x, home.get_center().y - size.y / 2.0), size)


## The distance (px) from `p` to the nearest point of `r`.
static func _gap_to(r: Rect2, p: Vector2) -> float:
	var dx: float = maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy: float = maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dy).length()


## The spot for a chip whose default box is `home`: the cheapest free one, or an empty
## Rect2. With a blip, a spot is within CHIP_REACH of it; `hard_stems` makes the other
## items' stems obstacles too.
static func _best_spot(
	e: Dictionary,
	home: Rect2,
	blocked: Array[Rect2],
	placed: Array[Rect2],
	stems: Array[Dictionary],
	limit: Rect2,
	disc: Rect2,
	blip: float,
	hard_stems: bool,
	reach: float = CHIP_REACH
) -> Rect2:
	var sz: Vector2 = home.size
	var spots: Array[Rect2] = [home]
	if e.has("pos"):
		var p: Vector2 = e["pos"]
		var gap: float = blip + 1.0
		var ys: Array[float] = [0.0, sz.y, -sz.y, sz.y * 2.0, -sz.y * 2.0]
		for dy: float in ys:
			spots.append(Rect2(Vector2(p.x + gap, p.y - sz.y / 2.0 + dy), sz))
			spots.append(Rect2(Vector2(p.x - gap - sz.x, p.y - sz.y / 2.0 + dy), sz))
		spots.append(Rect2(Vector2(p.x - sz.x / 2.0, p.y - gap - sz.y), sz))
		spots.append(Rect2(Vector2(p.x - sz.x / 2.0, p.y + gap), sz))
		# (corners: above and below, flush with the blip's right or left side)
		spots.append(Rect2(Vector2(p.x, p.y - gap - sz.y), sz))
		spots.append(Rect2(Vector2(p.x - sz.x, p.y - gap - sz.y), sz))
		spots.append(Rect2(Vector2(p.x, p.y + gap), sz))
		spots.append(Rect2(Vector2(p.x - sz.x, p.y + gap), sz))
	var best: Rect2 = Rect2()
	var best_cost: float = INF
	for spot: Rect2 in spots:
		if limit.has_area() and not limit.grow(0.5).encloses(spot):
			continue
		if e.has("pos") and _gap_to(spot, e["pos"]) > reach:
			continue
		var free: bool = true
		for o: Rect2 in blocked + placed:
			if o.intersects(spot):
				free = false
				break
		if not free:
			continue
		var cost: float = spot.get_center().distance_to(home.get_center())
		for s: Dictionary in stems:
			if (s["rect"] as Rect2).intersects(spot):
				if hard_stems and s["owner"] != e:
					free = false
					break
				cost += 8.0
		if not free:
			continue
		if disc.has_area():
			if not _in_ellipse(disc, spot):
				cost += 10.0
			# (a ring's line through the text strikes it out)
			var half: Rect2 = Rect2(disc.get_center() - disc.size / 4.0, disc.size / 2.0)
			for ring: Rect2 in [disc, half]:
				if _crosses_ellipse(ring, spot):
					cost += 6.0
		if cost < best_cost:
			best_cost = cost
			best = spot
	return best


## True when the outline of the ellipse inscribed in `box` passes through `r`: some of the
## corners and edge midpoints of `r` lie inside it and some outside.
static func _crosses_ellipse(box: Rect2, r: Rect2) -> bool:
	var c: Vector2 = box.get_center()
	var h: Vector2 = box.size / 2.0
	var mid: Vector2 = r.get_center()
	var inside: int = 0
	var points: Array[Vector2] = [
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
		Vector2(mid.x, r.position.y),
		Vector2(mid.x, r.end.y),
		Vector2(r.position.x, mid.y),
		Vector2(r.end.x, mid.y),
	]
	for q: Vector2 in points:
		if ((q - c) / h).length_squared() <= 1.0:
			inside += 1
	return inside > 0 and inside < points.size()


## True when all four corners of `r` lie inside the ellipse inscribed in `box`.
static func _in_ellipse(box: Rect2, r: Rect2) -> bool:
	var c: Vector2 = box.get_center()
	var h: Vector2 = box.size / 2.0
	for corner: Vector2 in [
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)
	]:
		var d: Vector2 = (corner - c) / h
		if d.length_squared() > 1.0:
			return false
	return true


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


## The rectangle the radar draws in: view_rect, or the whole control.
func _view() -> Rect2:
	return view_rect if view_rect.has_area() else Rect2(Vector2.ZERO, size)


func _area() -> Rect2:
	var v: Rect2 = _view()
	return Rect2(v.position, v.size - Vector2(STRIP_W if side_strip else 0.0, 0.0))


## The range label: bottom left of the view, at least touch_min on each side.
func _range_rect() -> Rect2:
	var font: Font = get_theme_default_font()
	var sz: Vector2 = font.get_string_size(_range_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	sz = Vector2(sz.x, font.get_height(FONT_SIZE)) + Vector2(8.0, 8.0)
	sz = sz.max(Vector2(touch_min, touch_min))
	var v: Rect2 = _view()
	return Rect2(Vector2(v.position.x + 6.0, v.end.y - sz.y - 6.0), sz)


## Where a tap picks the site banner: its box, at least touch_min tall and wide.
func _site_rect() -> Rect2:
	var r: Rect2 = SiteBanner.rect(get_theme_default_font(), picture.site, _roomy())
	if not r.has_area():
		return r
	r.position += _view().position
	r.size = r.size.max(Vector2(touch_min, touch_min))
	return r


## The range label's and site banner's tap controls follow them (only with touch_min).
func _sync_taps() -> void:
	if touch_min <= 0.0 and _taps.is_empty():
		return
	if _taps.is_empty():
		for n: String in ["RangeTap", "SiteTap"]:
			var c: Control = Control.new()
			c.name = n
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.set_meta("tap", true)
			add_child(c)
			_taps.append(c)
	var rects: Array[Rect2] = [_range_rect(), _site_rect()]
	for i: int in _taps.size():
		_taps[i].visible = touch_min > 0.0 and rects[i].has_area()
		_taps[i].position = rects[i].position
		_taps[i].size = rects[i].size


## True when the radar has room for the words in its two boxes ("Range", "Zone:").
func _roomy() -> bool:
	return _view().size.x >= SMALL_RADAR_W


func _range_text() -> String:
	# A small radar (a phone's 180 px column) keeps the short "10 km" so its chips have room.
	var key: String = "radar.range_km" if _roomy() else "radar.km"
	return tr(key) % str(int(RANGES_M[range_index] / 1000.0))


func _hits(e: Dictionary, p: Vector2) -> bool:
	return (e["pos"] as Vector2).distance_to(p) <= HIT_PX or (e["chip_rect"] as Rect2).has_point(p)


func _is_selected(it: Dictionary) -> bool:
	return not selected.is_empty() and _ref(it) == _ref(selected)


static func _ref(it: Dictionary) -> Dictionary:
	return {"kind": it.get("kind", ""), "id": it.get("id", -1)}
