class_name ThrottleSlider
extends Control
## A vertical thumb slider for a throttle (#28; FT §5.1 touch). A finger anywhere on it
## sets `value` from its height (top = max_value, bottom = min_value) and drags it; the
## value stays where it is let go. Snaps to `step`; with a min_value below zero the zero
## line is drawn and `detent` around it reads as zero. A mouse drives it too; the mouse
## Godot emulates from a finger is ignored.
##
##     var throttle := ThrottleSlider.new()
##     throttle.value_changed.connect(func(v: float) -> void: _set_throttle(v))

signal value_changed(value: float)

## Least width; the height should be most of a rail.
const MIN_WIDTH: float = 48.0
const MIN_HEIGHT: float = 160.0
## Height of the read-out at the top, px.
const LABEL_H: float = 22.0

var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.05
## Around zero (when min_value < 0), the share of the range that snaps to zero.
var detent: float = 0.05
## The read-out: a format with one %d of the value in percent.
var label_format: String = "%d%%"
var value: float = 0.0:
	set(v):
		value = clampf(v, min_value, max_value)
		queue_redraw()

var _touch: int = -1
var _mouse: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(TouchInput.GROUP)


## The track (local px) the value maps onto.
func track() -> Rect2:
	return Rect2(Vector2(0.0, LABEL_H), Vector2(size.x, maxf(size.y - LABEL_H - 6.0, 1.0)))


## The value for a finger at local height `y` (snapped, with the zero detent).
func value_at(y: float) -> float:
	var t: Rect2 = track()
	var k: float = clampf(1.0 - (y - t.position.y) / t.size.y, 0.0, 1.0)
	var v: float = lerpf(min_value, max_value, k)
	if min_value < 0.0 and absf(v) <= detent * (max_value - min_value):
		v = 0.0
	if step > 0.0:
		v = snappedf(v, step)
	return clampf(v, min_value, max_value)


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
			_apply(value_at(t.position.y))
		elif not t.pressed and t.index == _touch:
			_release()
		return
	var d: InputEventScreenDrag = event as InputEventScreenDrag
	if d != null:
		accept_event()
		if d.index == _touch:
			_apply(value_at(d.position.y))
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_mouse = mb.pressed and _touch < 0
		if _mouse:
			_apply(value_at(mb.position.y))
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _mouse:
		accept_event()
		_apply(value_at(mm.position.y))


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release()


func _exit_tree() -> void:
	_release()


func _release() -> void:
	if _touch >= 0:
		TouchInput.held = maxi(TouchInput.held - 1, 0)
	_touch = -1
	_mouse = false


func _apply(v: float) -> void:
	if is_equal_approx(v, value):
		return
	value = v
	value_changed.emit(value)


## The track height of `v` (local y).
func _y_of(v: float) -> float:
	var t: Rect2 = track()
	var k: float = inverse_lerp(min_value, max_value, v)
	return t.position.y + t.size.y * (1.0 - k)


func _draw() -> void:
	var sb: StyleBoxFlat = UiTheme.box("panel", "line_strong", 0, 0)
	sb.bg_color = Color(sb.bg_color, UiTheme.OVERLAY_ALPHA)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var t: Rect2 = track()
	var zero: float = _y_of(clampf(0.0, min_value, max_value))
	var at: float = _y_of(value)
	var fill: Rect2 = Rect2(10.0, minf(zero, at), size.x - 20.0, absf(zero - at))
	draw_rect(fill, Color(Palette.color("ok"), 0.55))
	if min_value < 0.0:
		draw_line(Vector2(4.0, zero), Vector2(size.x - 4.0, zero), Palette.color("line"), 1.0)
	draw_rect(Rect2(4.0, at - 3.0, size.x - 8.0, 6.0), Palette.color("text"))
	var font: Font = get_theme_default_font()
	var fs: int = UiTheme.SMALL_SIZE + 1
	var txt: String = label_format % roundi(value * 100.0)
	var sz: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(
		font,
		Vector2((size.x - sz.x) / 2.0, t.position.y - 6.0),
		txt,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		Palette.color("text")
	)
