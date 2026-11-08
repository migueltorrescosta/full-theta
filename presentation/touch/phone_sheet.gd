class_name PhoneSheet
extends RefCounted
## The phone placement shared by the shell's full-screen overlays (pause, outcome, vote,
## handover; #28 follow-up, design 2.13): whether a node is on a phone, fitting a sheet to
## the safe tap area, putting it back as the shell's centred card, and following the
## viewport's size.


## Whether `node` shows on a phone (LayoutMode.Kind.PHONE).
static func is_phone(node: Node) -> bool:
	return LayoutMode.kind_of(node) == LayoutMode.Kind.PHONE


## Fits `control` to the safe tap area (SafeArea.tap_rect), cut to start no higher than
## `below_top` and end no lower than `above_bottom` (viewport px), in its parent's
## coordinates. Sets nothing when it already fits, so a `resized` handler doesn't loop.
static func fit(control: Control, below_top: float = -INF, above_bottom: float = INF) -> void:
	var r: Rect2 = SafeArea.tap_rect(control)
	if below_top > -INF or above_bottom < INF:
		var top: float = maxf(r.position.y, below_top)
		var bottom: float = minf(r.end.y, above_bottom)
		r = Rect2(r.position.x, top, r.size.x, maxf(bottom - top, 0.0))
	var parent: Control = control.get_parent() as Control
	if parent != null:
		r = SafeArea.to_local(parent, r)
	if control.position != r.position or control.size != r.size:
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		control.custom_minimum_size = r.size
		control.position = r.position
		control.size = r.size


## Puts a fitted `control` back as a card centred in its parent, sized by its content.
static func unfit(control: Control) -> void:
	control.custom_minimum_size = Vector2.ZERO
	control.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH


## Calls `place` whenever the viewport of `control` changes size, connecting once (call it
## from `_enter_tree`); with `min_size` also (deferred) when the control's minimum size
## changes. Returns whether it connected now.
static func follow_viewport(control: Control, place: Callable, min_size: bool = false) -> bool:
	var vp: Viewport = control.get_viewport()
	if vp.size_changed.is_connected(place):
		return false
	vp.size_changed.connect(place)
	if min_size:
		control.minimum_size_changed.connect(place, Object.CONNECT_DEFERRED)
	return true
