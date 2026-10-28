class_name TouchScroll
extends ScrollContainer
## A ScrollContainer that a finger drag always scrolls (#28, the Android Firefox check).
## Godot pans by touch only through the container's own gui input, which fails in two
## places: a press on a child that takes it (a full-width button or check box, mouse
## filter STOP) never reaches the container, and a display server that reports no
## touchscreen (some browsers) does not pan at all. So the container follows the finger
## itself, from `_input`, in just those two cases; elsewhere the engine pans and this adds
## nothing, so a drag never scrolls twice.

## The finger must travel this far (px) before it scrolls: a tap stays a tap.
const SLOP: float = 8.0

var _finger: int = -1
var _travel: float = 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if not t.pressed:
			if t.index == _finger:
				_finger = -1
		elif _finger == -1 and _takes(t.position):
			_finger = t.index
			_travel = 0.0
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _finger:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		_travel += d.relative.length()
		if _travel > SLOP:
			scroll_horizontal -= int(d.relative.x)
			scroll_vertical -= int(d.relative.y)
			get_viewport().set_input_as_handled()


## True when a press at `pos` is ours to follow: on the container, and either the engine
## would not pan (no touchscreen) or a child that takes presses sits under the finger.
func _takes(pos: Vector2) -> bool:
	if not is_visible_in_tree() or not get_global_rect().has_point(pos):
		return false
	return not DisplayServer.is_touchscreen_available() or _stopped_by_child(self, pos)


func _stopped_by_child(node: Node, pos: Vector2) -> bool:
	for child: Node in node.get_children():
		var c: Control = child as Control
		if c == null or not c.visible:
			continue
		if c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(pos):
			return true
		if _stopped_by_child(c, pos):
			return true
	return false
