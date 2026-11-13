class_name SheetCover
extends RefCounted
## The opaque boxes (a choice sheet, the Captain's lists) that cover part of a canvas, so a
## radar or map under them hides what they would cut in half: a chip, the range label or
## the span caption peeking out at an edge reads as a bug (D319). A box registers while it
## is in the tree; only shown ones count.

static var _boxes: Array[Control] = []


## Forgets every box (tests, via UiOverrides.reset).
static func reset() -> void:
	_boxes.clear()


static func register(box: Control) -> void:
	if not _boxes.has(box):
		_boxes.append(box)
		box.tree_exiting.connect(func() -> void: _boxes.erase(box), CONNECT_ONE_SHOT)


## The shown boxes that overlap `canvas`, as rects in its coordinates.
static func over(canvas: Control) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not canvas.is_inside_tree():
		return out
	var here: Rect2 = canvas.get_global_rect()
	var inverse: Transform2D = canvas.get_global_transform().affine_inverse()
	for box: Control in _boxes:
		if is_instance_valid(box) and box.is_visible_in_tree():
			var rect: Rect2 = box.get_global_rect()
			if rect.intersects(here):
				out.append(inverse * rect)
	return out


## True when `rect` touches any of `covers`.
static func touches(rect: Rect2, covers: Array[Rect2]) -> bool:
	for c: Rect2 in covers:
		if c.intersects(rect):
			return true
	return false
