class_name WeaponsAimPad
extends Control
## The turret view's touch surface on a phone (#28, Weapons B): one finger dragged across
## the view turns the camera mount's aim (`dragged`, px moved), a short tap without
## movement asks for the item under the finger (`tapped`, select, §5.0). It joins
## TouchInput.GROUP, so the screen never also reads the finger as a select or a fire
## (LMB). A real mouse passes through to the screen's bindings; the mouse Godot emulates
## from a finger is ignored. FIRE and the other actions stay on the rails.
##
## In the phone frame (P28-Common) a finger held still on the view long-presses: the pad
## hands its touch-down to the screen's LongPress (`long_press`), which the screen never
## feeds over a touch widget, and lets the finger go once it arms (no tap, no aim), so a
## held finger pings and a held then dragged one marks.

## The finger moved by `relative` px while held.
signal dragged(relative: Vector2)
## A tap at `pos` (this control's coordinates).
signal tapped(pos: Vector2)

## Movement (px) under which a touch still counts as a tap.
const TAP_SLOP: float = 12.0

## The screen's long-press while its panel is in the frame, else null.
var long_press: LongPress = null:
	set(value):
		if long_press != null and long_press.armed.is_connected(_on_armed):
			long_press.armed.disconnect(_on_armed)
		long_press = value
		if value != null:
			value.armed.connect(_on_armed)
## The clock for the long-press (ms), the screen's.
var now_ms: Callable = Callable()

var _touch: int = -1
var _from: Vector2 = Vector2.ZERO
var _moved: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_to_group(TouchInput.GROUP)


func _gui_input(event: InputEvent) -> void:
	if TouchInput.is_emulated(event):
		accept_event()
		return
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t != null:
		accept_event()
		if t.pressed and _touch < 0:
			_touch = t.index
			_from = t.position
			_moved = false
			TouchInput.held += 1
			if long_press != null and now_ms.is_valid():
				var g: InputEventScreenTouch = t.duplicate()
				g.position = get_global_transform_with_canvas() * t.position
				long_press.feed(g, int(now_ms.call()))
		elif not t.pressed and t.index == _touch:
			_release()
			if not _moved:
				tapped.emit(t.position)
		return
	var d: InputEventScreenDrag = event as InputEventScreenDrag
	if d != null and d.index == _touch:
		accept_event()
		if not _moved and d.position.distance_to(_from) < TAP_SLOP:
			return
		# The first move past the slop turns by the whole way from the touch-down point.
		var rel: Vector2 = d.relative if _moved else d.position - _from
		_moved = true
		dragged.emit(rel)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release()


func _exit_tree() -> void:
	_release()


## The long-press armed under this finger: the gesture owns it now.
func _on_armed(_at: Vector2) -> void:
	if _touch >= 0:
		_release()


func _release() -> void:
	if _touch >= 0:
		TouchInput.held = maxi(TouchInput.held - 1, 0)
	_touch = -1
