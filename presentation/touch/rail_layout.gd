class_name RailLayout
extends Control
## A station's phone-landscape arrangement (#28): a view (`content`) with a thumb rail at
## the left and/or right edge and drawers beside the rails. Fill the station panel with
## it. Rails reach from the top to the tap limit (SafeArea: never into the gesture band
## or under an inset); the view fills everything.
##
## `docked` rails sit beside the view, which narrows to the space between them (Weapons).
## Overlay rails float over a full-size view (Science, Relay, Helm); a hand-drawn view
## keeps its read-outs clear of them with `content_rect_in(view)`, the uncovered part in
## the view's own coordinates, and redraws on `content_rect_changed`; a view with a
## `view_rect` property (DiscRadar) gets it set to that part.
##
##     var layout := RailLayout.new()
##     panel.add_child(layout)
##     layout.set_content(hud)
##     layout.rail(SIDE_LEFT).add(throttle)
##     layout.content_rect_changed.connect(hud.queue_redraw)
##     # in hud._draw(): var free: Rect2 = layout.content_rect_in(self)

## The uncovered part of the view changed (rails shown, hidden or resized; a rotation).
signal content_rect_changed(rect: Rect2)

## Rails beside the view (true) or over it (false).
var docked: bool = false:
	set(value):
		docked = value
		for r: TouchRail in [left, right]:
			if r != null:
				r.docked = value
		queue_sort()
## The view; null until set_content.
var content: Control = null
var left: TouchRail = null
var right: TouchRail = null
var drawers: Array[TouchDrawer] = []

var _content_rect: Rect2 = Rect2()
var _sorting: bool = false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	get_viewport().size_changed.connect(queue_sort)
	queue_sort()


## Puts `view` under the rails (replacing an earlier one, which is removed, not freed).
func set_content(view: Control) -> void:
	if content != null and content.get_parent() == self:
		remove_child(content)
	content = view
	if view.get_parent() != null:
		view.reparent(self, false)
	else:
		add_child(view)
	move_child(view, 0)
	queue_sort()


## The rail on `side` (SIDE_LEFT or SIDE_RIGHT), made on first use.
func rail(side: Side) -> TouchRail:
	var r: TouchRail = left if side == SIDE_LEFT else right
	if r == null:
		r = TouchRail.new(side, docked)
		r.visibility_changed.connect(queue_sort)
		r.resized.connect(queue_sort)
		add_child(r)
		if side == SIDE_LEFT:
			left = r
		else:
			right = r
	return r


## Adds a drawer beside the rail of its side, over the view.
func add_drawer(drawer: TouchDrawer) -> TouchDrawer:
	drawers.append(drawer)
	add_child(drawer)
	drawer.toggled.connect(func(_open: bool) -> void: queue_sort())
	queue_sort()
	return drawer


## The part of the view no rail covers, in this layout's coordinates.
func content_rect() -> Rect2:
	return _content_rect


## `content_rect` in the coordinates of `control` (a hand-drawn view).
func content_rect_in(control: Control) -> Rect2:
	var xf: Transform2D = control.get_global_transform().affine_inverse() * get_global_transform()
	return xf * _content_rect


## The rectangle taps may use, in this layout's coordinates.
func tap_area() -> Rect2:
	var full: Rect2 = Rect2(Vector2.ZERO, size)
	if not is_inside_tree():
		return full
	return full.intersection(SafeArea.to_local(self, SafeArea.tap_rect(self)))


func queue_sort() -> void:
	if not _sorting:
		_sorting = true
		_sort.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_sort()


func _sort() -> void:
	if not is_inside_tree():
		_sorting = false
		return
	var area: Rect2 = tap_area()
	var lw: float = _width(left)
	var rw: float = _width(right)
	if left != null:
		_place(left, Rect2(area.position.x, area.position.y, lw, area.size.y))
	if right != null:
		_place(right, Rect2(area.end.x - rw, area.position.y, rw, area.size.y))
	var gap: float = UiTheme.TOUCH_GAP
	var free_l: float = area.position.x + lw + (gap if lw > 0.0 else 0.0)
	var free_r: float = area.end.x - rw - (gap if rw > 0.0 else 0.0)
	if content != null:
		if docked:
			var from: float = area.position.x + lw if lw > 0.0 else 0.0
			var to: float = area.end.x - rw if rw > 0.0 else size.x
			_place(content, Rect2(from, 0.0, to - from, size.y))
		else:
			_place(content, Rect2(Vector2.ZERO, size))
	for d: TouchDrawer in drawers:
		if not d.visible:
			continue
		var w: float = d.get_combined_minimum_size().x
		var x: float = free_l if d.side == SIDE_LEFT else free_r - w
		_place(d, Rect2(x, area.position.y, w, area.size.y))
	var r: Rect2 = Rect2(free_l, 0.0, maxf(free_r - free_l, 0.0), size.y)
	if docked and content != null:
		r = Rect2(content.position, content.size)
	_sorting = false
	if r != _content_rect:
		_content_rect = r
		# A view that keeps its own controls to a `view_rect` (DiscRadar, RelayMap) keeps
		# them off the overlay rails; a station may still set its own on the signal.
		if content != null and content.get_parent() == self and "view_rect" in content:
			content.set("view_rect", Rect2() if docked else content_rect_in(content))
		content_rect_changed.emit(r)


func _width(r: TouchRail) -> float:
	if r == null or not r.visible:
		return 0.0
	return r.get_combined_minimum_size().x


func _place(c: Control, r: Rect2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = r.position
	c.size = r.size
