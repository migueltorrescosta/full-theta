class_name S5Hud
extends Control
## Helm HUD for the prototype: markers on the view (prograde, item brackets, the
## ecliptic horizon), contact chips in the ship frame (FT-SPA-003, FT-SPA-026), flight
## status, the target compass, the disc radar and the help overlay.

const HOSTILE: Color = Color(1.0, 0.6, 0.2)
const FRIENDLY: Color = Color(0.35, 0.8, 1.0)
const MARK: Color = Color(1.0, 0.9, 0.45)
const TEXT: Color = Color(0.9, 0.93, 0.97)
const DIM: Color = Color(0.6, 0.66, 0.72)
const ACTIVE: Color = Color(0.45, 1.0, 0.55)
const HELP_TITLE: String = "Catch H2 (orange) within 100 m, or bring us to Bravo and stop."
## [keys, what it does] pairs, laid out in two columns.
const HELP: Array[Array] = [
	["Mouse, arrows", "turn (the nose follows the mouse)"],
	["Q / E", "roll"],
	["W / S", "speed up / down (assist holds it)"],
	["A D / R V", "slide sideways / up and down"],
	["F (hold)", "face the selected thing"],
	["X (hold)", "approach it, stop 500 m off"],
	["Space", "all stop"],
	["Tab", "assist on / off (decoupled)"],
	["L", "level (press again: flatten pitch too)"],
	["T", "select next: H2, Bravo, F1"],
	["M", "put Bravo 5 km ahead (Shift+M: here)"],
	["Z", "radar range 2 / 10 / 50 km"],
	["C", "chase camera"],
	["I", "invert pitch"],
	["Backspace", "restart"],
	["F11 / Esc", "fullscreen / free the mouse"],
]
const HELP_PAD: Array[String] = [
	"Controller: left stick turns (hold LB to roll), right stick slides, triggers set speed.",
	"Hold L3 face, hold B approach, View+B all stop, View+A assist on/off, View+X level,",
	"X select, A Bravo ahead, Y chase camera, d-pad up radar range, View+Start restart.",
	"H or F1 (Start) hides this.",
]

var proto: S5HelmPrototype
var _compass: S5Compass
var _radar: S5Radar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass = S5Compass.new()
	_compass.size = Vector2(110.0, 110.0)
	add_child(_compass)
	_radar = S5Radar.new()
	_radar.size = Vector2(340.0, 200.0)
	add_child(_radar)


func _process(_delta: float) -> void:
	_compass.position = Vector2(size.x * 0.5 - 300.0, size.y - 150.0)
	_radar.position = Vector2(size.x - 360.0, size.y - 215.0)
	_update_widgets()
	queue_redraw()
	_compass.queue_redraw()
	_radar.queue_redraw()


func _colour(it: S5Item) -> Color:
	if it.kind == S5Item.Kind.MARK:
		return MARK
	return HOSTILE if it.name.begins_with("H") else FRIENDLY


func _update_widgets() -> void:
	var world: S5World = proto.world
	var ship: S5ShipBody = world.ship
	var sel: S5Item = world.selected_item()
	var rel: Vector3 = sel.position - ship.position
	_compass.direction = ship.to_local(rel).normalized()
	_compass.colour = _colour(sel)
	_compass.label = sel.name
	_radar.range_m = proto.radar_range()
	_radar.contacts.clear()
	for i: int in world.items.size():
		var it: S5Item = world.items[i]
		(
			_radar
			. contacts
			. append(
				{
					"name": it.name,
					"local": ship.to_local(it.position - ship.position),
					"colour": _colour(it),
					"mark": it.kind == S5Item.Kind.MARK,
					"selected": i == world.helm.selected,
				}
			)
		)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var world: S5World = proto.world
	var ship: S5ShipBody = world.ship
	var cam: Camera3D = proto.camera
	var centre: Vector2 = size * 0.5

	_draw_horizon(cam)
	if not proto.chase:
		draw_arc(centre, 10.0, 0.0, TAU, 24, Color(TEXT, 0.7), 1.5)
		draw_line(centre + Vector2(-22.0, 0.0), centre + Vector2(-12.0, 0.0), Color(TEXT, 0.7), 1.5)
		draw_line(centre + Vector2(12.0, 0.0), centre + Vector2(22.0, 0.0), Color(TEXT, 0.7), 1.5)
	# Mouse virtual stick.
	var ms: Vector2 = proto.mapper.mouse_stick
	if ms.length() > 0.02:
		draw_circle(centre + ms * 80.0, 3.0, Color(ACTIVE, 0.8))
	# Prograde (circle with ticks) and retrograde (circle with a cross).
	if ship.velocity.length() > 1.0:
		var v: Vector3 = ship.velocity.normalized() * 5000.0
		_vel_marker(cam, cam.global_position + v, true)
		_vel_marker(cam, cam.global_position - v, false)

	for i: int in world.items.size():
		_item_marker(world.items[i], i == world.helm.selected, cam, font)

	_draw_chips(font)
	_draw_status(font)
	if proto.show_help:
		_draw_help(font)


func _draw_horizon(cam: Camera3D) -> void:
	# The ecliptic: a ring of points around the ship in the world's horizontal plane.
	var prev: Vector2 = Vector2.INF
	for i: int in 73:
		var a: float = TAU * i / 72.0
		var p: Vector3 = cam.global_position + Vector3(cos(a), 0.0, sin(a)) * 10000.0
		if cam.is_position_behind(p):
			prev = Vector2.INF
			continue
		var s: Vector2 = cam.unproject_position(p)
		if prev != Vector2.INF:
			draw_line(prev, s, Color(0.4, 0.6, 0.75, 0.35), 1.0)
		prev = s


func _vel_marker(cam: Camera3D, p: Vector3, pro: bool) -> void:
	if cam.is_position_behind(p):
		return
	var s: Vector2 = cam.unproject_position(p)
	var col: Color = Color(ACTIVE, 0.9)
	draw_arc(s, 8.0, 0.0, TAU, 20, col, 1.5)
	if pro:
		draw_line(s + Vector2(-8.0, 0.0), s + Vector2(-14.0, 0.0), col, 1.5)
		draw_line(s + Vector2(8.0, 0.0), s + Vector2(14.0, 0.0), col, 1.5)
		draw_line(s + Vector2(0.0, -8.0), s + Vector2(0.0, -14.0), col, 1.5)
	else:
		draw_line(s + Vector2(-6.0, -6.0), s + Vector2(6.0, 6.0), col, 1.5)
		draw_line(s + Vector2(-6.0, 6.0), s + Vector2(6.0, -6.0), col, 1.5)


func _item_marker(it: S5Item, selected: bool, cam: Camera3D, font: Font) -> void:
	if cam.is_position_behind(it.position):
		return
	var s: Vector2 = cam.unproject_position(it.position)
	var col: Color = _colour(it)
	var w: float = 2.5 if selected else 1.2
	var d: float = 14.0 if selected else 10.0
	if it.kind == S5Item.Kind.MARK:
		var pts: PackedVector2Array = PackedVector2Array(
			[
				s + Vector2(0, -d),
				s + Vector2(d, 0),
				s + Vector2(0, d),
				s + Vector2(-d, 0),
				s + Vector2(0, -d)
			]
		)
		draw_polyline(pts, col, w)
	else:
		draw_rect(Rect2(s - Vector2(d, d), Vector2(d, d) * 2.0), col, false, w)
	var dist: float = (it.position - proto.world.ship.position).length()
	var text: String = "%s %s" % [it.name, S5Callout.range_text(dist)]
	draw_string(font, s + Vector2(d + 4.0, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _draw_chips(font: Font) -> void:
	var world: S5World = proto.world
	var ship: S5ShipBody = world.ship
	var y: float = 30.0
	draw_string(
		font,
		Vector2(size.x - 330.0, y),
		"CONTACTS (ship frame)",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		DIM
	)
	for i: int in world.items.size():
		y += 24.0
		var it: S5Item = world.items[i]
		var rel: Vector3 = it.position - ship.position
		var closing: float = -(it.velocity - ship.velocity).dot(rel.normalized())
		var label: String = ("<>" + it.name) if it.kind == S5Item.Kind.MARK else it.name
		var chip: String = S5Callout.chip(label, ship.to_local(rel), closing)
		var sel: bool = i == world.helm.selected
		var box: Rect2 = Rect2(Vector2(size.x - 336.0, y - 16.0), Vector2(320.0, 22.0))
		draw_rect(box, Color(0.0, 0.0, 0.0, 0.5))
		if sel:
			draw_rect(box, _colour(it), false, 2.0)
		draw_string(
			font, Vector2(size.x - 330.0, y), chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, _colour(it)
		)


func _draw_status(font: Font) -> void:
	var world: S5World = proto.world
	var ship: S5ShipBody = world.ship
	var helm: S5HelmState = world.helm
	var inp: S5HelmInput = proto.last_input
	var lines: Array[Array] = []
	var mode: String = "DECOUPLED" if helm.decoupled else "ASSIST on"
	lines.append([mode, Color(1.0, 0.5, 0.4) if helm.decoupled else ACTIVE])
	var fwd: float = ship.velocity.dot(ship.forward())
	lines.append(["speed %.0f m/s (forward %.0f)" % [ship.velocity.length(), fwd], TEXT])
	if not helm.decoupled:
		lines.append(["throttle set %.0f m/s" % helm.throttle_setpoint, TEXT])
	var pct: float = 100.0 * ship.propellant / S5ShipBody.new().propellant
	lines.append(["propellant %.0f %%" % pct, TEXT])
	var active: PackedStringArray = PackedStringArray()
	if helm.all_stop:
		active.append("ALL STOP")
	if inp.approach:
		active.append("APPROACH")
	elif inp.face:
		active.append("FACE")
	if helm.level == S5HelmState.Level.ROLL:
		active.append("LEVEL roll")
	elif helm.level == S5HelmState.Level.ROLL_AND_PITCH:
		active.append("LEVEL roll+pitch")
	if active.is_empty():
		lines.append(["no assist mode active", DIM])
	else:
		lines.append([" ".join(active), ACTIVE])
	lines.append(["selected: %s" % world.selected_item().name, TEXT])
	var timer: String = "H2 intercept: %.1f s" % world.time
	if proto.intercept_time >= 0.0:
		timer = "H2 intercepted at %.1f s" % proto.intercept_time
	lines.append([timer, MARK])
	if proto.autopilot != null:
		lines.append(["AUTOPILOT demo", MARK])
	var y: float = size.y - 30.0 - 22.0 * lines.size()
	draw_rect(
		Rect2(Vector2(12.0, y - 20.0), Vector2(300.0, 22.0 * lines.size() + 14.0)),
		Color(0, 0, 0, 0.5)
	)
	for l: Array in lines:
		draw_string(font, Vector2(20.0, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, l[1])
		y += 22.0
	_draw_thrust(font, Vector2(330.0, size.y - 120.0))
	draw_string(
		font,
		Vector2(20.0, 26.0),
		"HELM  S5 prototype   H: help",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		DIM
	)


## Thrust envelope use per axis: how much of each axis' limit this tick's command uses.
func _draw_thrust(font: Font, at: Vector2) -> void:
	var ship: S5ShipBody = proto.world.ship
	var cmd: S5ThrustCommand = proto.world.last_command
	var rows: Array[Array] = [
		[
			"fwd",
			-cmd.force.z / (ship.max_thrust_neg.z if cmd.force.z < 0.0 else ship.max_thrust_pos.z)
		],
		["side", cmd.force.x / ship.max_thrust_pos.x],
		["vert", cmd.force.y / ship.max_thrust_pos.y],
		["rot", cmd.torque.length() / ship.max_torque.length()],
	]
	for r: Array in rows:
		draw_string(font, at + Vector2(0.0, 10.0), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		var bar: Rect2 = Rect2(at + Vector2(36.0, 0.0), Vector2(100.0, 10.0))
		draw_rect(bar, Color(0, 0, 0, 0.5))
		var v: float = clampf(r[1], -1.0, 1.0)
		var mid: float = bar.position.x + 50.0
		draw_rect(
			Rect2(Vector2(minf(mid, mid + v * 50.0), at.y), Vector2(absf(v) * 50.0, 10.0)), ACTIVE
		)
		draw_rect(bar, DIM, false, 1.0)
		at.y += 16.0


func _draw_help(font: Font) -> void:
	var rows: int = ceili(HELP.size() / 2.0)
	var h: float = 60.0 + 20.0 * rows + 20.0 * HELP_PAD.size()
	var box: Rect2 = Rect2(Vector2(size.x * 0.5 - 400.0, 60.0), Vector2(800.0, h))
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.75))
	var x: float = box.position.x + 16.0
	var y: float = box.position.y + 26.0
	draw_string(font, Vector2(x, y), HELP_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MARK)
	for i: int in HELP.size():
		var col: float = x + (i % 2) * 392.0
		var row: float = y + 26.0 + 20.0 * floori(i / 2.0)
		draw_string(font, Vector2(col, row), HELP[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACTIVE)
		draw_string(
			font, Vector2(col + 110.0, row), HELP[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT
		)
	y += 36.0 + 20.0 * rows
	for l: String in HELP_PAD:
		draw_string(font, Vector2(x, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT)
		y += 20.0
