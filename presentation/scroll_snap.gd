class_name ScrollSnap
extends RefCounted
## Sizes a scrolling column's view to whole rows (D319): when the content overflows, the
## room under the last row that fits becomes a margin under the scroll, so no row, heading
## or button is cut at rest. The scroll sits in a MarginContainer; call fit() after the
## content or the view changes (deferred, once the layout has settled). A control with a
## `row_bottoms()` method (a list that draws its own rows) names its row edges itself.


## Sets `margin`'s bottom margin from `scroll`'s view and `content`'s rows.
static func fit(scroll: ScrollContainer, margin: MarginContainer, content: Control) -> void:
	if not scroll.is_inside_tree():
		return
	var now: int = margin.get_theme_constant("margin_bottom")
	var room: float = scroll.size.y + float(now)
	var keep: float = 0.0
	if content.get_combined_minimum_size().y > room:
		var best: float = 0.0
		for bottom: float in bottoms(content, content):
			if bottom <= room + 0.5:
				best = maxf(best, bottom)
		keep = room - best if best > 0.0 else 0.0
	if int(keep) != now:
		margin.add_theme_constant_override("margin_bottom", int(keep))


## The bottom edges (px, in `root`'s coordinates) of the rows under `node`: each visible
## leaf control, and each row of a list that names its own.
static func bottoms(node: Control, root: Control) -> Array[float]:
	var out: Array[float] = []
	var top: float = root.get_global_rect().position.y
	for child: Node in node.get_children():
		var c: Control = child as Control
		if c == null or not c.visible:
			continue
		var y: float = c.get_global_rect().position.y - top
		if c.has_method(&"row_bottoms"):
			for edge: float in c.call(&"row_bottoms"):
				out.append(y + edge)
			continue
		out.append(c.get_global_rect().end.y - top)
		out.append_array(bottoms(c, root))
	return out
