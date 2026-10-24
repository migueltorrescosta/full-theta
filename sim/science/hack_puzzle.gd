class_name HackPuzzle
extends RefCounted
## The node-route hack (FT-SCI-006, D59), generated and checked on the server
## (FT-SCI-011). Nodes form a cols x rows grid, numbered row * cols + col. The route
## starts at the entry (first column, middle row) and must reach the goal, the chosen
## subsystem (last column). Edges join orthogonal neighbours; each node keeps a mask of
## its edges (RIGHT, DOWN, LEFT, UP). A route from entry to goal always exists. Some inner
## nodes start hidden; scans and probe coverage reveal them (FT-SCI-007), and stepping
## onto one reveals it. Everything derives from (def, seed, goal row), so the sim stores
## only those, the player's position and the known-node mask.

const RIGHT: int = 1
const DOWN: int = 2
const LEFT: int = 4
const UP: int = 8


static func entry(def: ScienceDef) -> int:
	return (def.hack_rows / 2) * def.hack_cols


## The goal node for a subsystem index: the last column, row by index.
static func goal(def: ScienceDef, subsystem_index: int) -> int:
	return (subsystem_index % def.hack_rows) * def.hack_cols + def.hack_cols - 1


## Edge mask per node.
static func edges(def: ScienceDef, puzzle_seed: int, goal_node: int) -> PackedByteArray:
	var cols: int = def.hack_cols
	var rng: RandomNumberGenerator = _rng(puzzle_seed, 11)
	var out: PackedByteArray = PackedByteArray()
	out.resize(cols * def.hack_rows)
	# The guaranteed route: right or toward the goal row, at random.
	var cur: int = entry(def)
	var goal_row: int = goal_node / cols
	while cur != goal_node:
		var r: int = cur / cols
		var c: int = cur % cols
		var go_right: bool = c < cols - 1
		var go_vert: bool = r != goal_row
		if go_right and go_vert:
			go_right = rng.randf() < 0.6
			go_vert = not go_right
		var nxt: int = cur + 1
		if go_vert:
			nxt = cur + cols if goal_row > r else cur - cols
		link(out, cols, cur, nxt)
		cur = nxt
	# Extra edges between orthogonal neighbours.
	for n: int in out.size():
		if n % cols < cols - 1 and rng.randf() < def.edge_density:
			link(out, cols, n, n + 1)
		if n / cols < def.hack_rows - 1 and rng.randf() < def.edge_density:
			link(out, cols, n, n + cols)
	return out


## Adds the edge between adjacent nodes a and b to both masks.
static func link(mask: PackedByteArray, cols: int, a: int, b: int) -> void:
	var d: int = b - a
	if d == 1:
		mask[a] |= RIGHT
		mask[b] |= LEFT
	elif d == -1:
		mask[a] |= LEFT
		mask[b] |= RIGHT
	elif d == cols:
		mask[a] |= DOWN
		mask[b] |= UP
	else:
		mask[a] |= UP
		mask[b] |= DOWN


## The node reached by taking the edge in direction bit `dir` from `from`, or -1.
static func neighbour(def: ScienceDef, from: int, dir: int) -> int:
	match dir:
		RIGHT:
			return from + 1 if from % def.hack_cols < def.hack_cols - 1 else -1
		LEFT:
			return from - 1 if from % def.hack_cols > 0 else -1
		DOWN:
			return from + def.hack_cols if from / def.hack_cols < def.hack_rows - 1 else -1
		UP:
			return from - def.hack_cols if from >= def.hack_cols else -1
	return -1


## Whether an edge joins the adjacent nodes a and b.
static func connected(mask: PackedByteArray, def: ScienceDef, a: int, b: int) -> bool:
	for dir: int in [RIGHT, DOWN, LEFT, UP]:
		if (mask[a] & dir) != 0 and neighbour(def, a, dir) == b:
			return true
	return false


## The hidden inner nodes in the order scans reveal them.
static func hidden_order(def: ScienceDef, puzzle_seed: int, goal_node: int) -> Array[int]:
	var rng: RandomNumberGenerator = _rng(puzzle_seed, 12)
	var inner: Array[int] = []
	for n: int in def.hack_cols * def.hack_rows:
		if n != entry(def) and n != goal_node:
			inner.append(n)
	for i: int in range(inner.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = inner[i]
		inner[i] = inner[j]
		inner[j] = tmp
	var count: int = roundi(def.hidden_fraction * inner.size())
	return inner.slice(0, count)


## Bit mask of the nodes the player sees at the start: all but the hidden ones, less
## the ones the scan confidence (and probe coverage) reveals (FT-SCI-007).
static func known_at_start(
	def: ScienceDef, puzzle_seed: int, goal_node: int, scan_conf: float, probe_covered: bool
) -> int:
	var all: int = (1 << (def.hack_cols * def.hack_rows)) - 1
	var hidden: Array[int] = hidden_order(def, puzzle_seed, goal_node)
	var share: float = clampf(scan_conf + (def.probe_reveal if probe_covered else 0.0), 0.0, 1.0)
	var shown: int = roundi(share * hidden.size())
	var known: int = all
	for i: int in hidden.size():
		if i >= shown:
			known &= ~(1 << hidden[i])
	return known


static func _rng(puzzle_seed: int, salt: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = puzzle_seed * 16 + salt
	return rng
