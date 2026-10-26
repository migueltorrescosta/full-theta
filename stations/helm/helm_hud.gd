class_name HelmHud
extends Control
## Helm's HUD over the 3D view (§5.1, S5's HUD with the station data): reticle,
## prograde and retrograde markers, brackets on contacts and diamonds on marks
## (allegiance colour and shape, FT-STN-006), off-screen arrows for the selection and
## pinged items (FT-HLM-004), the target compass (FT-HLM-003), the flight read-out
## (assist or decoupled, speed, setpoint, active assist modes), the thrust envelope and
## propellant (FT-HLM-012) and the controller radial. Compact (docked): compass and
## read-out only. Drawn every frame from the panel's context; never captures input.

const FONT_SIZE: int = 14
const SMALL: int = 12
## Off-screen arrows sit this far inside the view's edge.
const EDGE: float = 36.0
const COMPASS_R: float = 46.0
## Envelope bars show 0..BAR_MAX of nominal; a tick marks nominal.
const BAR_MAX: float = 1.5

var panel: HelmPanel
var compact: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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


# --- strand F ---
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


# --- end strand F ---
func _draw() -> void:
	if panel == null or panel.ctx == null:
		return
	var font: Font = get_theme_default_font()
	if compact:
		_draw_compass(font, Vector2(COMPASS_R + 12.0, size.y / 2.0 - 10.0))
		_draw_readout(font, Vector2(2.0 * COMPASS_R + 28.0, size.y / 2.0 - 24.0), false)
		return
	_draw_reticle()
	_draw_velocity()
	_draw_routes(font)
	_draw_lanes(font)  # strand F
	for e: Dictionary in markers():
		if e["on_screen"]:
			_draw_marker(font, e, e["selected"])
		elif e["arrow"]:
			_draw_arrow(font, e, e["selected"])
	_draw_compass(font, Vector2(300.0, size.y - COMPASS_R - 40.0))
	_draw_readout(font, Vector2(16.0, size.y - 150.0), true)
	if panel.chase:
		_text(font, Vector2(16.0, 24.0), tr("helm.chase"), Palette.color("text_dim"))
	if not panel.steering() and panel.ctx.matcher.device == IntentTable.KBM:
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


## Prograde (circle with ticks) and retrograde (circle with a cross).
func _draw_velocity() -> void:
	var v: Vector3 = velocity()
	if v.length() < 1.0:
		return
	var cam: Camera3D = panel.view3d.camera
	var col: Color = Palette.color("ok")
	for pro: bool in [true, false]:
		var p: Vector3 = v.normalized() * 5000.0 * (1.0 if pro else -1.0)
		if cam.is_position_behind(p):
			continue
		var s: Vector2 = cam.unproject_position(p)
		draw_arc(s, 8.0, 0.0, TAU, 20, col, 1.5)
		if pro:
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
				draw_line(s + d * 8.0, s + d * 14.0, col, 1.5)
		else:
			draw_line(s + Vector2(-6.0, -6.0), s + Vector2(6.0, 6.0), col, 1.5)
			draw_line(s + Vector2(-6.0, 6.0), s + Vector2(6.0, -6.0), col, 1.5)


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
	_text(font, p + Vector2(r + 6.0, 5.0), text, col)


## An arrow on the view's edge toward an item off screen or behind (FT-HLM-004).
func _draw_arrow(font: Font, e: Dictionary, selected: bool) -> void:
	var cam: Camera3D = panel.view3d.camera
	var d: Vector3 = cam.global_transform.basis.inverse() * (e["world"] as Vector3)
	var dir: Vector2 = Vector2(d.x, -d.y)
	if dir.length() < 1e-3:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var c: Vector2 = size / 2.0
	var half: Vector2 = c - Vector2(EDGE, EDGE)
	var t: float = minf(half.x / maxf(absf(dir.x), 1e-6), half.y / maxf(absf(dir.y), 1e-6))
	var tip: Vector2 = c + dir * t
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
	var bar: Rect2 = Rect2(at + Vector2(48.0, 0.0), Vector2(140.0, 10.0))
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
