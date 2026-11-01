class_name LongPress
extends RefCounted
## Long-press gestures on a phone's view (#28 follow-up, P28-Common, spec §5.0 touch): one
## finger held still for HOLD_MS arms the gesture; let go there to ping what is under it,
## or drag first and let go to place a mark where the finger ends. A finger that moves
## more than SLOP px before HOLD_MS is an ordinary drag (aim, pan) and never arms; a second
## finger cancels. Positions are the events' (viewport px).
##
##     var lp := LongPress.new()
##     lp.ping.connect(func(at: Vector2) -> void: _ping_at(at))
##     lp.mark.connect(func(at: Vector2) -> void: _mark_at(at))
##     # in _input: if lp.feed(event, now_ms): accept the event
##     # in _process: lp.update(now_ms)

## The finger has been held HOLD_MS (show feedback at `at`).
signal armed(at: Vector2)
## Released where it armed: ping under `at`.
signal ping(at: Vector2)
## Released after dragging from where it armed: mark at `at`.
signal mark(at: Vector2)

const HOLD_MS: int = 500
const SLOP: float = 12.0

var _index: int = -1
var _start: Vector2 = Vector2.ZERO
var _at: Vector2 = Vector2.ZERO
var _since: int = 0
var _armed: bool = false
var _dragged: bool = false
var _fingers: int = 0


## True while the gesture is armed (the screen then keeps the finger's events).
func is_armed() -> bool:
	return _armed


## Feeds a touch event at now_ms; true when the gesture owns it (armed, or its release).
func feed(event: InputEvent, now_ms: int) -> bool:
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t != null:
		if t.pressed:
			_fingers += 1
			if _fingers == 1:
				_index = t.index
				_start = t.position
				_at = t.position
				_since = now_ms
				_armed = false
				_dragged = false
			else:
				_reset()
			return false
		_fingers = maxi(_fingers - 1, 0)
		if t.index != _index:
			return false
		update(now_ms)
		var was: bool = _armed
		if _armed:
			if _dragged:
				mark.emit(t.position)
			else:
				ping.emit(t.position)
		_reset()
		return was
	var d: InputEventScreenDrag = event as InputEventScreenDrag
	if d != null and d.index == _index:
		_at = d.position
		if not _armed and _at.distance_to(_start) > SLOP:
			_reset()
			return false
		if _armed and _at.distance_to(_start) > SLOP:
			_dragged = true
		return _armed
	return false


## Arms the gesture once the finger has been held still for HOLD_MS.
func update(now_ms: int) -> void:
	if _index >= 0 and not _armed and now_ms - _since >= HOLD_MS:
		_armed = true
		armed.emit(_at)


func _reset() -> void:
	_index = -1
	_armed = false
	_dragged = false
