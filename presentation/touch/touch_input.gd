class_name TouchInput
extends RefCounted
## How the touch widgets of presentation/touch/ share the screen's input (#28).
##
## Every finger arrives as InputEventScreenTouch / ScreenDrag with its own index, so two
## thumbs work at once (a stick and FIRE). Godot also emulates a mouse from the first
## finger; the widgets ignore those emulated events, and StationScreen asks `owns` so a
## tap on a rail never also reaches the station's bindings (select, fire, steer).
## A widget joins GROUP and counts its held fingers in `held`.

## Controls whose rectangle takes every touch and emulated mouse event over it.
const GROUP: StringName = &"ft_touch_owned"

## Fingers held by touch widgets right now.
static var held: int = 0


## True for a mouse event Godot made from a finger.
static func is_emulated(event: InputEvent) -> bool:
	return event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION


## True when `event` belongs to a touch widget: a touch or emulated mouse event over a
## visible member of GROUP, or any emulated mouse event while a widget holds a finger.
static func owns(tree: SceneTree, event: InputEvent) -> bool:
	var pos: Vector2
	if event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
	elif is_emulated(event):
		if held > 0:
			return true
		pos = (event as InputEventMouse).position
	else:
		return false
	return over(tree, pos)


## True when `pos` (viewport px) is over a visible member of GROUP.
static func over(tree: SceneTree, pos: Vector2) -> bool:
	for n: Node in tree.get_nodes_in_group(GROUP):
		var c: Control = n as Control
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false
