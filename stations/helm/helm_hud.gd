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
## The least font size (sp) of a phone's read-outs (C7): the desktop sizes are too small there.
const PHONE_FONT: int = 16
## The envelope bars' percentage text and the gap before the bar need this much room (px).
const PCT_WIDTH: float = 42.0
const LABEL_GAP: float = 6.0
## Off-screen arrows sit this far inside the view's edge.
const EDGE: float = 36.0
## On a phone an arrow keeps this far (px) from the read-outs (its label sits beside it).
const ARROW_CLEAR: float = 14.0
## The height an edge arrow needs between two read-outs it keeps clear of.
const ARROW_ROOM: float = 2.0 * ARROW_CLEAR + 16.0
const COMPASS_R: float = 46.0
## The least gap (px) between the flight read-out's percentages and the compass disc.
const COMPASS_GAP: float = 12.0
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
const NARROW_WIDTH: float = 640.0
## A phone (portrait) keeps it top left.
const PHONE_WIDTH: float = 420.0
## A tablet view under this height takes the phone layout.
const TABLET_SHORT_H: float = 400.0
## The flight read-out's top edge, from the view's bottom.
const READOUT_H: float = 168.0
## Envelope bar length, and on a phone (narrower, so the compass fits beside the read-out).
const BAR_WIDTH: float = 140.0
const PHONE_BAR_WIDTH: float = 100.0
## The shortest bars on a phone, so the read-out ends left of the reticle.
const TIGHT_BAR_WIDTH: float = 60.0
## A label with no clear spot may cover up to this share of its area of something else.
const SLIGHT: float = 0.1
## A marker's label sits within this distance (px on screen) of the marker (D319).
const LABEL_REACH: float = 48.0

var panel: HelmPanel
var compact: bool = false

## This frame's markers and the labels placed so far: later labels keep clear of them.
var _placed: Array[Rect2] = []
## This frame's marker and velocity labels (tests check they keep clear).
var _labels: Array[Rect2] = []


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
	if panel == null:
		return false
	if panel.touch_ui != null:
		return true
	# A tablet's view between its rails is as small as a phone's on the classic iPad sizes
	# (332 px wide on 1024x768, 366 px tall on 768x1024): it takes the phone's layout then.
	return panel.tablet_ui != null and (size.x < PHONE_WIDTH or size.y < TABLET_SHORT_H)


## The font size (sp) of the read-outs: a phone's floor, else the desktop size.
func _fs() -> int:
	return maxi(FONT_SIZE, PHONE_FONT) if touch_layout() else FONT_SIZE


func _small() -> int:
	return PHONE_FONT if touch_layout() else SMALL


## The label key of a bar: "Max thrust" and "Max turn" on a desktop; a phone's 16 sp text
## leaves no room beside the compass for them, so it keeps the short "Thrust" and "Turn".
func _bar_key(key: String) -> String:
	if not touch_layout():
		return key
	return {"helm.max_thrust": "helm.thrust", "helm.max_turn": "helm.turn"}.get(key, key)


## The room (px) a bar's label before it and percentage after it take.
func _bar_extra() -> float:
	var font: Font = get_theme_default_font()
	var w: float = 0.0
	for key: String in ["helm.max_thrust", "helm.max_turn", "helm.propellant"]:
		var name: String = tr(_bar_key(key))
		w = maxf(w, font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, _small()).x)
	return ceilf(w) + LABEL_GAP + PCT_WIDTH


## Envelope bar length: on a phone short enough that the read-out ends left of the reticle
## (when they share rows), down to TIGHT_BAR_WIDTH.
func _bar_width() -> float:
	if not touch_layout():
		# The read-out shares its rows with the compass: its percentages end clear of it (w5).
		var room_x: float = _compass_centre().x - COMPASS_R - COMPASS_GAP - 14.0 - _bar_extra()
		return clampf(room_x, TIGHT_BAR_WIDTH, BAR_WIDTH)
	var a: Rect2 = area()
	var top: float = a.end.y - READOUT_H
	var ret: Rect2 = reticle_rect()
	if ret.end.y < top or ret.position.y > top + 130.0:
		if panel.tablet_ui == null:
			return PHONE_BAR_WIDTH
		# A tablet's narrow view: the bars end left of the compass at the bottom right.
		var left: float = a.end.x - 3.0 * COMPASS_R - 4.0 - COMPASS_GAP
		return clampf(left - (a.position.x + 14.0) - _bar_extra(), TIGHT_BAR_WIDTH, PHONE_BAR_WIDTH)
	var room: float = ret.position.x - 8.0 - (a.position.x + 14.0) - _bar_extra()
	return clampf(room, TIGHT_BAR_WIDTH, PHONE_BAR_WIDTH)


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
		if e["on_screen"]:
			e["pos"] = clear_of_readout(e["pos"])
		e["selected"] = panel.ctx.crew.is_selected(e["kind"], e["id"])
		# Off-screen arrows for the selection, pinged items and the priority target
		# (FT-HLM-004, gp-15).
		var lit: bool = e["selected"] or float(e["pulse"]) > 0.0 or e.get("priority", false)
		e["arrow"] = not e["on_screen"] and lit
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
## "time_left" (s until the window opens, or closes while open)}, only for lanes in front of the
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
		out.append({"pos": cam.unproject_position(world), "state": state, "time_left": left})
	return out


## A ring and a countdown at each lane's site: amber while the window is ahead, green inside
## it, red once it has closed.
func _draw_lanes(font: Font) -> void:
	var colours: Dictionary[String, String] = {"wait": "warn", "open": "ok", "late": "danger_text"}
	for lane: Dictionary in lane_marks():
		var col: Color = Palette.color(colours[lane["state"]])
		var at: Vector2 = lane["pos"]
		draw_arc(at, 18.0, 0.0, TAU, 28, col, 2.5)
		var text: String = tr("helm.lane." + String(lane["state"]))
		if lane["state"] != "late":
			text += " %d s" % ceili(float(lane["time_left"]))
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
	var all: Array[Dictionary] = markers()
	_placed.clear()
	_labels.clear()
	for e: Dictionary in all:
		if e["on_screen"]:
			_placed.append(_marker_box(e["pos"], 14.0 if e["selected"] else 10.0))
		elif e["arrow"]:
			_placed.append(_arrow_box(font, e))
	for m: Dictionary in velocity_markers():
		_placed.append(_marker_box(m["pos"], 14.0))
	_draw_thrust(font)
	_draw_routes(font)
	_draw_lanes(font)
	# The compass and read-out first: a marker passing behind them stays on top.
	var a: Rect2 = area()
	_draw_compass(font, _compass_centre())
	_draw_readout(font, Vector2(a.position.x + 16.0, a.end.y - 150.0), true)
	for e: Dictionary in all:
		if e["on_screen"]:
			_draw_marker(font, e, e["selected"])
		elif e["arrow"]:
			_draw_arrow(font, e, e["selected"])
	# The velocity labels go anywhere on the view (no reach): after the marker labels, which
	# must stay within reach of their markers (w-dcc: "Kappa 4.7 km" lost its range to "Drift").
	_draw_velocity(font)
	if panel.chase:
		_text(font, a.position + Vector2(16.0, 24.0), tr("helm.chase"), Palette.color("text_dim"))
	var tablet: bool = panel.tablet_ui != null
	if (
		not panel.steering()
		and panel.ctx.matcher.device == IntentTable.KBM
		and not (touch_layout() or tablet)
	):
		_text(font, Vector2(16.0, 44.0), tr("helm.pointer_free"), Palette.color("text_dim"))
	if panel.ctx.matcher.is_held("helm_radial"):
		_draw_radial(font)


## The reticle at the view's centre, for the read-outs to keep clear of.
func reticle_rect() -> Rect2:
	return Rect2(size / 2.0 - Vector2(22.0, 12.0), Vector2(44.0, 24.0))


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
		var clear: Vector2 = clear_of_readout(at)
		edge = edge or clear != at
		out.append({"kind": "pro" if pro else "retro", "pos": clear, "edge": edge})
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
		var at: Rect2 = label_rect(font, text, s, 14.0, INF)
		_placed.append(at)
		_labels.append(at)
		_text(font, at.position + Vector2(0.0, font.get_ascent(FONT_SIZE)), text, col)


## The translation input that lights the thrust arrows: x starboard +, y up +, z forward +.
func thrust_input() -> Vector3:
	var cmd: Dictionary = panel.input_command()
	return Vector3(cmd["strafe"], cmd["lift"], cmd["throttle"])


## The thrust cross's centre: beside the compass, clear of the ring.
func thrust_centre() -> Vector2:
	var a: Rect2 = area()
	if touch_layout():
		# A phone's view: top left of the part clear of the rails; in a shorter view (under
		# the screen's view-top row) at the top right, over the compass, so an edge arrow
		# fits between it and the read-out; in a short one (a joint view's switch below) bare.
		if _cross_right():
			var reach: Vector2 = (
				_cross_size(not cross_tight()) - Vector2(CROSS_ARM + 14.0, CROSS_ARM + 14.0)
			)
			return Vector2(a.end.x - reach.x - 4.0, a.position.y + CROSS_ARM + 20.0)
		return a.position + Vector2(CROSS_ARM + 22.0, 52.0)
	if size.x < PHONE_WIDTH:
		# A phone has no room beside the compass: top left, under the mode captions.
		return Vector2(CROSS_ARM + 22.0, 92.0)
	if size.x < NARROW_WIDTH:
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
	if not thrust_rect().has_area():
		return
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
	if cross_tight():
		return
	var l: Vector3 = local_velocity()
	var rows: Array = [
		[tr("helm.vel_fwd"), -l.z], [tr("helm.vel_side"), l.x], [tr("helm.vel_up"), l.y]
	]
	for i: int in rows.size():
		var text: String = "%s %s" % [rows[i][0], speed_text(float(rows[i][1]))]
		var at: Vector2 = c + Vector2(CROSS_ARM * 3.6, -14.0 + 16.0 * i)
		_text(font, at, text, Palette.color("text"), _small())


## The thrust cross and its read-outs, for the labels to keep clear of.
func thrust_rect() -> Rect2:
	var c: Vector2 = thrust_centre()
	var r: Rect2 = Rect2(
		c - Vector2(CROSS_ARM + 14.0, CROSS_ARM + 14.0), _cross_size(not cross_tight())
	)
	# A phone's view too short for it over the compass (a joint view under the view-top row
	# and the partner card): no cross; the read-out still gives the speed.
	if touch_layout() and _cross_right() and compass_boxes()[0].intersects(r):
		return Rect2()
	return r


## The thrust cross's box size: with the Fwd / Side / Up speeds beside it, or bare.
func _cross_size(speeds: bool) -> Vector2:
	var w: float = 250.0 if speeds else 2.0 * CROSS_ARM + 14.0 + 2.6 * CROSS_ARM + CROSS_ARROW
	return Vector2(w, 2.0 * CROSS_ARM + 28.0)


## True on a phone whose view is too short for the cross (with its speeds) at the top left
## above the flight read-out: the cross goes bare to the top right instead (#28).
func cross_tight() -> bool:
	return touch_layout() and area().size.y < 52.0 + CROSS_ARM + 14.0 + READOUT_H


## True on a phone whose view is too short for the thrust cross at the top left above the
## flight read-out with room for an edge arrow between them: the cross goes to the top right.
## A tablet keeps it top left: its shield ring and compass take the top right (w5).
func _cross_right() -> bool:
	var room: float = 52.0 + CROSS_ARM + 14.0 + READOUT_H + ARROW_ROOM
	return panel.touch_ui != null and area().size.y < room


## `p` moved just outside the flight read-out when it falls on it (a phone: a marker there
## would hide the bars); elsewhere unchanged.
func clear_of_readout(p: Vector2) -> Vector2:
	if not (touch_layout() or size.x < PHONE_WIDTH):
		return p
	var r: Rect2 = readout_rect().grow(ARROW_CLEAR)
	if not r.has_point(p):
		return p
	var spots: Array[Vector2] = [
		Vector2(r.end.x, p.y),
		Vector2(p.x, r.position.y),
		Vector2(p.x, r.end.y),
		Vector2(r.position.x, p.y)
	]
	var inside: Rect2 = area()
	var best: Vector2 = p
	var best_d: float = INF
	for q: Vector2 in spots:
		if inside.has_point(q) and q.distance_to(p) < best_d:
			best_d = q.distance_to(p)
			best = q
	return best


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
		ItemGlyph.ping_ring(self, p, r + 4.0, 10.0, pulse, col, 2.0, 24, false)
	if e.get("priority", false):
		ItemGlyph.draw_priority(self, p, r)
	var text: String = "%s %s" % [e["label"], _range(e["world"].length())]
	var at: Rect2 = label_rect(font, text, p, r)
	if _covers_something(at):
		# No clear spot near the marker for the range too: the callsign alone.
		var short: Rect2 = label_rect(font, str(e["label"]), p, r)
		if not _covers_something(short):
			text = str(e["label"])
			at = short
	_placed.append(at)
	_labels.append(at)
	if at.position.x != p.x + r + 6.0 or at.position.y != p.y + 5.0 - font.get_ascent(FONT_SIZE):
		# Moved clear of something: a thin leader keeps it tied to its marker.
		var tip: Vector2 = Vector2(
			clampf(p.x, at.position.x, at.end.x), clampf(p.y, at.position.y, at.end.y)
		)
		# From the bracket's edge to a little short of the text (w-dcc: at 150 % the stem ran
		# into the last letter).
		var d: Vector2 = tip - p
		if d.length() > r + 4.0:
			var u: Vector2 = d.normalized()
			draw_line(p + u * r, tip - u * 3.0, Color(col, 0.5), 1.0)
	_text(font, at.position + Vector2(0.0, font.get_ascent(FONT_SIZE)), text, col)


## True when `box` overlaps a reserved box or a label placed this frame.
func _covers_something(box: Rect2) -> bool:
	var avoid: Array[Rect2] = reserved()
	avoid.append_array(_placed)
	return CalloutLayout.hits(box, avoid)


## Where a marker's label goes (HUD coordinates): right of the marker, else the nearest spot
## within LABEL_REACH of it, clear of the marker, of `reserved()` and of this frame's other
## markers and labels; with none clear, the spot within reach that covers least. The label
## always stays inside the view.
func label_rect(font: Font, text: String, p: Vector2, r: float, reach: float = -1.0) -> Rect2:
	if reach < 0.0:
		reach = _label_reach()
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var h: float = font.get_height(FONT_SIZE)
	var right: Rect2 = Rect2(p + Vector2(r + 6.0, 5.0 - font.get_ascent(FONT_SIZE)), Vector2(w, h))
	var avoid: Array[Rect2] = reserved()
	avoid.append_array(_placed)
	var inside: Rect2 = area()
	if not CalloutLayout.hits(right, avoid) and inside.encloses(right):
		return right
	# (a marker outside the view's clear area, under the view-top row, has no near spot)
	if not inside.has_point(p):
		reach = INF
	var tries: Array[Rect2] = [
		Rect2(right.position - Vector2(w + 2.0 * r + 12.0, 0.0), right.size),
		Rect2(Vector2(p.x - w / 2.0, p.y - 1.3 * r - h - 2.0), right.size),
		Rect2(Vector2(p.x - w / 2.0, p.y + 1.3 * r + 2.0), right.size),
	]
	# Round the marker: eight directions, up to three lines out, all within LABEL_REACH.
	for step: int in 3:
		var d: float = 1.3 * r + 2.0 + step * h
		for dir: Vector2 in [
			Vector2(1, 0),
			Vector2(-1, 0),
			Vector2(0, -1),
			Vector2(0, 1),
			Vector2(1, -1),
			Vector2(-1, -1),
			Vector2(1, 1),
			Vector2(-1, 1),
		]:
			var corner: Vector2 = p + dir * d
			var x0: float = (
				corner.x if dir.x > 0.0 else (corner.x - w if dir.x < 0.0 else p.x - w / 2.0)
			)
			var y0: float = (
				corner.y if dir.y > 0.0 else (corner.y - h if dir.y < 0.0 else p.y - h / 2.0)
			)
			tries.append(Rect2(Vector2(x0, y0), right.size))
	for a: Rect2 in avoid:
		for x: float in [a.position.x - w - 4.0, a.end.x + 4.0]:
			tries.append(Rect2(Vector2(x, right.position.y), right.size))
		for y: float in [a.position.y - h - 2.0, a.end.y + 2.0]:
			tries.append(Rect2(Vector2(right.position.x, y), right.size))
			# Centred on the marker: under or over a box the marker sits in or beside.
			tries.append(Rect2(Vector2(p.x - w / 2.0, y), right.size))
		# Beside a reserved box, nudged up or down off its neighbours.
		for x: float in [a.position.x - w - 4.0, a.end.x + 4.0]:
			for k: int in [-2, -1, 1, 2]:
				tries.append(Rect2(Vector2(x, right.position.y + k * h), right.size))
	var marker: Rect2 = _marker_box(p, r)
	var best: Rect2 = right
	var best_d: float = INF
	# No clear spot (a crowded phone view): the spot overlapping least, if only slightly.
	var least: Rect2 = Rect2(
		right.position.clamp(inside.position, (inside.end - right.size).max(inside.position)),
		right.size
	)
	var least_cover: float = INF
	for t: Rect2 in tries:
		# Kept inside the view: a label near the edge slides in rather than giving up.
		t.position = t.position.clamp(inside.position, (inside.end - t.size).max(inside.position))
		if (
			t.intersects(marker)
			or not inside.encloses(t)
			or not CalloutLayout.leader_clear(p, t, avoid)
		):
			continue
		if CalloutLayout.gap_to(t, p) > reach:
			continue
		var cover: float = 0.0
		for a: Rect2 in avoid:
			cover += t.intersection(a).get_area()
		if cover > 0.0:
			if cover < least_cover:
				least_cover = cover
				least = t
			continue
		if t.get_center().distance_to(p) < best_d:
			best_d = t.get_center().distance_to(p)
			best = t
	return best if best_d < INF else least


## LABEL_REACH in this HUD's units: the screen px of the rule shrink with a UI scale.
func _label_reach() -> float:
	var scale: float = get_window().content_scale_factor if is_inside_tree() else 1.0
	return LABEL_REACH / maxf(scale, 1.0)


## A marker's box at `p` for a bracket of radius `r`.
static func _marker_box(p: Vector2, r: float) -> Rect2:
	return Rect2(p - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6)


## What marker labels keep clear of: the panel's shield ring (with its caption), a tablet's
## radar inset, the target compass (with its chip) and the flight read-out.
func reserved() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _ring_rect().has_area():
		out.append(_ring_rect().grow(2.0))
	if _inset_rect().has_area():
		out.append(_inset_rect().grow(2.0))
	out.append_array(compass_boxes())
	# The flight read-out, line by line: a label may sit in the gap under the speed line
	# while no assist mode is on (w-dcc: "Kappa 4.7 km" kept its range there).
	out.append_array(_readout_lines())
	out.append(thrust_rect())
	return out


## A tablet's radar inset in this HUD's coordinates while it shows (C14), else empty.
func _inset_rect() -> Rect2:
	if panel == null or not panel.radar_inset_rect().has_area():
		return Rect2()
	var xf: Transform2D = get_global_transform().affine_inverse() * panel.get_global_transform()
	return xf * panel.radar_inset_rect()


## The shield ring's box in this HUD's coordinates while it sits on the view, else empty.
func _ring_rect() -> Rect2:
	if (
		panel == null
		or panel.ring == null
		or not panel.ring.visible
		or panel.ring.get_parent() != panel
	):
		return Rect2()
	return get_global_transform().affine_inverse() * panel.ring.get_global_rect()


## The flight read-out's drawn lines (mode, speed, the active modes when any, the bars), each
## as wide as its text, inside readout_rect().
func _readout_lines() -> Array[Rect2]:
	var font: Font = get_theme_default_font()
	var a: Rect2 = area()
	var at: Vector2 = Vector2(a.position.x + 16.0, a.end.y - 150.0)
	var fs: int = _fs()
	var h: Dictionary = panel.helm_block() if panel != null and panel.ctx != null else {}
	var texts: Array[String] = [
		tr("helm.decoupled_mode") if bool(h.get("decoupled", false)) else tr("helm.assist"),
		(tr("helm.speed") % 9999) + "  " + tr("helm.setpoint") % 9999,
	]
	var on: bool = (
		["all_stop", "approach", "face"].any(func(k: String) -> bool: return bool(h.get(k, false)))
		or int(h.get("align", 0)) != 0
		or int(h.get("jump_left", 0)) > 0
		or int(h.get("docked_site", -1)) >= 0
	)
	var out: Array[Rect2] = []
	var full: Rect2 = readout_rect()
	for i: int in 3:
		if i == 2 and not on:
			continue
		var w: float = full.size.x
		if i < texts.size():
			w = font.get_string_size(texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
		var top: float = at.y + 20.0 * i - font.get_ascent(fs)
		out.append(Rect2(full.position.x, top, minf(w, full.size.x), font.get_height(fs)))
	var bars: float = at.y + 62.0 - 4.0
	out.append(Rect2(full.position.x, bars, full.size.x, full.end.y - bars))
	return out


## The flight read-out's box: mode, speed, active modes and the three bars.
func readout_rect() -> Rect2:
	var a: Rect2 = area()
	return Rect2(
		Vector2(a.position.x + 14.0, a.end.y - READOUT_H),
		Vector2(_bar_width() + _bar_extra(), 130.0)
	)


func _compass_centre() -> Vector2:
	var a: Rect2 = area()
	if touch_layout():
		# Bottom right of the clear view, beside the read-out.
		return Vector2(a.end.x - 2.0 * COMPASS_R - 4.0, a.end.y - COMPASS_R - 40.0)
	return Vector2(300.0, size.y - COMPASS_R - 40.0)


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


## An arrow tip moved off the read-outs, the shield ring and the velocity markers, along the view's
## edge: the nearest spot on its edge clear of them (above or below on a side edge, beside on the
## top or bottom edge); where none is clear it stays. Used on a phone.
func arrow_tip(tip: Vector2) -> Vector2:
	var a: Rect2 = area().grow(-EDGE)
	# A view not yet laid out is narrower than two edges: nothing to move along.
	if not a.has_area():
		return tip
	var keeps: Array[Rect2] = []
	for r: Rect2 in [readout_rect(), thrust_rect(), _ring_rect()] + compass_boxes():
		if r.has_area():
			keeps.append(r.grow(ARROW_CLEAR))
	# Nor on the velocity markers (w-dcc: "H2" sat on the Drift reticle).
	for m: Dictionary in velocity_markers():
		# (with room for the arrow's label, which sits 30 px back from its tip)
		keeps.append(_marker_box(m["pos"], 14.0).grow(ARROW_CLEAR + 16.0))
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


## The target compass's disc and its chip, which on a phone sits on the side of the disc the
## selection's dot is on, so the chip stays near the dot (D319).
func compass_boxes() -> Array[Rect2]:
	var c: Vector2 = _compass_centre()
	var chip_y: float = -COMPASS_R - 24.0 if _chip_above() else COMPASS_R
	# (the chip is centred under the disc: its box is as wide as its text, w-dcc)
	var font: Font = get_theme_default_font()
	var w: float = minf(
		font.get_string_size(_compass_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, _small()).x + 8.0,
		4.0 * COMPASS_R
	)
	return [
		Rect2(c - Vector2(COMPASS_R, COMPASS_R), Vector2(2.0, 2.0) * COMPASS_R),
		Rect2(c + Vector2(-w / 2.0, chip_y), Vector2(w, 24.0)),
	]


## The compass chip's text: the selection's callout, or "Nothing selected".
func _compass_label() -> String:
	if panel == null or panel.ctx == null:
		return tr("helm.no_selection")
	var local: Variant = panel.ctx.selection_local()
	if local is Vector3:
		return CalloutText.callout(selection_label(), local)
	return tr("helm.no_selection")


## True when, on a phone, the selection's compass dot is in the disc's upper half: its chip
## goes above (the desktop has no room there: the reticle's caption), unless the shield ring's
## caption sits there (a short tablet view, w5).
func _chip_above() -> bool:
	if not touch_layout():
		return false
	var local: Variant = panel.ctx.selection_local()
	if not (local is Vector3 and compass_point(local, COMPASS_R - 6.0).y < 0.0):
		return false
	var c: Vector2 = _compass_centre()
	var above: Rect2 = Rect2(
		c + Vector2(-2.0 * COMPASS_R, -COMPASS_R - 24.0), Vector2(4.0 * COMPASS_R, 24.0)
	)
	return not above.intersects(_ring_rect().grow(4.0))


## An off-screen item's arrow: its direction on the view and its tip on the edge.
func _arrow(e: Dictionary) -> Array[Vector2]:
	var cam: Camera3D = panel.view3d.camera
	var d: Vector3 = cam.global_transform.basis.inverse() * (e["world"] as Vector3)
	var dir: Vector2 = Vector2(d.x, -d.y)
	dir = dir.normalized() if dir.length() >= 1e-3 else Vector2.DOWN
	var tip: Vector2 = _edge_point(dir)
	if touch_layout() or size.x < PHONE_WIDTH:
		tip = arrow_tip(tip)
	# Never on a tablet's radar inset (C14): an arrow there slides along its edge to just
	# below the inset or left of it, its label with it.
	var inset: Rect2 = _inset_rect()
	if inset.has_area():
		# (then off the shield ring under it, the same way)
		for box: Rect2 in [inset, _ring_rect()]:
			var keep: Rect2 = box.grow(30.0 + 16.0)
			if box.has_area() and keep.has_point(tip):
				# (whichever way is shorter)
				if keep.end.y - tip.y < tip.x - keep.position.x:
					tip.y = keep.end.y
				else:
					tip.x = keep.position.x
	return [dir, tip]


## The box an arrow and its label cover, for marker labels to keep clear of.
func _arrow_box(font: Font, e: Dictionary) -> Rect2:
	var a: Array[Vector2] = _arrow(e)
	var at: Vector2 = a[1] - a[0] * 30.0 + Vector2(-10.0, 5.0 - font.get_ascent(FONT_SIZE))
	var w: float = font.get_string_size(str(e["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var label: Rect2 = Rect2(at, Vector2(w, font.get_height(FONT_SIZE)))
	return label.expand(a[1]).expand(a[1] - a[0] * 16.0).grow(2.0)


## An arrow on the view's edge toward an item off screen or behind (FT-HLM-004).
func _draw_arrow(font: Font, e: Dictionary, selected: bool) -> void:
	var a: Array[Vector2] = _arrow(e)
	var dir: Vector2 = a[0]
	var tip: Vector2 = a[1]
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
	var label: String = _compass_label()
	if local is Vector3:
		var p: Vector2 = c + compass_point(local, COMPASS_R - 6.0)
		var col: Color = Palette.item_color(_selected_item())
		if compass_filled(local):
			draw_circle(p, 5.0, col)
		else:
			draw_arc(p, 5.0, 0.0, TAU, 16, col, 2.0)
	var w: float = 4.0 * COMPASS_R
	var chip_dy: float = -COMPASS_R - 8.0 if _chip_above() else COMPASS_R + 18.0
	Palette.draw_outlined(
		self,
		font,
		c + Vector2(-w / 2.0, chip_dy),
		label,
		_small(),
		Palette.color("text"),
		w,
		HORIZONTAL_ALIGNMENT_CENTER
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
	var fs: int = _fs()
	var mode: String = tr("helm.decoupled_mode") if decoupled else tr("helm.assist")
	if decoupled:
		# A filled amber tag: the mode that turns the assists off is not missed (C7).
		var tag: Vector2 = font.get_string_size(mode, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var top: float = at.y - font.get_ascent(fs) - 2.0
		draw_rect(Rect2(at.x - 4.0, top, tag.x + 8.0, tag.y + 4.0), Palette.color("warn"))
		_text(font, at, mode, Palette.color("background"), fs)
	else:
		_text(font, at, mode, Palette.color("ok"), fs)
	var speed: String = tr("helm.speed") % roundi(velocity().length())
	if not decoupled and full:
		speed += "  " + tr("helm.setpoint") % roundi(float(h.get("throttle_setpoint", 0.0)))
	_text(font, at + Vector2(0.0, 20.0), speed, Palette.color("text"), fs)
	var modes: PackedStringArray = PackedStringArray()
	for m: Array in [
		["all_stop", "helm.all_stop"], ["approach", "helm.approach"], ["face", "helm.face"]
	]:
		if bool(h.get(m[0], false)):
			modes.append(tr(m[1]))
	if int(h.get("align", 0)) != 0:
		modes.append(tr("helm.align"))
	if int(h.get("jump_left", 0)) > 0:
		modes.append(tr("helm.jump_spool") % (float(h["jump_left"]) / NetCodec.TICK_RATE))
	if int(h.get("docked_site", -1)) >= 0:
		modes.append(tr("helm.docked"))
	if not modes.is_empty():
		_text(font, at + Vector2(0.0, 40.0), "  ".join(modes), Palette.color("accent"), fs)
	if not full:
		return
	var y: float = at.y + 62.0
	var pitch: float = 20.0 if touch_layout() else 18.0
	_bar(
		font,
		Vector2(at.x, y),
		tr(_bar_key("helm.max_thrust")),
		float(h.get("thrust_scale", 1.0)),
		true
	)
	_bar(
		font,
		Vector2(at.x, y + pitch),
		tr(_bar_key("helm.max_turn")),
		float(h.get("torque_scale", 1.0)),
		true
	)
	_bar(
		font, Vector2(at.x, y + 2.0 * pitch), tr("helm.propellant"), panel.propellant_share(), false
	)


## A labelled bar: an envelope share (0..BAR_MAX, nominal ticked) or a 0..1 share;
## nothing for a negative value (unknown). Fuel turns amber under a fifth and red under a
## tenth, its percentage with it.
func _bar(font: Font, at: Vector2, label: String, value: float, envelope: bool) -> void:
	if value < 0.0:
		return
	var fs: int = _small()
	var label_width: float = _bar_extra() - PCT_WIDTH
	_text(font, at + Vector2(0.0, 10.0 + (fs - SMALL) / 2.0), label, Palette.color("text_dim"), fs)
	var bar: Rect2 = Rect2(at + Vector2(label_width, 0.0), Vector2(_bar_width(), 10.0))
	var top: float = BAR_MAX if envelope else 1.0
	draw_rect(bar, Color(Palette.color("background"), 0.6))
	var fill: Rect2 = Rect2(bar.position, Vector2(bar.size.x * clampf(value / top, 0.0, 1.0), 10.0))
	var low: bool = value < (0.75 if envelope else StationContext.FUEL_LOW)
	var critical: bool = not envelope and value < StationContext.FUEL_ALMOST_GONE
	var fill_role: String = "danger_text" if critical else ("warn" if low else "ok")
	draw_rect(fill, Palette.color(fill_role))
	draw_rect(bar, Palette.color("line"), false, 1.0)
	if envelope:
		var x: float = bar.position.x + bar.size.x / BAR_MAX
		draw_line(
			Vector2(x, bar.position.y - 2.0), Vector2(x, bar.end.y + 2.0), Palette.color("text")
		)
	_text(
		font,
		bar.position + Vector2(bar.size.x + 6.0, 10.0 + (fs - SMALL) / 2.0),
		"%d%%" % roundi(value * 100.0),
		Palette.color(fill_role) if low and not envelope else Palette.color("text_dim"),
		fs
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
	var v: Vector3i = panel.ctx.snap.kin.get("vel", Vector3i.ZERO)
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
	return panel.ctx.snap.callsign(int(s.get("id", -1)))


func _selected_item() -> Dictionary:
	var s: Dictionary = panel.ctx.crew.selection
	if s.get("kind", "") == "mark":
		return {"kind": "mark", "allegiance": ""}
	if s.get("kind", "") == "site":
		return {"kind": "site", "allegiance": ""}
	var info: Dictionary = panel.ctx.snap.contacts.get("info", {})
	var letter: String = Palette.allegiance(selection_label())
	if int(info.get(int(s.get("id", -1)), [0])[0]) & SnapshotReader.FLAG_OWN:
		letter = "F"
	return {"kind": "contact", "allegiance": letter}


## Exact range for markers (D114 keeps it off chips): "850 m", "2.3 km".
static func _range(m: float) -> String:
	if m < 1000.0:
		return String(TranslationServer.translate("helm.range_m")) % roundi(m)
	return String(TranslationServer.translate("helm.range_km")) % (m / 1000.0)


func _text(font: Font, at: Vector2, text: String, col: Color, fs: int = FONT_SIZE) -> void:
	Palette.draw_outlined(self, font, at, text, fs, col)
