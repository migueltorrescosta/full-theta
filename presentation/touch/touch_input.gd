class_name TouchInput
extends RefCounted
## How the touch widgets of presentation/touch/ share the screen's input (#28).
##
## Every finger arrives as InputEventScreenTouch / ScreenDrag with its own index, so two
## thumbs work at once (a stick and FIRE). Godot also emulates a mouse from the first
## finger; the widgets ignore those emulated events, and StationScreen asks `owns` so a
## tap on a rail never also reaches the station's bindings (select, fire, steer).
## A widget joins GROUP and registers itself with `hold` while it holds a finger.

## Controls whose rectangle takes every touch and emulated mouse event over it.
const GROUP: StringName = &"ft_touch_owned"

## Instance ids of the widgets holding a finger right now.
static var _holders: Dictionary[int, bool] = {}


## `owner` holds a finger (idempotent).
static func hold(owner: Object) -> void:
	_holders[owner.get_instance_id()] = true


## `owner` let go of its finger (idempotent).
static func release(owner: Object) -> void:
	_holders.erase(owner.get_instance_id())


## True while any touch widget holds a finger.
static func is_held() -> bool:
	return not _holders.is_empty()


## Widgets holding a finger right now.
static func held_count() -> int:
	return _holders.size()


## Forgets every holder (tests: tests/ui_overrides_hook.gd).
static func reset() -> void:
	_holders.clear()


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
		if is_held():
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
