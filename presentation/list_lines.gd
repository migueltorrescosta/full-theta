class_name ListLines
extends RefCounted
## The 1 px divider between the rows of a list (D304, P28 design: `line` at 0.6 alpha, no box
## per row). attach() puts it on an ItemList or a container whose children are the rows (a
## vertical box; a grid, where a row is `columns` children); lists that draw their own rows
## call between() for each gap. The line sits in the gap between two rows.

const ALPHA: float = 0.6
const WIDTH: float = 1.0


static func color() -> Color:
	return Color(Palette.color("line"), ALPHA)


## Draws the divider at `y` from `x0` to `x1` on `item`; call it from a draw.
static func hline(item: CanvasItem, y: float, x0: float, x1: float) -> void:
	item.draw_line(Vector2(x0, y), Vector2(x1, y), color(), WIDTH)


## The divider in the gap between two rows given as rectangles (b below a).
static func between(item: CanvasItem, a: Rect2, b: Rect2) -> void:
	hline(item, roundf((a.end.y + b.position.y) / 2.0) + 0.5, a.position.x, a.end.x)


## Draws dividers on a list from now on: an ItemList, or a vertical BoxContainer or
## GridContainer of rows.
static func attach(list: Control) -> void:
	list.draw.connect(_draw_on.bind(list))
	if list is Container:
		(list as Container).sort_children.connect(list.queue_redraw)


static func _draw_on(list: Control) -> void:
	if list is ItemList:
		var items: ItemList = list as ItemList
		for i: int in range(1, items.item_count):
			between(items, items.get_item_rect(i - 1, false), items.get_item_rect(i, false))
		return
	var step: int = 1
	if list is GridContainer:
		step = maxi(1, (list as GridContainer).columns)
	var rows: Array[Rect2] = []
	var kids: Array[Node] = list.get_children()
	for i: int in range(0, kids.size(), step):
		var kid: Control = kids[i] as Control
		if kid != null and kid.visible:
			rows.append(Rect2(kid.position, Vector2(list.size.x, kid.size.y)))
	for i: int in range(1, rows.size()):
		between(list, rows[i - 1], rows[i])
