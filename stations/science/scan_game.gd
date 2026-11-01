class_name ScanGame
extends Control
## The silhouette-alignment scan (§5.4, FT-SCI-004, FT-SCI-013, D58): the server's point
## cloud (dots) and the wireframe the player turns until it lies on the cloud. The server
## opens 1 to 3 rotation axes by noise (FT-SCI-014); the open axes are numbered 0 to 2 in
## x, y, z order here. The server checks the submitted angles (FT-SCI-011); the match
## shown while turning is the client's estimate from the cloud alone (nearest cloud point
## of each posed vertex), so it can't leak the hidden pose.
##
## Turning: drag horizontally for the selected axis and vertically for the next open
## axis (KB/M and touch), tap an axis chip to select it, the keyboard or stick dials in
## `turn(index, delta)`. Enter / X submits, Backspace / Y cancels; both are also buttons.
## On a phone (`footer` off) the chips and buttons are real Buttons in the panel's thumb
## rails instead (SciencePanel, #28), and the cloud takes the freed room.

signal submitted(angles: Vector3)
signal cancelled

## Radians turned per pixel dragged.
const RAD_PER_PX: float = 0.012
## A fixed look at the scene so depth reads: the model is seen from this yaw and pitch.
const VIEW_YAW: float = 0.5
const VIEW_PITCH: float = 0.35
const FONT_SIZE: int = 15
const CHIP_W: float = 64.0
## Tap-sized (44 px, FT-STN-005).
const CHIP_H: float = 44.0
const BUTTON_W: float = 110.0

var wire: Array[Vector3] = []
var cloud: Array[Vector3] = []
## Bit mask of the open axes (bit 0 x, 1 y, 2 z).
var axes: int = 0
## The angles chosen so far (rad), 0 on closed axes.
var angles: Vector3 = Vector3.ZERO
## Index (among the open axes) of the axis a horizontal drag turns.
var selected: int = 0
var title: String = ""
var noise_text: String = ""
var elapsed_s: float = 0.0
## Draw the axis chips and the Submit and Cancel buttons (off on a phone, #28).
var footer: bool = true:
	set(value):
		footer = value
		queue_redraw()

var _drag: bool = false
var _start: int = -1
var _view: Basis = Basis.from_euler(Vector3(VIEW_PITCH, VIEW_YAW, 0.0))


## Loads a SCIENCE section block that has a scan open (session 1).
func load_block(block: Dictionary) -> void:
	var start: int = int(block.get("session_start", 0))
	var fresh: bool = start != _start
	_start = start
	wire = _points(block.get("wire", []))
	cloud = _points(block.get("cloud", []))
	axes = int(block.get("axes", 0))
	if fresh:
		angles = Vector3.ZERO
		selected = 0
	queue_redraw()


## The open axes in x, y, z order: [0, 2] for x and z.
func open_axes() -> Array[int]:
	var out: Array[int] = []
	for a: int in 3:
		if axes & (1 << a):
			out.append(a)
	return out


## Turns the open axis number `index` by `delta` radians.
func turn(index: int, delta: float) -> void:
	var open: Array[int] = open_axes()
	if index < 0 or index >= open.size():
		return
	var a: int = open[index]
	angles[a] = wrapf(angles[a] + delta, -PI, PI)
	queue_redraw()


## The match (0..1) of the wireframe at the current angles against the cloud.
func quality() -> float:
	if wire.is_empty() or cloud.is_empty():
		return 0.0
	var pose: Basis = Basis.from_euler(angles)
	var span: float = 1.0
	var def: ScienceDef = ScienceLookup.science_def()
	if def != null and def.quality_span > 0.0:
		span = def.quality_span
	var total: float = 0.0
	for v: Vector3 in wire:
		var p: Vector3 = pose * v
		var best: float = INF
		for c: Vector3 in cloud:
			best = minf(best, p.distance_squared_to(c))
		total += best
	return clampf(1.0 - sqrt(total / wire.size()) / span, 0.0, 1.0)


func submit() -> void:
	submitted.emit(angles)


func cancel() -> void:
	cancelled.emit()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if _press(mb.position):
				accept_event()
				return
			_drag = true
		else:
			_drag = false
		accept_event()
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _drag:
		var open: Array[int] = open_axes()
		turn(selected, mm.relative.x * RAD_PER_PX)
		if open.size() > 1:
			turn((selected + 1) % open.size(), mm.relative.y * RAD_PER_PX)
		accept_event()


## Picks the open axis number `index` for horizontal drags (an axis chip's tap).
func select_axis(index: int) -> void:
	if index >= 0 and index < open_axes().size():
		selected = index
		queue_redraw()


## Chips and buttons; true when the press hit one.
func _press(at: Vector2) -> bool:
	if not footer:
		return false
	var open: Array[int] = open_axes()
	for i: int in open.size():
		if _chip_rect(i).has_point(at):
			selected = i
			queue_redraw()
			return true
	if _button_rect(0).has_point(at):
		submit()
		return true
	if _button_rect(1).has_point(at):
		cancel()
		return true
	return false


## Footer rows: the axis chips and the buttons share one, or the buttons take the row
## above on a narrow stage (a phone).
func _rows() -> int:
	if not footer:
		return 0
	var chips: float = 12.0 + open_axes().size() * (CHIP_W + 6.0)
	return 1 if size.x >= chips + 2.0 * (BUTTON_W + 6.0) + 12.0 else 2


func _chip_rect(i: int) -> Rect2:
	return Rect2(
		Vector2(12.0 + i * (CHIP_W + 6.0), size.y - CHIP_H - 10.0), Vector2(CHIP_W, CHIP_H)
	)


func _button_rect(i: int) -> Rect2:
	var x: float = size.x - 12.0 - (i + 1) * (BUTTON_W + 6.0) + 6.0
	var y: float = size.y - CHIP_H - 10.0 - (0.0 if _rows() == 1 else CHIP_H + 6.0)
	return Rect2(Vector2(x, y), Vector2(BUTTON_W, CHIP_H))


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("panel"))
	draw_string(
		font,
		Vector2(12.0, 22.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		Palette.color("text")
	)
	var mid: Vector2 = Vector2(size.x / 2.0, size.y / 2.0 - 14.0)
	var scale: float = minf(size.x, size.y - 56.0 - CHIP_H * _rows()) * 0.4
	for c: Vector3 in cloud:
		var p: Vector2 = _project(c, mid, scale)
		draw_circle(p, 3.0, Palette.color("text_dim"))
	var pose: Basis = Basis.from_euler(angles)
	var pts: PackedVector2Array = PackedVector2Array()
	for v: Vector3 in wire:
		pts.append(_project(pose * v, mid, scale))
	var accent: Color = Palette.color("accent")
	for i: int in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], accent, 2.0, true)
		draw_line(pts[i], mid, accent * Color(1, 1, 1, 0.3), 1.0, true)
		draw_circle(pts[i], 3.5, accent)
	_draw_footer(font)


func _draw_footer(font: Font) -> void:
	var q: float = quality()
	var def: ScienceDef = ScienceLookup.science_def()
	var lock: float = def.lock_threshold if def != null else 0.85
	var col: Color = Palette.color("ok") if q >= lock else Palette.color("warn")
	var y: float = size.y - CHIP_H * _rows() - 22.0 - (6.0 if _rows() == 2 else 0.0)
	draw_string(
		font,
		Vector2(12.0, y),
		"%s %d%%   %s   %d s" % [tr("sci.match"), roundi(q * 100.0), noise_text, roundi(elapsed_s)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		col
	)
	if not footer:
		return
	var open: Array[int] = open_axes()
	for i: int in open.size():
		var r: Rect2 = _chip_rect(i)
		draw_rect(r, Palette.color("panel_focus") if i == selected else Palette.color("background"))
		draw_rect(r, Palette.color("line"), false, 1.0)
		var label: String = "%s %d" % ["XYZ"[open[i]], roundi(rad_to_deg(angles[open[i]]))]
		draw_string(
			font,
			r.position + Vector2(6.0, 23.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE - 1,
			Palette.color("text")
		)
	for i: int in 2:
		var r: Rect2 = _button_rect(i)
		draw_rect(r, Palette.color("panel_focus"))
		draw_rect(r, Palette.color("ok") if i == 0 else Palette.color("line"), false, 1.0)
		draw_string(
			font,
			r.position + Vector2(10.0, 23.0),
			tr("sci.submit") if i == 0 else tr("sci.cancel"),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE,
			Palette.color("text")
		)


func _project(p: Vector3, mid: Vector2, scale: float) -> Vector2:
	var v: Vector3 = _view * p
	return mid + Vector2(v.x, -v.y) * scale


static func _points(rows: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r: Variant in rows:
		out.append((r as Dictionary)["p"])
	return out
