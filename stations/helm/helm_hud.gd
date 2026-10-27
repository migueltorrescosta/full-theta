class_name HelmHud
extends Control
## Helm's HUD over the 3D view (§5.1, S5's HUD with the station data): reticle,
## prograde and retrograde markers, brackets on contacts and diamonds on marks
## (allegiance colour and shape, FT-STN-006), off-screen arrows for the selection and
## pinged items (FT-HLM-004), the target compass (FT-HLM-003), the flight read-out
## (assist or decoupled, speed, setpoint, active assist modes), the thrust envelope and
## propellant (FT-HLM-012) and the controller radial. Compact (docked): compass and
## read-out only. Drawn every frame from the panel's context; never captures input.
## On a phone the read-outs and edge arrows stay inside `area()`, clear of the touch rails
## (HelmPanel.hud_area, #28).

const FONT_SIZE: int = 14
const SMALL: int = 12
## Off-screen arrows sit this far inside the view's edge.
const EDGE: float = 36.0
## On a phone an arrow keeps this far (px) from the read-outs (its label sits beside it).
const ARROW_CLEAR: float = 14.0
const COMPASS_R: float = 46.0
## Envelope bars show 0..BAR_MAX of nominal; a tick marks nominal.
const BAR_MAX: float = 1.5
## Speeds under this (m/s) show no velocity markers.
const DRIFT_MIN: float = 0.5
## Translation input above this lights its thrust arrow.
const THRUST_LIT: float = 0.05
## The thrust cross: arm distance and arrow size (px).
const CROSS_ARM: float = 24.0
const CROSS_ARROW: float = 9.0
## Narrower views move the thrust cross above the flight read-out.
const NARROW_W: float = 640.0
## A phone (portrait) keeps it top left.
const PHONE_W: float = 420.0
## The flight read-out's top edge, from the view's bottom.
const READOUT_H: float = 168.0
## Envelope bar length, and on a phone (narrower, so the compass fits beside the read-out).
const BAR_W: float = 140.0
const PHONE_BAR_W: float = 100.0

var panel: HelmPanel
var compact: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Where the read-outs go (this control's coordinates): the view clear of a phone's rails,
## else all of it.
func area() -> Rect2:
	if panel == null:
		return Rect2(Vector2.ZERO, size)
	return panel.hud_area(self)


## True with a phone's touch layout over the view.
func touch_layout() -> bool:
	return panel != null and panel.touch_ui != null


func _bar_w() -> float:
	return PHONE_BAR_W if touch_layout() else BAR_W


## The items on the view: ContactPicture's contacts, marks and named sites with their screen
## position, `on_screen`, `behind`, `selected` and `arrow`; [] when there is no camera
## (docked).
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if compact or panel == null or panel.view3d == null or panel.view3d.camera == null:
		return out
	var cam: Camera3D = panel.view3d.camera
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var picture: ContactPicture = panel.ctx.picture()
	for item: Dictionary in picture.items + picture.sites:
		if item["kind"] == "point":
			continue
		var world: Vector3 = item["world"]
		var e: Dictionary = item.duplicate()
		e["behind"] = cam.is_position_behind(world)
		e["pos"] = Vector2.ZERO if e["behind"] else cam.unproject_position(world)
		e["on_screen"] = not e["behind"] and rect.has_point(e["pos"])
		e["selected"] = panel.ctx.crew.is_selected(e["kind"], e["id"])
		# Off-screen arrows for the selection and pinged items (FT-HLM-004).
		e["arrow"] = not e["on_screen"] and (e["selected"] or float(e["pulse"]) > 0.0)
		out.append(e)
	return out


## Relay's routes on this view, in screen pixels (FT-RLY-005, P4): one entry per route with
## a Vector2 per waypoint, or null for a waypoint behind the camera. They
## only exist while the routes toggle lets them reach Helm (the server withholds them on
## Hard, FT-PAIR-008).
func route_points() -> Array:
	var out: Array = []
	if compact or panel == null or panel.view3d == null or panel.view3d.camera == null:
		return out
	var cam: Camera3D = panel.view3d.camera
	for route: Array in panel.ctx.crew.routes:
		var points: Array = []
		for w: Dictionary in route:
			var spot: Variant = null
			var world: Vector3 = panel.ctx.interp.offset_to(w["pos"])
			if not cam.is_position_behind(world):
				spot = cam.unproject_position(world)
			points.append(spot)
		out.append(points)
	return out


## The ribbon: a wide soft line through the waypoints, a gate ring and number at each, and a
## thin leader from the reticle to the first waypoint in view.
func _draw_routes(font: Font) -> void:
	var col: Color = Palette.color("accent")
	for points: Array in route_points():
		var previous: Variant = null
		var first: bool = true
		for i: int in points.size():
			var p: Variant = points[i]
			if p == null:
				previous = null
				continue
			if previous != null:
				draw_line(previous, p, Color(col, 0.35), 8.0)
				draw_line(previous, p, Color(col, 0.9), 1.5)
			elif first:
				draw_line(size / 2.0, p, Color(col, 0.5), 1.0)
			first = false
			draw_arc(p, 12.0, 0.0, TAU, 20, col, 2.0)
			_text(font, (p as Vector2) + Vector2(16.0, -10.0), str(i + 1), col, SMALL)
			previous = p


## Comms' approach lanes on this view, in screen pixels (P5, FT-PAIR-001): {"pos" (Vector2),
## "state" ("wait" amber until the window opens, "open" green inside it, "late" red after),
## "left_s" (s until the window opens, or closes while open)}, only for lanes in front of the
## camera. They exist only while the lanes toggle lets them reach Helm (Comms shared them, or
## the view holds Comms; the server withholds them on Hard).
func lane_marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if compact or panel == null or panel.view3d == null or panel.view3d.camera == null:
		return out
	var cam: Camera3D = panel.view3d.camera
	var now: int = panel.ctx.now_ms()
	for lane: Dictionary in panel.ctx.crew.lanes:
		var world: Vector3 = panel.ctx.interp.offset_to(lane["pos"])
		if cam.is_position_behind(world):
			continue
		var state: String = "wait"
		var left: float = (int(lane["opens_ms"]) - now) / 1000.0
		if now >= int(lane["closes_ms"]):
			state = "late"
			left = 0.0
		elif now >= int(lane["opens_ms"]):
			state = "open"
			left = (int(lane["closes_ms"]) - now) / 1000.0
		out.append({"pos": cam.unproject_position(world), "state": state, "left_s": left})
	return out


## A ring and a countdown at each lane's site: amber while the window is ahead, green inside
## it, red once it has closed.
func _draw_lanes(font: Font) -> void:
	var colours: Dictionary[String, String] = {"wait": "warn", "open": "ok", "late": "danger"}
	for lane: Dictionary in lane_marks():
		var col: Color = Palette.color(colours[lane["state"]])
		var at: Vector2 = lane["pos"]
		draw_arc(at, 18.0, 0.0, TAU, 28, col, 2.5)
		var text: String = tr("helm.lane." + String(lane["state"]))
		if lane["state"] != "late":
			text += " %d s" % ceili(float(lane["left_s"]))
		_text(font, at + Vector2(24.0, -4.0), text, col, SMALL)


func _draw() -> void:
	if panel == null or panel.ctx == null:
		return
	var font: Font = get_theme_default_font()
	if compact:
		_draw_compass(font, Vector2(COMPASS_R + 12.0, size.y / 2.0 - 10.0))
		_draw_readout(font, Vector2(2.0 * COMPASS_R + 28.0, size.y / 2.0 - 24.0), false)
		return
	_draw_reticle()
	_draw_velocity(font)
	_draw_thrust(font)
	_draw_routes(font)
	_draw_lanes(font)
	for e: Dictionary in markers():
		if e["on_screen"]:
			_draw_marker(font, e, e["selected"])
		elif e["arrow"]:
			_draw_arrow(font, e, e["selected"])
	var a: Rect2 = area()
	_draw_compass(font, _compass_centre())
	_draw_readout(font, Vector2(a.position.x + 16.0, a.end.y - 150.0), true)
	if panel.chase:
		_text(font, a.position + Vector2(16.0, 24.0), tr("helm.chase"), Palette.color("text_dim"))
	if not panel.steering() and panel.ctx.matcher.device == IntentTable.KBM and not touch_layout():
		_text(font, Vector2(16.0, 44.0), tr("helm.pointer_free"), Palette.color("text_dim"))
	if panel.ctx.matcher.is_held("helm_radial"):
		_draw_radial(font)


func _draw_reticle() -> void:
	var c: Vector2 = size / 2.0
	var col: Color = Color(Palette.color("text"), 0.7)
	draw_arc(c, 10.0, 0.0, TAU, 24, col, 1.5)
	draw_line(c + Vector2(-22.0, 0.0), c + Vector2(-12.0, 0.0), col, 1.5)
	draw_line(c + Vector2(12.0, 0.0), c + Vector2(22.0, 0.0), col, 1.5)
	var stick: Vector2 = panel.ctx.matcher.mouse_stick.value
	if panel.steering() and stick.length() > 0.02:
		draw_circle(c + stick * 80.0, 3.0, Palette.color("ok"))


## The velocity markers on the view, in screen pixels (HUD coordinates): `kind` "pro"
## (prograde, along the drift) always, "retro" only while moving backwards; `pos`,
## `on_screen`, and `edge` for a marker clamped to the view's edge because its direction is
## off screen or behind. [] when nearly still or there is no camera.
func velocity_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v: Vector3 = velocity()
	if compact or panel == null or panel.view3d == null or panel.view3d.camera == null:
		return out
	if v.length() < DRIFT_MIN:
		return out
	var cam: Camera3D = panel.view3d.camera
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	for pro: bool in [true, false]:
		if not pro and local_velocity().z <= 0.0:
			continue
		var dir: Vector3 = v.normalized() * (1.0 if pro else -1.0)
		var world: Vector3 = dir * 5000.0
		var behind: bool = cam.is_position_behind(world)
		var at: Vector2 = Vector2.ZERO if behind else cam.unproject_position(world)
		var edge: bool = behind or not rect.has_point(at)
		if edge:
			var d: Vector3 = cam.global_transform.basis.inverse() * world
			at = _edge_point(Vector2(d.x, -d.y))
		out.append({"kind": "pro" if pro else "retro", "pos": at, "edge": edge})
	return out


## Prograde (circle with ticks) and retrograde (circle with a cross), clamped to the
## view's edge when off screen, each named.
func _draw_velocity(font: Font) -> void:
	var col: Color = Palette.color("ok")
	for m: Dictionary in velocity_markers():
		var s: Vector2 = m["pos"]
		var pro: bool = m["kind"] == "pro"
		if m["edge"]:
			draw_circle(s, 12.0, Color(Palette.color("background"), 0.6))
		draw_arc(s, 8.0, 0.0, TAU, 20, col, 1.5)
		if pro:
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
				draw_line(s + d * 8.0, s + d * 14.0, col, 1.5)
		else:
			draw_line(s + Vector2(-6.0, -6.0), s + Vector2(6.0, 6.0), col, 1.5)
			draw_line(s + Vector2(-6.0, 6.0), s + Vector2(6.0, -6.0), col, 1.5)
		var text: String = tr("helm.prograde" if pro else "helm.retrograde")
		var at: Rect2 = label_rect(font, text, s, 14.0)
		_text(font, at.position + Vector2(0.0, font.get_ascent(FONT_SIZE)), text, col)


## The translation input that lights the thrust arrows: x starboard +, y up +, z forward +.
func thrust_input() -> Vector3:
	var cmd: Dictionary = panel.input_command()
	return Vector3(cmd["strafe"], cmd["lift"], cmd["throttle"])


## The thrust cross's centre: beside the compass, clear of the ring.
func thrust_centre() -> Vector2:
	var a: Rect2 = area()
	if touch_layout():
		# A phone's view: top left of the part clear of the rails.
		return a.position + Vector2(CROSS_ARM + 22.0, 52.0)
	if size.x < PHONE_W:
		# A phone has no room beside the compass: top left, under the mode captions.
		return Vector2(CROSS_ARM + 22.0, 92.0)
	if size.x < NARROW_W:
		# No room beside the compass: a fixed panel on the left, just above the read-out,
		# where no contact marker or the ring sits.
		return Vector2(CROSS_ARM + 22.0, size.y - READOUT_H - CROSS_ARM - 20.0)
	var x: float = clampf(size.x / 2.0, 440.0, maxf(440.0, size.x - 360.0))
	return Vector2(x, size.y - 72.0)


## Arrows for sway (left, right), heave (up, down) and forward / astern (the pair beside
## the cross), lit while that thrust fires, with the ship-frame speeds (forward, lateral,
## vertical) beside them.
func _draw_thrust(font: Font) -> void:
	var c: Vector2 = thrust_centre()
	var t: Vector3 = thrust_input()
	# [where from the centre (in CROSS_ARM), pointing, input].
	var arrows: Array = [
		[Vector2.LEFT, Vector2.LEFT, -t.x],
		[Vector2.RIGHT, Vector2.RIGHT, t.x],
		[Vector2.UP, Vector2.UP, t.y],
		[Vector2.DOWN, Vector2.DOWN, -t.y],
		[Vector2(2.6, -0.8), Vector2.UP, t.z],
		[Vector2(2.6, 0.8), Vector2.DOWN, -t.z],
	]
	draw_rect(thrust_rect(), Color(Palette.color("background"), 0.5))
	for a: Array in arrows:
		var lit: bool = float(a[2]) > THRUST_LIT
		var col: Color = Palette.color("accent") if lit else Color(Palette.color("text_dim"), 0.45)
		var pts: PackedVector2Array = _triangle(c + (a[0] as Vector2) * CROSS_ARM, a[1])
		if lit:
			draw_colored_polygon(pts, col)
		else:
			pts.append(pts[0])
			draw_polyline(pts, col, 1.5)
	var l: Vector3 = local_velocity()
	var rows: Array = [
		[tr("helm.vel_fwd"), -l.z], [tr("helm.vel_side"), l.x], [tr("helm.vel_up"), l.y]
	]
	for i: int in rows.size():
		var text: String = "%s %s" % [rows[i][0], speed_text(float(rows[i][1]))]
		var at: Vector2 = c + Vector2(CROSS_ARM * 3.6, -14.0 + 16.0 * i)
		_text(font, at, text, Palette.color("text"), SMALL)


## The thrust cross and its read-outs, for the labels to keep clear of.
func thrust_rect() -> Rect2:
	var c: Vector2 = thrust_centre()
	return Rect2(
		c - Vector2(CROSS_ARM + 14.0, CROSS_ARM + 14.0), Vector2(250.0, 2.0 * CROSS_ARM + 28.0)
	)


## A triangle of CROSS_ARROW at `base` pointing along `dir`.
static func _triangle(base: Vector2, dir: Vector2) -> PackedVector2Array:
	var side: Vector2 = dir.orthogonal()
	return PackedVector2Array(
		[
			base + dir * CROSS_ARROW,
			base - dir * CROSS_ARROW * 0.6 + side * CROSS_ARROW * 0.8,
			base - dir * CROSS_ARROW * 0.6 - side * CROSS_ARROW * 0.8,
		]
	)


## A signed speed in m/s: one decimal under 10, else whole.
static func speed_text(mps: float) -> String:
	if absf(mps) < 0.05:
		return "+0.0 m/s"
	if absf(mps) < 9.95:
		return "%+.1f m/s" % mps
	return "%+d m/s" % roundi(mps)


## A bracket in the allegiance shape (a diamond for marks) with callsign and range;
## bolder when selected, a ring while pinged.
func _draw_marker(font: Font, e: Dictionary, selected: bool) -> void:
	var col: Color = Palette.item_color(e)
	var p: Vector2 = e["pos"]
	var r: float = 14.0 if selected else 10.0
	draw_polyline(Palette.shape_points(Palette.item_shape(e), p, r), col, 2.5 if selected else 1.2)
	var pulse: float = float(e["pulse"])
	if pulse > 0.0:
		draw_arc(p, r + 10.0 * (1.0 - pulse) + 4.0, 0.0, TAU, 24, Color(col, pulse), 2.0)
	var text: String = "%s %s" % [e["label"], _range(e["world"].length())]
	var at: Rect2 = label_rect(font, text, p, r)
	if at.position.x != p.x + r + 6.0 or at.position.y != p.y + 5.0 - font.get_ascent(FONT_SIZE):
		# Moved clear of something: a thin leader keeps it tied to its marker.
		var tip: Vector2 = Vector2(
			clampf(p.x, at.position.x, at.end.x), clampf(p.y, at.position.y, at.end.y)
		)
		draw_line(p, tip, Color(col, 0.5), 1.0)
	_text(font, at.position + Vector2(0.0, font.get_ascent(FONT_SIZE)), text, col)


## Where a marker's label goes (HUD coordinates): right of the marker, else the nearest spot
## clear of the marker and of `reserved()`; a label that fits nowhere clear stays on the
## right.
func label_rect(font: Font, text: String, p: Vector2, r: float) -> Rect2:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var h: float = font.get_height(FONT_SIZE)
	var right: Rect2 = Rect2(p + Vector2(r + 6.0, 5.0 - font.get_ascent(FONT_SIZE)), Vector2(w, h))
	var avoid: Array[Rect2] = reserved()
	if not _hits(right, avoid):
		return right
	var tries: Array[Rect2] = [
		Rect2(right.position - Vector2(w + 2.0 * r + 12.0, 0.0), right.size),
	]
	for a: Rect2 in avoid:
		for x: float in [a.position.x - w - 4.0, a.end.x + 4.0]:
			tries.append(Rect2(Vector2(x, right.position.y), right.size))
		for y: float in [a.position.y - h - 2.0, a.end.y + 2.0]:
			tries.append(Rect2(Vector2(right.position.x, y), right.size))
		# Beside a reserved box, nudged up or down off its neighbours.
		for x: float in [a.position.x - w - 4.0, a.end.x + 4.0]:
			for k: int in [-2, -1, 1, 2]:
				tries.append(Rect2(Vector2(x, right.position.y + k * h), right.size))
	var marker: Rect2 = Rect2(p - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6)
	var best: Rect2 = right
	var best_d: float = INF
	var inside: Rect2 = area()
	for t: Rect2 in tries:
		if _hits(t, avoid) or t.intersects(marker) or not inside.encloses(t):
			continue
		if not _leader_clear(p, t, avoid):
			continue
		if t.get_center().distance_to(p) < best_d:
			best_d = t.get_center().distance_to(p)
			best = t
	return best


## What marker labels keep clear of: the panel's shield ring (with its caption), the target
## compass (with its chip) and the flight read-out.
func reserved() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if (
		panel != null
		and panel.ring != null
		and panel.ring.visible
		and panel.ring.get_parent() == panel
	):
		out.append(panel.ring.get_rect().grow(2.0))
	out.append(_compass_rect())
	# The flight read-out: mode, speed, active modes and the three bars.
	out.append(readout_rect())
	out.append(thrust_rect())
	return out


## The flight read-out's box: mode, speed, active modes and the three bars.
func readout_rect() -> Rect2:
	var a: Rect2 = area()
	return Rect2(
		Vector2(a.position.x + 14.0, a.end.y - READOUT_H), Vector2(_bar_w() + 122.0, 130.0)
	)


func _compass_centre() -> Vector2:
	var a: Rect2 = area()
	if touch_layout():
		# Bottom right of the clear view, beside the read-out.
		return Vector2(a.end.x - 2.0 * COMPASS_R - 4.0, a.end.y - COMPASS_R - 40.0)
	return Vector2(300.0, size.y - COMPASS_R - 40.0)


## True when the leader from `p` to the label `box` crosses none of `avoid` (a box that
## holds `p` itself doesn't count).
static func _leader_clear(p: Vector2, box: Rect2, avoid: Array[Rect2]) -> bool:
	var tip: Vector2 = Vector2(
		clampf(p.x, box.position.x, box.end.x), clampf(p.y, box.position.y, box.end.y)
	)
	for a: Rect2 in avoid:
		if a.has_point(p):
			continue
		if a.has_point(tip):
			return false
		var corners: Array[Vector2] = [
			a.position,
			Vector2(a.end.x, a.position.y),
			a.end,
			Vector2(a.position.x, a.end.y),
		]
		for i: int in 4:
			if (
				Geometry2D.segment_intersects_segment(p, tip, corners[i], corners[(i + 1) % 4])
				!= null
			):
				return false
	return true


static func _hits(box: Rect2, others: Array[Rect2]) -> bool:
	for o: Rect2 in others:
		if box.intersects(o):
			return true
	return false


## Where a ray from the view centre along `dir` (screen axes) meets the edge inset by EDGE
## (on a phone, the edge of the view clear of the rails).
func _edge_point(dir: Vector2) -> Vector2:
	dir = dir.normalized() if dir.length() >= 1e-3 else Vector2.DOWN
	var c: Vector2 = size / 2.0
	if not touch_layout():
		var half: Vector2 = c - Vector2(EDGE, EDGE)
		var t: float = minf(half.x / maxf(absf(dir.x), 1e-6), half.y / maxf(absf(dir.y), 1e-6))
		return c + dir * t
	var box: Rect2 = area().grow(-EDGE)
	c = c.clamp(box.position, box.end)
	var tx: float = ((box.end.x if dir.x > 0.0 else box.position.x) - c.x) / dir.x
	var ty: float = ((box.end.y if dir.y > 0.0 else box.position.y) - c.y) / dir.y
	if absf(dir.x) < 1e-6:
		tx = INF
	if absf(dir.y) < 1e-6:
		ty = INF
	return c + dir * minf(tx, ty)


## An arrow tip moved off the read-outs, along the view's edge: the nearest spot on its
## edge clear of them (above or below on a side edge, beside on the top or bottom edge);
## where none is clear it stays.
func arrow_tip(tip: Vector2) -> Vector2:
	var a: Rect2 = area().grow(-EDGE)
	var keeps: Array[Rect2] = []
	for r: Rect2 in [readout_rect(), _compass_rect(), thrust_rect()]:
		keeps.append(r.grow(ARROW_CLEAR))
	if not keeps.any(func(k: Rect2) -> bool: return k.has_point(tip)):
		return tip
	var side: bool = is_equal_approx(tip.x, a.position.x) or is_equal_approx(tip.x, a.end.x)
	var best: Vector2 = tip
	var best_d: float = INF
	for k: Rect2 in keeps:
		var spots: Array[Vector2] = []
		if side:
			spots = [Vector2(tip.x, k.position.y - 1.0), Vector2(tip.x, k.end.y + 1.0)]
		else:
			spots = [Vector2(k.position.x - 1.0, tip.y), Vector2(k.end.x + 1.0, tip.y)]
		for p: Vector2 in spots:
			if (
				not a.grow(1.0).has_point(p)
				or keeps.any(func(q: Rect2) -> bool: return q.has_point(p))
			):
				continue
			if p.distance_to(tip) < best_d:
				best_d = p.distance_to(tip)
				best = p
	return best


func _compass_rect() -> Rect2:
	var c: Vector2 = _compass_centre()
	return Rect2(
		c - Vector2(2.0 * COMPASS_R, COMPASS_R), Vector2(4.0 * COMPASS_R, 2.0 * COMPASS_R + 24.0)
	)


## An arrow on the view's edge toward an item off screen or behind (FT-HLM-004).
func _draw_arrow(font: Font, e: Dictionary, selected: bool) -> void:
	var cam: Camera3D = panel.view3d.camera
	var d: Vector3 = cam.global_transform.basis.inverse() * (e["world"] as Vector3)
	var dir: Vector2 = Vector2(d.x, -d.y)
	dir = dir.normalized() if dir.length() >= 1e-3 else Vector2.DOWN
	var tip: Vector2 = _edge_point(dir)
	if touch_layout():
		tip = arrow_tip(tip)
	var side: Vector2 = dir.orthogonal() * 8.0
	var col: Color = Palette.item_color(e)
	var pts: PackedVector2Array = PackedVector2Array(
		[tip, tip - dir * 16.0 + side, tip - dir * 16.0 - side]
	)
	if selected:
		draw_colored_polygon(pts, col)
	else:
		pts.append(tip)
		draw_polyline(pts, col, 2.0)
	_text(font, tip - dir * 30.0 + Vector2(-10.0, 5.0), str(e["label"]), col)


## Target compass (FT-HLM-003): the selection's direction from the bow, filled ahead,
## hollow behind; its chip under it.
func _draw_compass(font: Font, c: Vector2) -> void:
	var dim: Color = Palette.color("text_dim")
	draw_circle(c, COMPASS_R, Color(Palette.color("background"), 0.6))
	draw_arc(c, COMPASS_R, 0.0, TAU, 40, Palette.color("line"), 2.0)
	draw_line(c - Vector2(5.0, 0.0), c + Vector2(5.0, 0.0), dim)
	draw_line(c - Vector2(0.0, 5.0), c + Vector2(0.0, 5.0), dim)
	var local: Variant = panel.ctx.selection_local()
	var label: String = tr("helm.no_selection")
	if local is Vector3:
		var p: Vector2 = c + compass_point(local, COMPASS_R - 6.0)
		var col: Color = Palette.item_color(_selected_item())
		if compass_filled(local):
			draw_circle(p, 5.0, col)
		else:
			draw_arc(p, 5.0, 0.0, TAU, 16, col, 2.0)
		label = ChipText.chip(selection_label(), local)
	var w: float = 4.0 * COMPASS_R
	draw_string(
		font,
		c + Vector2(-w / 2.0, COMPASS_R + 18.0),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		SMALL,
		Palette.color("text")
	)


## The compass dot's offset from the compass centre for an item at `local` (ship frame):
## the (x, y) of its unit direction, so dead ahead and dead astern are both centred.
static func compass_point(local: Vector3, r: float) -> Vector2:
	var dir: Vector3 = local.normalized()
	return Vector2(dir.x, -dir.y) * r


## Filled when the item is ahead of the beam (FT-HLM-003), hollow behind.
static func compass_filled(local: Vector3) -> bool:
	return local.z <= 0.0


## Assist or decoupled, speed and setpoint, active assist modes; with `full`, the
## thrust envelope and propellant bars.
func _draw_readout(font: Font, at: Vector2, full: bool) -> void:
	var h: Dictionary = panel.helm_block()
	var decoupled: bool = bool(h.get("decoupled", false))
	var mode: String = tr("helm.decoupled_mode") if decoupled else tr("helm.assist")
	_text(font, at, mode, Palette.color("warn") if decoupled else Palette.color("ok"))
	var speed: String = tr("helm.speed") % roundi(velocity().length())
	if not decoupled and full:
		speed += "  " + tr("helm.setpoint") % roundi(float(h.get("throttle_setpoint", 0.0)))
	_text(font, at + Vector2(0.0, 20.0), speed, Palette.color("text"))
	var modes: PackedStringArray = PackedStringArray()
	for m: Array in [
		["all_stop", "helm.all_stop"], ["approach", "helm.approach"], ["face", "helm.face"]
	]:
		if bool(h.get(m[0], false)):
			modes.append(tr(m[1]))
	if int(h.get("align", 0)) != 0:
		modes.append(tr("helm.align"))
	if int(h.get("jump_left", 0)) > 0:
		modes.append(tr("helm.jump_spool") % (float(h["jump_left"]) / NetCodec.TICK_HZ))
	if int(h.get("docked_site", -1)) >= 0:
		modes.append(tr("helm.docked"))
	if not modes.is_empty():
		_text(font, at + Vector2(0.0, 40.0), "  ".join(modes), Palette.color("accent"))
	if not full:
		return
	var y: float = at.y + 62.0
	_bar(font, Vector2(at.x, y), tr("helm.thrust"), float(h.get("thrust_scale", 1.0)), true)
	_bar(font, Vector2(at.x, y + 18.0), tr("helm.turn"), float(h.get("torque_scale", 1.0)), true)
	_bar(font, Vector2(at.x, y + 36.0), tr("helm.propellant"), panel.propellant_share(), false)


## A labelled bar: an envelope share (0..BAR_MAX, nominal ticked) or a 0..1 share;
## nothing for a negative value (unknown).
func _bar(font: Font, at: Vector2, label: String, value: float, envelope: bool) -> void:
	if value < 0.0:
		return
	_text(font, at + Vector2(0.0, 10.0), label, Palette.color("text_dim"), SMALL)
	var bar: Rect2 = Rect2(at + Vector2(48.0, 0.0), Vector2(_bar_w(), 10.0))
	var top: float = BAR_MAX if envelope else 1.0
	draw_rect(bar, Color(Palette.color("background"), 0.6))
	var fill: Rect2 = Rect2(bar.position, Vector2(bar.size.x * clampf(value / top, 0.0, 1.0), 10.0))
	var low: bool = value < (0.75 if envelope else 0.2)
	draw_rect(fill, Palette.color("warn") if low else Palette.color("ok"))
	draw_rect(bar, Palette.color("line"), false, 1.0)
	if envelope:
		var x: float = bar.position.x + bar.size.x / BAR_MAX
		draw_line(
			Vector2(x, bar.position.y - 2.0), Vector2(x, bar.end.y + 2.0), Palette.color("text")
		)
	_text(
		font,
		bar.position + Vector2(bar.size.x + 6.0, 10.0),
		"%d%%" % roundi(value * 100.0),
		Palette.color("text_dim"),
		SMALL
	)


## The controller radial: items clockwise from the top, the picked one lit.
func _draw_radial(font: Font) -> void:
	var c: Vector2 = size / 2.0
	var r: float = 120.0
	draw_circle(c, r + 40.0, Color(Palette.color("background"), 0.75))
	var n: int = HelmPanel.RADIAL.size()
	for i: int in n:
		var id: String = HelmPanel.RADIAL[i]
		var a: float = TAU * i / n - PI / 2.0
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
		var col: Color = Palette.color("text")
		if i == panel.radial_pick:
			col = Palette.color("accent")
			draw_circle(p, 34.0, Color(col, 0.25))
		var text: String = tr(IntentTable.label_key(id))
		draw_string(
			font, p + Vector2(-60.0, 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, SMALL, col
		)


## Own velocity (m/s, world axes) from KIN.
func velocity() -> Vector3:
	var v: Vector3i = panel.ctx.view.kin.get("vel", Vector3i.ZERO)
	return Vector3(v) / NetCodec.VEL_Q


## Own velocity in the ship frame (m/s): x starboard, y up, z astern (the bow is -Z).
func local_velocity() -> Vector3:
	return panel.ctx.interp.own_rotation().inverse() * velocity()


## The selection's label: a contact's callsign, a mark's name or a site's name.
func selection_label() -> String:
	var s: Dictionary = panel.ctx.crew.selection
	if s.get("kind", "") == "mark":
		return str(panel.ctx.crew.mark_in_slot(int(s["id"])).get("name", ""))
	if s.get("kind", "") == "site":
		return str(panel.ctx.picture().find(s).get("label", ""))
	return panel.ctx.view.callsign(int(s.get("id", -1)))


func _selected_item() -> Dictionary:
	var s: Dictionary = panel.ctx.crew.selection
	if s.get("kind", "") == "mark":
		return {"kind": "mark", "allegiance": ""}
	if s.get("kind", "") == "site":
		return {"kind": "site", "allegiance": ""}
	var info: Dictionary = panel.ctx.view.contacts.get("info", {})
	var letter: String = Palette.allegiance(selection_label())
	if int(info.get(int(s.get("id", -1)), [0])[0]) & ContactsSection.FLAG_OWN:
		letter = "F"
	return {"kind": "contact", "allegiance": letter}


## Exact range for markers (D114 keeps it off chips): "850 m", "2.3 km".
static func _range(m: float) -> String:
	if m < 1000.0:
		return String(TranslationServer.translate("helm.range_m")) % roundi(m)
	return String(TranslationServer.translate("helm.range_km")) % (m / 1000.0)


func _text(font: Font, at: Vector2, text: String, col: Color, fs: int = FONT_SIZE) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
