class_name HackGame
extends Control
## The node-route hack (§5.4, FT-SCI-006, FT-SCI-013, D59): a grid of nodes with the route
## entering at the middle of the left column; find a path to the chosen subsystem's node
## in the last column before the trace bar fills. Nodes the scans and probes haven't
## revealed show "?" and their edges only appear once the route has stood on one end.
## The server checks every move (FT-SCI-011). Moves: arrows, d-pad or stick, or a tap on
## an adjacent node; a step onto a hidden node is allowed along a known node's edge.

signal moved(node: int)
signal cancelled

## Edge bits of a node's mask (HackPuzzle).
const RIGHT: int = 1
const DOWN: int = 2
const LEFT: int = 4
const UP: int = 8
const FONT_SIZE: int = 15
const NODE_R: float = 18.0
const BUTTON_W: float = 110.0
const BUTTON_H: float = 34.0

var cols: int = 0
var rows: int = 0
var node: int = -1
var goal: int = -1
var known: int = 0
var trace: float = 0.0
var edges: Array = []
var title: String = ""
var target_text: String = ""
var elapsed_s: float = 0.0
var entry: int = -1


func load_block(block: Dictionary) -> void:
	cols = int(block.get("hack_cols", 0))
	rows = int(block.get("hack_rows", 0))
	node = int(block.get("hack_node", -1))
	goal = int(block.get("hack_goal", -1))
	known = int(block.get("known", 0))
	trace = float(block.get("trace", 0.0))
	edges = block.get("edges", [])
	entry = (rows / 2) * cols
	queue_redraw()


## The node reached by stepping `dir` (RIGHT, DOWN, LEFT, UP) from the route, or -1 when
## the grid ends there or no known edge leads that way.
func step_target(dir: int) -> int:
	if node < 0 or node >= edges.size() or (int(edges[node]["mask"]) & dir) == 0:
		return -1
	match dir:
		RIGHT:
			return node + 1 if node % cols < cols - 1 else -1
		LEFT:
			return node - 1 if node % cols > 0 else -1
		DOWN:
			return node + cols if node / cols < rows - 1 else -1
		UP:
			return node - cols if node >= cols else -1
	return -1


## Steps the route in a direction; true when a move was sent.
func step(dir: int) -> bool:
	var n: int = step_target(dir)
	if n < 0:
		return false
	moved.emit(n)
	return true


## The direction from the route to the adjacent node n, or 0.
func direction_to(n: int) -> int:
	for d: int in [RIGHT, DOWN, LEFT, UP]:
		if step_target(d) == n:
			return d
	return 0


func node_centre(n: int) -> Vector2:
	var area: Rect2 = _grid_rect()
	var gap: Vector2 = Vector2(area.size.x / maxf(cols - 1, 1), area.size.y / maxf(rows - 1, 1))
	return area.position + Vector2((n % cols) * gap.x, (n / cols) * gap.y)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	accept_event()
	if _button_rect().has_point(mb.position):
		cancelled.emit()
		return
	for n: int in cols * rows:
		if node_centre(n).distance_to(mb.position) <= NODE_R * 1.6:
			var d: int = direction_to(n)
			if d != 0:
				step(d)
			return


func _grid_rect() -> Rect2:
	return Rect2(Vector2(60.0, 80.0), Vector2(maxf(size.x - 120.0, 1.0), maxf(size.y - 190.0, 1.0)))


func _button_rect() -> Rect2:
	return Rect2(
		Vector2(size.x - 12.0 - BUTTON_W, size.y - BUTTON_H - 10.0), Vector2(BUTTON_W, BUTTON_H)
	)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("panel"))
	draw_string(
		font,
		Vector2(12.0, 22.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		Palette.color("text")
	)
	if cols <= 0 or rows <= 0:
		return
	var line: Color = Palette.color("line")
	for n: int in mini(edges.size(), cols * rows):
		var mask: int = int(edges[n]["mask"])
		if mask & RIGHT and n % cols < cols - 1:
			draw_line(node_centre(n), node_centre(n + 1), line, 3.0, true)
		if mask & DOWN and n / cols < rows - 1:
			draw_line(node_centre(n), node_centre(n + cols), line, 3.0, true)
	var reach: Array[int] = []
	for d: int in [RIGHT, DOWN, LEFT, UP]:
		reach.append(step_target(d))
	for n: int in cols * rows:
		_draw_node(font, n, reach)
	_draw_footer(font)


func _draw_node(font: Font, n: int, reach: Array[int]) -> void:
	var c: Vector2 = node_centre(n)
	var is_known: bool = (known >> n) & 1 == 1
	var col: Color = Palette.color("text") if is_known else Palette.color("text_dim")
	if n == goal:
		col = Palette.color("danger")
	if n == node:
		col = Palette.color("ok")
	draw_circle(c, NODE_R, Palette.color("background"))
	draw_arc(c, NODE_R, 0.0, TAU, 24, col, 2.5 if n in reach or n == node else 1.5, true)
	var label: String = ""
	if n == goal:
		label = target_text
	elif n == entry:
		label = tr("sci.hack_in")
	elif not is_known:
		label = "?"
	if label != "":
		draw_string(
			font,
			c + Vector2(-NODE_R, 5.0),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			NODE_R * 2.0,
			FONT_SIZE - 3,
			col
		)


func _draw_footer(font: Font) -> void:
	var y: float = size.y - BUTTON_H - 22.0
	var bar: Rect2 = Rect2(Vector2(12.0, y - 10.0), Vector2(size.x * 0.4, 14.0))
	draw_rect(bar, Palette.color("background"))
	var fill: Color = Palette.color("danger") if trace > 0.75 else Palette.color("warn")
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(trace, 0.0, 1.0), bar.size.y)), fill)
	draw_rect(bar, Palette.color("line"), false, 1.0)
	draw_string(
		font,
		Vector2(bar.end.x + 10.0, y + 2.0),
		"%s  %d s" % [tr("sci.trace"), roundi(elapsed_s)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		Palette.color("text")
	)
	var r: Rect2 = _button_rect()
	draw_rect(r, Palette.color("panel_focus"))
	draw_rect(r, Palette.color("line"), false, 1.0)
	draw_string(
		font,
		r.position + Vector2(10.0, 23.0),
		tr("sci.cancel"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		Palette.color("text")
	)
