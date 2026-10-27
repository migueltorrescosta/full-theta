class_name VirtualStick
extends Control
## An on-screen thumb stick (#28; FT §5.1 touch: the left stick turns, the right one
## slides). A finger anywhere on it grabs the knob; `value` is the knob's offset from the
## centre, each axis in -1..1 with +x right and +y down, zero inside `dead_zone` and
## rescaled outside it. Releasing springs the knob back to the centre. A mouse drives it
## too (desktop tests); the mouse Godot emulates from a finger is ignored.
##
##     var turn := VirtualStick.new()
##     turn.label = "Turn"
##     turn.moved.connect(func(v: Vector2) -> void: _set_turn(v))

## The value changed (also to zero on release).
signal moved(value: Vector2)

## Least size (the mockups' sticks are 96-120 px).
const MIN_SIZE: float = 96.0

## Caption under the knob.
var label: String = "":
	set(v):
		label = v
		queue_redraw()
## Share of the radius around the centre that reads as zero.
var dead_zone: float = 0.12
## Current value, each axis -1..1.
var value: Vector2 = Vector2.ZERO

var _touch: int = -1
var _mouse: bool = false
## Knob offset from the centre in px (drawn).
var _knob: Vector2 = Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(MIN_SIZE, MIN_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(TouchInput.GROUP)


## The radius the knob travels, in px.
func radius() -> float:
	return maxf(minf(size.x, size.y) / 2.0 - 4.0, 1.0)


## The value for a knob offset `offset` px from the centre of a stick of radius `r`,
## after the dead zone `dz` (pure, for tests).
static func value_for(offset: Vector2, r: float, dz: float) -> Vector2:
	var v: Vector2 = offset / maxf(r, 1.0)
	var n: float = v.length()
	if n <= dz:
		return Vector2.ZERO
	var k: float = (minf(n, 1.0) - dz) / (1.0 - dz)
	return v / n * k


func _gui_input(event: InputEvent) -> void:
	if TouchInput.is_emulated(event):
		accept_event()
		return
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t != null:
		accept_event()
		if t.pressed and _touch < 0 and not _mouse:
			_touch = t.index
			TouchInput.held += 1
			_drag(t.position)
		elif not t.pressed and t.index == _touch:
			_release()
		return
	var d: InputEventScreenDrag = event as InputEventScreenDrag
	if d != null:
		accept_event()
		if d.index == _touch:
			_drag(d.position)
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if mb.pressed and _touch < 0:
			_mouse = true
			_drag(mb.position)
		elif not mb.pressed and _mouse:
			_mouse = false
			_apply(Vector2.ZERO)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _mouse:
		accept_event()
		_drag(mm.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release()


func _exit_tree() -> void:
	_release()


## Lets go of the knob (focus loss, hiding, a finger lifted).
func _release() -> void:
	if _touch >= 0:
		TouchInput.held = maxi(TouchInput.held - 1, 0)
	_touch = -1
	_mouse = false
	_apply(Vector2.ZERO)


func _drag(local: Vector2) -> void:
	var offset: Vector2 = (local - size / 2.0).limit_length(radius())
	_apply(offset)


func _apply(offset: Vector2) -> void:
	_knob = offset
	queue_redraw()
	var v: Vector2 = value_for(offset, radius(), dead_zone)
	if v != value:
		value = v
		moved.emit(v)


func _draw() -> void:
	var c: Vector2 = size / 2.0
	var r: float = radius()
	draw_circle(c, r, Color(Palette.color("panel"), UiTheme.OVERLAY_ALPHA))
	draw_arc(c, r, 0.0, TAU, 48, Palette.color("line"), 2.0, true)
	draw_arc(c, r * 0.55, 0.0, TAU, 32, Color(Palette.color("line"), 0.6), 1.0, true)
	var k: Vector2 = c + _knob
	var held_now: bool = _touch >= 0 or _mouse
	draw_circle(k, r * 0.32, Palette.color("panel_focus"))
	draw_arc(k, r * 0.32, 0.0, TAU, 32, Palette.color("accent"), 3.0 if held_now else 2.0, true)
	if label != "":
		var font: Font = get_theme_default_font()
		var fs: int = UiTheme.SMALL_SIZE + 1
		var sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at: Vector2 = Vector2(c.x - sz.x / 2.0, c.y + r * 0.32 + fs + 4.0)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.color("text_dim"))
