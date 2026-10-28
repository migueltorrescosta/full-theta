class_name EngineeringCutaway
extends Control
## Engineering's cutaway (FT-ENG-001, FT-ENG-004): a low-poly wireframe of the hull,
## rotatable (right-drag, right stick), with each subsystem at its ship-frame position
## as a disc coloured by health (with its percentage, so colour isn't the only code) and
## ringed by its heat, recent hits as fading crosses, and the repair crews as lettered
## tokens: drag one onto a subsystem to send it there, off the ship to call it back
## (right-click a token also calls it back). Drawn in 2D from an orthographic projection
## of the ship frame: cheap, and no world up (D124).

## Hull outline from nose to tail, the approved ship's sections (ProceduralShip): z,
## half-width, half-height, centre height; stretched to enclose the subsystems.
const SECTIONS: Array[Vector4] = ProceduralShip.SECTIONS
const RING: int = 8
const NODE_R: float = 17.0
const TOKEN_R: float = 12.0
const PITCH_LIMIT: float = 1.4
## Mouse drag turn (rad per px).
const DRAG_TURN: float = 0.008

var panel: EngineeringPanel
## View angles (rad): yaw about the ship's up axis, then pitch towards the viewer; the
## picture is then turned a quarter so the bow points up and the ship's length uses the
## cutaway's height. The default is a three-quarter side view.
var yaw: float = 1.2
var pitch: float = 0.3
## Controller cursor (px, this control's space); shown after the stick moved it.
var cursor: Vector2 = Vector2(-1, -1)
## The crew being dragged (-1 none) and where.
var drag_crew: int = -1
var drag_pos: Vector2 = Vector2.ZERO

var _rotating: bool = false
var _rotated: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func rotate_by(d: Vector2) -> void:
	yaw = wrapf(yaw + d.x, -PI, PI)
	pitch = clampf(pitch + d.y, -PITCH_LIMIT, PITCH_LIMIT)
	queue_redraw()


## Moves the controller cursor; returns the subsystem it snaps to, or -1.
func move_cursor(d: Vector2) -> int:
	if cursor.x < 0:
		cursor = size / 2.0
	cursor = (cursor + d).clamp(Vector2.ZERO, size)
	return subsystem_at(cursor, NODE_R * 3.0)


## Screen position of a ship-frame point (m) and its depth (larger is nearer).
func project(p: Vector3) -> Vector3:
	var q: Vector3 = _basis() * p
	var flat: Vector2 = Vector2(q.x, -q.y).rotated(PI / 2.0) * _scale()
	return Vector3(size.x / 2.0 + flat.x, size.y * 0.47 + flat.y, q.z)


func subsystem_pos(i: int) -> Vector2:
	var p: Vector3 = project(panel.ship_def.subsystems[i].position)
	return Vector2(p.x, p.y)


## The subsystem whose disc is under pos (within radius px of its centre), or -1.
func subsystem_at(pos: Vector2, radius: float = NODE_R + 4.0) -> int:
	var best: int = -1
	var best_d: float = radius
	for i: int in panel.count():
		var d: float = subsystem_pos(i).distance_to(pos)
		if d <= best_d:
			best = i
			best_d = d
	return best


## Where crew c's token sits: beside its job's disc, or in the crew bay.
func token_pos(c: int) -> Vector2:
	var job: int = panel.crew_job(c)
	var k: int = 0
	for o: int in c:
		if panel.crew_job(o) == job:
			k += 1
	if job >= 0:
		return subsystem_pos(job) + Vector2(NODE_R + 6.0 + k * (TOKEN_R * 2.0 + 3.0), -NODE_R)
	return Vector2(24.0 + k * (TOKEN_R * 2.0 + 6.0), size.y - 54.0)


func crew_at(pos: Vector2) -> int:
	for c: int in panel.crew_count():
		if token_pos(c).distance_to(pos) <= TOKEN_R + 3.0:
			return c
	return -1


func _gui_input(event: InputEvent) -> void:
	if panel == null or panel.ship_def == null:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		_button(mb)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm == null:
		return
	if drag_crew >= 0:
		drag_pos = mm.position
		queue_redraw()
	elif _rotating:
		_rotated = true
		rotate_by(mm.relative * DRAG_TURN)
	accept_event()


func _button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var c: int = crew_at(mb.position)
				if c >= 0:
					drag_crew = c
					drag_pos = mb.position
					panel.crew_pick = c
				else:
					panel.select(subsystem_at(mb.position))
			elif drag_crew >= 0:
				var i: int = subsystem_at(mb.position, NODE_R * 2.0)
				if i >= 0:
					panel.dispatch(drag_crew, i)
				elif token_pos(drag_crew).distance_to(mb.position) > TOKEN_R * 2.0:
					panel.recall(drag_crew)
				drag_crew = -1
			accept_event()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rotating = true
				_rotated = false
			else:
				_rotating = false
				var c: int = crew_at(mb.position)
				if not _rotated and c >= 0:
					panel.recall(c)
			accept_event()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background"))
	if panel == null or panel.ship_def == null:
		return
	_draw_hull()
	var now: int = panel.ctx.now_ms()
	for h: Dictionary in panel.hits:
		var a: float = 1.0 - float(now - int(h["at_ms"])) / float(EngineeringPanel.HIT_MS)
		var p: Vector3 = project(h["pos"])
		var col: Color = Palette.color("danger")
		col.a = clampf(a, 0.15, 1.0)
		var c: Vector2 = Vector2(p.x, p.y)
		draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), col, 2.5)
		draw_line(c + Vector2(-6, 6), c + Vector2(6, -6), col, 2.5)
	var order: Array = range(panel.count())
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				project(panel.ship_def.subsystems[a].position).z
				< project(panel.ship_def.subsystems[b].position).z
			)
	)
	for i: int in order:
		_draw_subsystem(i)
	# Labels over every disc, outlined, so a near disc never hides a far one's name.
	var rects: Dictionary = label_rects()
	for i: int in rects:
		_draw_label(i, rects[i])
	_draw_crews()
	if cursor.x >= 0:
		var a: Color = Palette.color("accent")
		draw_arc(cursor, 8.0, 0.0, TAU, 16, a, 1.5)
		draw_line(cursor + Vector2(-12, 0), cursor + Vector2(12, 0), a, 1.0)
		draw_line(cursor + Vector2(0, -12), cursor + Vector2(0, 12), a, 1.0)
	var font: Font = get_theme_default_font()
	var fs: int = get_theme_default_font_size()
	draw_multiline_string(
		font,
		Vector2(12, 22),
		hint(),
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 24,
		fs - 2,
		3,
		Palette.color("text_dim")
	)


func _draw_hull() -> void:
	var line: Color = Palette.color("line")
	var rings: Array[PackedVector2Array] = []
	for sec: Vector4 in SECTIONS:
		var ring: PackedVector2Array = []
		for k: int in RING:
			var t: float = TAU * k / RING
			var p: Vector3 = Vector3(cos(t) * sec.y, sec.w + sin(t) * sec.z, sec.x)
			var q: Vector3 = project(p * _hull_scale())
			ring.append(Vector2(q.x, q.y))
		rings.append(ring)
		var closed: PackedVector2Array = ring.duplicate()
		closed.append(ring[0])
		draw_polyline(closed, line, 1.0, true)
	for k: int in RING:
		var spine: PackedVector2Array = []
		for ring: PackedVector2Array in rings:
			spine.append(ring[k])
		draw_polyline(spine, line, 1.0, true)


func _draw_subsystem(i: int) -> void:
	var c: Vector2 = subsystem_pos(i)
	var h: float = panel.health_frac(i)
	var fill: Color = _health_color(h)
	draw_circle(c, NODE_R, Palette.color("panel"))
	draw_circle(c, NODE_R - 3.0, fill)
	# Heat: an arc around the disc, a full ring at the fault threshold.
	var heat: float = clampf(panel.heat_frac(i), 0.0, 1.0)
	if heat > 0.02:
		var role: String = "danger" if heat >= EngineeringPanel.HOT else "warn"
		draw_arc(c, NODE_R + 3.0, -PI / 2.0, -PI / 2.0 + TAU * heat, 24, Palette.color(role), 3.0)
	# Hardened (FT-ENG-008): a blue rim; an unknown-cause fault (FT-SIM-025): a "?".
	if panel.hardened_ticks(i) > 0:
		draw_arc(c, NODE_R + 5.5, 0.0, TAU, 32, Palette.color("accent"), 2.0)
	if panel.has_fault(i):
		var font: Font = get_theme_default_font()
		Palette.draw_outlined(
			self, font, c + Vector2(NODE_R * 0.7, -NODE_R * 0.7), "?", 16, Palette.color("warn")
		)
	if i == panel.selected:
		draw_arc(c, NODE_R + 8.0, 0.0, TAU, 32, Palette.color("selected"), 2.0)


## Where each subsystem's label goes (rects in this control's space): below its disc,
## else right, left or above, the first spot inside the cutaway that covers no disc,
## crew token or label already placed, so the labels stay apart when the cutaway is
## small (150 % UI scale); below when nothing is free.
func label_rects() -> Dictionary:
	var font: Font = get_theme_default_font()
	var fs: int = _label_size()
	var taken: Array[Rect2] = []
	for i: int in panel.count():
		taken.append(_square(subsystem_pos(i), NODE_R + 3.0))
	for c: int in panel.crew_count():
		taken.append(_square(token_pos(c), TOKEN_R))
	var out: Dictionary = {}
	var gap: float = NODE_R + 4.0
	for i: int in panel.count():
		var c: Vector2 = subsystem_pos(i)
		var sz: Vector2 = font.get_string_size(_label(i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var spots: Array[Vector2] = [
			c + Vector2(-sz.x / 2.0, gap),
			c + Vector2(gap, -sz.y / 2.0),
			c + Vector2(-gap - sz.x, -sz.y / 2.0),
			c + Vector2(-sz.x / 2.0, -gap - sz.y),
		]
		out[i] = Rect2(spots[0], sz)
		for at: Vector2 in spots:
			var r: Rect2 = Rect2(at, sz)
			if Rect2(Vector2.ZERO, size).encloses(r) and not taken.any(r.intersects):
				out[i] = r
				break
		taken.append(out[i])
	return out


func _label(i: int) -> String:
	return "%s %d%%" % [panel.short_name(i), roundi(panel.health_frac(i) * 100)]


func _label_size() -> int:
	return get_theme_default_font_size() - 3


static func _square(c: Vector2, r: float) -> Rect2:
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)


func _draw_label(i: int, rect: Rect2) -> void:
	var font: Font = get_theme_default_font()
	var fs: int = _label_size()
	var label: String = _label(i)
	var at: Vector2 = rect.position + Vector2(0.0, font.get_ascent(fs))
	Palette.draw_outlined(self, font, at, label, fs, Palette.color("text"))


func _draw_crews() -> void:
	var font: Font = get_theme_default_font()
	var fs: int = get_theme_default_font_size() - 2
	draw_string(
		font,
		Vector2(12, size.y - 76),
		tr("eng.crews"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		Palette.color("text_dim")
	)
	for c: int in panel.crew_count():
		var p: Vector2 = drag_pos if c == drag_crew else token_pos(c)
		var taken: bool = panel.crew_taken(c)
		draw_circle(p, TOKEN_R, Palette.color("text_dim" if taken else "accent"))
		var letter: String = EngineeringPanel.crew_letter(c)
		var sz: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(
			font,
			p + Vector2(-sz.x / 2.0, font.get_ascent(fs) - sz.y / 2.0),
			letter,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			Palette.color("background")
		)


static func _health_color(h: float) -> Color:
	if h <= 0.0:
		return Palette.color("line")
	if h < 0.34:
		return Palette.color("danger")
	if h < 1.0:
		return Palette.color("warn")
	return Palette.color("ok")


func _basis() -> Basis:
	return Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw)


## Per-axis stretch of the hull sections so the hull encloses every subsystem (m per
## section unit).
func _hull_scale() -> Vector3:
	var ext: Vector3 = Vector3(2.0, 2.0, 2.0)
	for s: SubsystemDef in panel.ship_def.subsystems:
		ext = ext.max(s.position.abs())
	return Vector3((ext.x + 6.0) / 0.5, (ext.y + 3.0) / 0.28, (ext.z + 5.0) / 2.5)


## Pixels per metre: the hull's longest extent fits the control.
func _scale() -> float:
	var hs: Vector3 = _hull_scale()
	var extent: float = maxf(2.7 * hs.z, maxf(0.5 * hs.x, 0.28 * hs.y + 4.0))
	return minf(size.x * 1.1, size.y * 0.8) / (2.0 * extent)


## The hint over the cutaway; a phone has no right button (#28), so it names the drag only.
func hint() -> String:
	if LayoutMode.is_phone(LayoutMode.form_of(self)):
		return TouchText.of("eng.cutaway_hint_touch", "Drag a crew onto a part to fix it.")
	return tr("eng.cutaway_hint")
