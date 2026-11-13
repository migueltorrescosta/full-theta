class_name EngineeringCutaway
extends Control
## Engineering's cutaway (FT-ENG-001, FT-ENG-004): a low-poly wireframe of the hull,
## rotatable (right-drag, right stick), with each subsystem at its ship-frame position
## as a disc coloured by health (with its percentage, so colour isn't the only code) and
## ringed by its heat, recent hits as fading crosses, and the repair crews as lettered
## tokens: drag one onto a subsystem to send it there, off the ship to call it back
## (right-click a token also calls it back). Drawn in 2D from an orthographic projection
## of the ship frame: cheap, and no world up (D124).
##
## On a touch screen (#28, D274) a finger has no right button: a drag that starts off the
## crew tokens turns the cutaway and a tap selects; tokens and discs take a 44 px grab area
## and tokens sit 52 px apart, each token's area a control with the `tap` meta (TapAudit).
##
## One sentence over the cutaway says how to use it on the player's device (touch, pad, or
## mouse), until the first crew dragged onto a part (or, on a pad, the first turn): then it
## goes for good, like the other first-visit hints (R22-17, ClientSettings.hint_seen).

## Hull outline from nose to tail, the approved ship's sections (ProceduralShip): z,
## half-width, half-height, centre height; stretched to enclose the subsystems.
const SECTIONS: Array[Vector4] = ProceduralShip.SECTIONS
const RING: int = 8
const NODE_R: float = 17.0
## The smallest disc (px in radius) a small cutaway shrinks to.
const NODE_R_MIN: float = 7.0
## The drawing area (px) a cutaway keeps under its hint, wide and tall (D319).
const MIN_SQUARE: float = 200.0
const TOKEN_R: float = 12.0
const PITCH_LIMIT: float = 1.4
## Mouse drag turn (rad per px).
const DRAG_TURN: float = 0.008
## A finger moving more than this (px) after it lands turns instead of tapping.
const TURN_SLOP: float = 8.0
## Under this height (px) the cutaway draws no hint.
const HINT_MIN_H: float = 220.0
## A phone's cutaway at least this many times wider than tall puts its hint beside the hull.
const HINT_SIDE_ASPECT: float = 1.3
## The first-visit hint key of the cutaway's sentence (ClientSettings.hint_seen).
const HINT_KEY: String = "eng_cutaway"

var model: EngineeringModel
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

## The parts whose label shows the short name alone (label_rects).
var shortened: Array[int] = []
var _rotating: bool = false
var _rotated: bool = false
## A phone's press off the tokens: a tap selects on release, a drag turns.
var _finger_turn: bool = false
var _press_at: Vector2 = Vector2.ZERO
var _taps: Array[Control] = []
## The projection's cache (R20-6): the discs' screen positions and depths, their radius, the
## draw order, the hull's lines and the hint's height. It changes only when the view turns,
## the control resizes, the ship, the form or the language changes, not on every frame.
var _geo_key: Array = []
var _geo_serial: int = 0
var _geo_pos: Array[Vector2] = []
var _geo_depth: Array[float] = []
var _geo_order: Array[int] = []
var _geo_hull: Array[PackedVector2Array] = []
var _geo_node_r: float = NODE_R
var _geo_hint_h: float = 0.0
## label_rects' cache: the geometry it was made for and the state it read.
var _labels_key: Array = []
var _labels_out: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## Room for the hint (three lines) over a MIN_SQUARE drawing area (D319); a phone sets its
## own height.
func _get_minimum_size() -> Vector2:
	return Vector2(MIN_SQUARE, MIN_SQUARE + 64.0)


## The discs' radius: NODE_R, smaller when the projected parts are closer than two discs
## (a small cutaway at 150 % UI scale), so the discs never overlap.
func node_r() -> float:
	if model == null or model.ship_def == null:
		return NODE_R
	_ensure_geo()
	return _geo_node_r


func rotate_by(d: Vector2) -> void:
	yaw = wrapf(yaw + d.x, -PI, PI)
	pitch = clampf(pitch + d.y, -PITCH_LIMIT, PITCH_LIMIT)
	queue_redraw()


## Moves the controller cursor; returns the subsystem it snaps to, or -1.
func move_cursor(d: Vector2) -> int:
	if cursor.x < 0:
		cursor = size / 2.0
	cursor = (cursor + d).clamp(Vector2.ZERO, size)
	return subsystem_at(cursor, node_r() * 3.0)


## Screen position of a ship-frame point (m) and its depth (larger is nearer).
func project(p: Vector3) -> Vector3:
	if model != null and model.ship_def != null:
		_ensure_geo()
	return _project(p)


## `project` with the cached hint height (the cache is current).
func _project(p: Vector3) -> Vector3:
	var q: Vector3 = _basis() * p
	var flat: Vector2 = Vector2(q.x, -q.y).rotated(PI / 2.0) * _scale()
	var top: float = _geo_hint_h
	return Vector3(size.x / 2.0 + flat.x, top + (size.y - top) * 0.47 + flat.y, q.z)


func subsystem_pos(i: int) -> Vector2:
	_ensure_geo()
	return _geo_pos[i]


## Rebuilds the cached projection when what it depends on changed: the view angles, the
## size, the ship, the form and the language (the hint's wording and height).
func _ensure_geo() -> void:
	var key: Array = [
		yaw,
		pitch,
		size,
		model.ship_def,
		model.count(),
		phone(),
		hint(),
		TranslationServer.get_locale(),
		get_theme_default_font_size(),
	]
	if key == _geo_key:
		return
	_geo_key = key
	_geo_serial += 1
	_geo_hint_h = _hint_height()
	var subs: Array[SubsystemDef] = model.ship_def.subsystems
	_geo_pos.clear()
	_geo_depth.clear()
	for i: int in model.count():
		var p: Vector3 = _project(subs[i].position)
		_geo_pos.append(Vector2(p.x, p.y))
		_geo_depth.append(p.z)
	_geo_order.clear()
	_geo_order.assign(range(model.count()))
	_geo_order.sort_custom(func(a: int, b: int) -> bool: return _geo_depth[a] < _geo_depth[b])
	var least: float = INF
	for i: int in _geo_pos.size():
		for j: int in range(i + 1, _geo_pos.size()):
			least = minf(least, _geo_pos[i].distance_to(_geo_pos[j]))
	_geo_node_r = clampf((least - 3.0) / 2.0, NODE_R_MIN, NODE_R)
	_geo_hull = _hull_lines()


## The subsystem whose disc is under pos (within radius px of its centre), or -1.
func subsystem_at(pos: Vector2, radius: float = -1.0) -> int:
	if radius < 0.0:
		radius = node_r() + 4.0
	var best: int = -1
	var best_d: float = radius
	for i: int in model.count():
		var d: float = subsystem_pos(i).distance_to(pos)
		if d <= best_d:
			best = i
			best_d = d
	return best


## Where crew c's token sits: beside its job's disc, or in the crew bay.
func token_pos(c: int) -> Vector2:
	var job: int = model.crew_job(c)
	var k: int = 0
	for o: int in c:
		if model.crew_job(o) == job:
			k += 1
	var touch: bool = phone()
	if job >= 0:
		var step: float = _token_step() if touch else TOKEN_R * 2.0 + 3.0
		# Clear of the disc and its heat arc, rims and selection ring (up to node_r() + 8).
		return subsystem_pos(job) + Vector2(node_r() + TOKEN_R + 8.0 + k * step, -node_r() * 0.6)
	var bay: float = _token_step() if touch else TOKEN_R * 2.0 + 6.0
	return Vector2(24.0 + k * bay, size.y - 54.0)


func crew_at(pos: Vector2) -> int:
	for c: int in model.crew_count():
		if token_pos(c).distance_to(pos) <= grab_radius():
			return c
	return -1


## True on a phone (either way up).
func phone() -> bool:
	return is_inside_tree() and LayoutMode.is_phone(LayoutMode.form_of(self))


## True on a touch screen (a phone or a tablet), where a finger turns the cutaway.
func finger() -> bool:
	return is_inside_tree() and LayoutMode.is_touch(LayoutMode.kind_of(self))


## How far (px) from a token's centre a press grabs it: half a touch target on a touch screen.
func grab_radius() -> float:
	return UiTheme.TOUCH_MIN / 2.0 if finger() else TOKEN_R + 3.0


## Centre to centre of two tokens on a phone: a grab area and a gap.
func _token_step() -> float:
	return UiTheme.TOUCH_MIN + UiTheme.TOUCH_GAP


func _gui_input(event: InputEvent) -> void:
	if model == null or model.ship_def == null:
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
	elif _finger_turn and (_rotated or mm.position.distance_to(_press_at) > TURN_SLOP):
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
					model.crew_pick = c
				elif finger():
					_finger_turn = true
					_rotated = false
					_press_at = mb.position
				else:
					model.select(subsystem_at(mb.position))
			elif drag_crew >= 0:
				var i: int = subsystem_at(mb.position, maxf(node_r() * 2.0, grab_radius()))
				if i >= 0:
					if model.dispatch(drag_crew, i):
						learned()
				elif token_pos(drag_crew).distance_to(mb.position) > grab_radius() * 2.0:
					model.recall(drag_crew)
				drag_crew = -1
			elif _finger_turn:
				_finger_turn = false
				if not _rotated:
					model.select(subsystem_at(mb.position, UiTheme.TOUCH_MIN / 2.0))
			accept_event()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rotating = true
				_rotated = false
			else:
				_rotating = false
				var c: int = crew_at(mb.position)
				if not _rotated and c >= 0:
					model.recall(c)
			accept_event()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background"))
	if model == null or model.ship_def == null:
		return
	_draw_hull()
	var now: int = model.ctx.now_ms()
	for h: Dictionary in model.hits:
		var a: float = 1.0 - float(now - int(h["at_ms"])) / float(EngineeringModel.HIT_MS)
		var p: Vector3 = project(h["pos"])
		var col: Color = Palette.color("danger")
		col.a = clampf(a, 0.15, 1.0)
		var c: Vector2 = Vector2(p.x, p.y)
		draw_line(c + Vector2(-6, -6), c + Vector2(6, 6), col, 2.5)
		draw_line(c + Vector2(-6, 6), c + Vector2(6, -6), col, 2.5)
	_ensure_geo()
	for i: int in _geo_order:
		_draw_subsystem(i)
	# Labels over every disc, outlined, so a near disc never hides a far one's name.
	var rects: Dictionary = label_rects()
	for i: int in rects:
		_draw_label(i, rects[i])
	_draw_crews()
	_sync_taps()
	if cursor.x >= 0:
		var a: Color = Palette.color("accent")
		draw_arc(cursor, 8.0, 0.0, TAU, 16, a, 1.5)
		draw_line(cursor + Vector2(-12, 0), cursor + Vector2(12, 0), a, 1.0)
		draw_line(cursor + Vector2(0, -12), cursor + Vector2(0, 12), a, 1.0)
	if hint_height() == 0.0 and not hint_beside():
		return
	var font: Font = get_theme_default_font()
	var fs: int = get_theme_default_font_size()
	var box: Rect2 = hint_rect()
	draw_multiline_string(
		font,
		Vector2(12.0, 22.0) if not hint_beside() else box.position + Vector2(0.0, 14.0),
		hint(),
		HORIZONTAL_ALIGNMENT_LEFT,
		box.size.x,
		fs - 2,
		-1 if hint_beside() else 3,
		Palette.color("text_dim")
	)


func _draw_hull() -> void:
	var line: Color = Palette.color("line")
	for pts: PackedVector2Array in _geo_hull:
		draw_polyline(pts, line, 1.0, true)


## The hull's lines in this control's space: each section's closed ring, then the spines
## along the hull (one per ring point).
func _hull_lines() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var rings: Array[PackedVector2Array] = []
	var stretch: Vector3 = _hull_scale()
	for sec: Vector4 in SECTIONS:
		var ring: PackedVector2Array = []
		for k: int in RING:
			var t: float = TAU * k / RING
			var p: Vector3 = Vector3(cos(t) * sec.y, sec.w + sin(t) * sec.z, sec.x)
			var q: Vector3 = _project(p * stretch)
			ring.append(Vector2(q.x, q.y))
		rings.append(ring)
		var closed: PackedVector2Array = ring.duplicate()
		closed.append(ring[0])
		out.append(closed)
	for k: int in RING:
		var spine: PackedVector2Array = []
		for ring: PackedVector2Array in rings:
			spine.append(ring[k])
		out.append(spine)
	return out


func _draw_subsystem(i: int) -> void:
	var c: Vector2 = subsystem_pos(i)
	var h: float = model.health_frac(i)
	var fill: Color = _health_color(h)
	draw_circle(c, node_r(), Palette.color("panel"))
	draw_circle(c, node_r() - 3.0, fill)
	# Heat: an arc around the disc, a full ring at the fault threshold.
	var heat: float = clampf(model.heat_frac(i), 0.0, 1.0)
	if heat > 0.02:
		var role: String = "danger" if heat >= EngineeringModel.HOT else "warn"
		draw_arc(c, node_r() + 3.0, -PI / 2.0, -PI / 2.0 + TAU * heat, 24, Palette.color(role), 3.0)
	# Hardened (FT-ENG-008): a blue rim; an unknown-cause fault (FT-SIM-025): a "?".
	if model.hardened_ticks(i) > 0:
		draw_arc(c, node_r() + 5.5, 0.0, TAU, 32, Palette.color("accent"), 2.0)
	if model.has_fault(i):
		var font: Font = get_theme_default_font()
		Palette.draw_outlined(
			self, font, c + Vector2(node_r() * 0.7, -node_r() * 0.7), "?", 16, Palette.color("warn")
		)
	if i == model.selected:
		draw_arc(c, node_r() + 8.0, 0.0, TAU, 32, Palette.color("selected"), 2.0)


## Where each subsystem's label goes (rects in this control's space), within LABEL_REACH
## of its disc: below it, else right, left, above, a diagonal, then a step further out: the
## first spot inside the cutaway that covers no disc, crew token or label already placed,
## so the labels stay apart when the cutaway is small (150 % UI scale). A part whose full
## label ("SNS 100%") finds no spot shows its short name alone ("SNS", see `shortened`);
## below the disc when nothing is free.
func label_rects() -> Dictionary:
	if model == null or model.ship_def == null:
		return {}
	_ensure_geo()
	# The layout reads the geometry, the label texts (the health percentages) and where the
	# crew sit: it is redone only when one of them changed (R20-6).
	var texts: PackedStringArray = PackedStringArray()
	for i: int in model.count():
		texts.append(_label(i))
	var jobs: PackedInt32Array = PackedInt32Array()
	for c: int in model.crew_count():
		jobs.append(model.crew_job(c))
	var key: Array = [_geo_serial, texts, jobs]
	if key != _labels_key:
		_labels_key = key
		_labels_out = _place_labels()
	return _labels_out


func _place_labels() -> Dictionary:
	var font: Font = get_theme_default_font()
	var fs: int = _label_size()
	var taken: Array[Rect2] = []
	var r: float = node_r()
	# A disc with its heat arc and rims (up to node_r() + 7), the crew tokens and the
	# "Crews" caption: no label covers them.
	for i: int in model.count():
		taken.append(_square(subsystem_pos(i), r + 6.0))
	for c: int in model.crew_count():
		taken.append(_square(token_pos(c), TOKEN_R))
	taken.append(_crews_rect())
	if hint_beside():
		taken.append(hint_rect().grow(4.0))
	var out: Dictionary = {}
	shortened.clear()
	var gap: float = r + 6.0
	for i: int in model.count():
		var c: Vector2 = subsystem_pos(i)
		var first: Rect2 = Rect2()
		var chosen: Rect2 = Rect2()
		for short: bool in [false, true]:
			var sz: Vector2 = font.get_string_size(
				_label(i, short), HORIZONTAL_ALIGNMENT_LEFT, -1, fs
			)
			for at: Vector2 in _label_spots(c, sz, gap):
				var spot: Rect2 = Rect2(at, sz)
				if not first.has_area():
					first = spot
				if Rect2(Vector2.ZERO, size).encloses(spot) and not taken.any(spot.intersects):
					chosen = spot
					break
			if chosen.has_area():
				if short:
					shortened.append(i)
				break
		out[i] = chosen if chosen.has_area() else first
		taken.append(out[i])
	return out


## Candidate top-left corners for a label of size `sz` round a disc at `c`, nearest first.
func _label_spots(c: Vector2, sz: Vector2, gap: float) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for k: float in [1.0, 1.6]:
		var g: float = gap * k
		(
			spots
			. append_array(
				[
					c + Vector2(-sz.x / 2.0, g),
					c + Vector2(g, -sz.y / 2.0),
					c + Vector2(-g - sz.x, -sz.y / 2.0),
					c + Vector2(-sz.x / 2.0, -g - sz.y),
					c + Vector2(g * 0.7, g * 0.7 - sz.y / 2.0),
					c + Vector2(-g * 0.7 - sz.x, g * 0.7 - sz.y / 2.0),
					c + Vector2(g * 0.7, -g * 0.7 - sz.y / 2.0),
					c + Vector2(-g * 0.7 - sz.x, -g * 0.7 - sz.y / 2.0),
				]
			)
		)
	return spots


func _label(i: int, short: bool = false) -> String:
	if short:
		return model.short_name(i)
	return "%s %d%%" % [model.short_name(i), roundi(model.health_frac(i) * 100)]


func _label_size() -> int:
	return get_theme_default_font_size() - 3


static func _square(c: Vector2, r: float) -> Rect2:
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)


func _draw_label(i: int, rect: Rect2) -> void:
	var font: Font = get_theme_default_font()
	var fs: int = _label_size()
	var label: String = _label(i, i in shortened)
	var at: Vector2 = rect.position + Vector2(0.0, font.get_ascent(fs))
	Palette.draw_outlined(self, font, at, label, fs, Palette.color("text"))


## The "Crews" caption's box, above the crew bay.
func _crews_rect() -> Rect2:
	var font: Font = get_theme_default_font()
	var fs: int = get_theme_default_font_size() - 2
	var sz: Vector2 = font.get_string_size(tr("eng.crews"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	return Rect2(Vector2(12.0, size.y - 76.0 - font.get_ascent(fs)), sz)


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
	for c: int in model.crew_count():
		var p: Vector2 = drag_pos if c == drag_crew else token_pos(c)
		var taken: bool = model.crew_taken(c)
		draw_circle(p, TOKEN_R, Palette.color("text_dim" if taken else "accent"))
		var letter: String = EngineeringModel.crew_letter(c)
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


## A subsystem's disc and health-bar colour: the shared health bands (HealthBand through
## StatusView.bar_role, R05-2), so Engineering and the status view colour one health alike;
## a destroyed part (0) is the plain line colour.
static func _health_color(h: float) -> Color:
	if h <= 0.0:
		return Palette.color("line")
	return Palette.color(StatusView.bar_role(h))


func _basis() -> Basis:
	return Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw)


## Per-axis stretch of the hull sections so the hull encloses every subsystem (m per
## section unit).
func _hull_scale() -> Vector3:
	var ext: Vector3 = Vector3(2.0, 2.0, 2.0)
	for s: SubsystemDef in model.ship_def.subsystems:
		ext = ext.max(s.position.abs())
	return Vector3((ext.x + 6.0) / 0.5, (ext.y + 3.0) / 0.28, (ext.z + 5.0) / 2.5)


## Pixels per metre: the hull's longest extent fits the control.
func _scale() -> float:
	var hs: Vector3 = _hull_scale()
	var extent: float = maxf(2.7 * hs.z, maxf(0.5 * hs.x, 0.28 * hs.y + 4.0))
	return minf(size.x * 1.1, (size.y - _geo_hint_h) * 0.9) / (2.0 * extent)


## The room the hint takes at the top, 0 on a short cutaway (a phone upright under the
## banner); the hull is drawn below it, so the two never overlap (T2).
func hint_height() -> float:
	if model == null or model.ship_def == null:
		return _hint_height()
	_ensure_geo()
	return _geo_hint_h


func _hint_height() -> float:
	if size.y < HINT_MIN_H or model == null or hint_beside() or hint() == "":
		return 0.0
	var fs: int = get_theme_default_font_size() - 2
	var text: Vector2 = get_theme_default_font().get_multiline_string_size(
		hint(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, fs, 3
	)
	return 16.0 + text.y + 6.0


## True on a phone on its side, where the page is wide and short: the hint sits in the free
## column left of the hull instead of over it, so the hull keeps the page's whole height
## (at least MIN_SQUARE, D319).
func hint_beside() -> bool:
	return (
		size.y >= HINT_MIN_H
		and model != null
		and phone()
		and size.x >= HINT_SIDE_ASPECT * size.y
		and hint() != ""
	)


## The hint's box: over the cutaway, or left of the hull when beside it.
func hint_rect() -> Rect2:
	var font: Font = get_theme_default_font()
	var fs: int = get_theme_default_font_size() - 2
	if hint_beside():
		var w: float = maxf(size.x / 2.0 - size.y * 0.3 - 16.0, 96.0)
		var text: Vector2 = font.get_multiline_string_size(
			hint(), HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1
		)
		return Rect2(Vector2(12.0, 10.0), Vector2(w, text.y))
	var text: Vector2 = font.get_multiline_string_size(
		hint(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, fs, 3
	)
	return Rect2(Vector2(12.0, 10.0), Vector2(size.x - 24.0, text.y))


## The hint over the cutaway in the words of the player's device (a finger has no right
## button, #28; a pad turns with its right stick), or "" once learned.
func hint() -> String:
	if model == null or model.ctx == null or model.ctx.settings.hint_seen(HINT_KEY):
		return ""
	if finger():
		return tr("eng.cutaway_hint_touch")
	if model.ctx.matcher.device == IntentTable.PAD:
		return tr("eng.cutaway_hint_pad")
	return tr("eng.cutaway_hint")


## The player did what the hint says (a crew dragged onto a part, a pad's turn): it goes for
## good.
func learned() -> void:
	var settings: ClientSettings = model.ctx.settings
	if settings.hint_seen(HINT_KEY):
		return
	settings.mark_hint_seen(HINT_KEY)
	settings.save()
	queue_redraw()


## Each token's grab area on a phone, as a control TapAudit sees.
func _sync_taps() -> void:
	var n: int = model.crew_count() if finger() else 0
	while _taps.size() < n:
		var c: Control = Control.new()
		c.name = "CrewTap%d" % _taps.size()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.set_meta("tap", true)
		add_child(c)
		_taps.append(c)
	var r: float = grab_radius()
	for c: int in _taps.size():
		_taps[c].visible = c < n
		if c < n:
			var p: Vector2 = drag_pos if c == drag_crew else token_pos(c)
			_taps[c].position = p - Vector2(r, r)
			_taps[c].size = Vector2(r, r) * 2.0
