class_name ScienceFixture
extends RefCounted
## Worlds and a scripted solver for the Science tests (E01): the M1 corvette (faction 1,
## ship 0) with the science definition, and a raider (faction 2, ship 1) at a given
## range, either broadside (aspect 0, least noise) or bow-on (aspect 1).

const BLUE: int = 1
const RED: int = 2
const ME: int = 0
const FOE: int = 1


static func science() -> ScienceDef:
	return load("res://content/science/science.tres") as ScienceDef


## The raider with a weak point on its first subsystem and a kinetic resistance, as
## copies (definitions are read-only, FT-ARC-020).
static func weak_raider() -> ShipDef:
	var def: ShipDef = TestDefs.raider().duplicate()
	var subs: Array[SubsystemDef] = []
	subs.assign(def.subsystems.duplicate())
	var first: SubsystemDef = subs[0].duplicate()
	first.weak_point = true
	subs[0] = first
	def.subsystems = subs
	def.resistances = {&"kinetic": 0.5}
	return def


static func world(
	dist: float = 6000.0, broadside: bool = true, foe: ShipDef = null, world_seed: int = 7
) -> SimWorld:
	var w: SimWorld = SimWorld.new(world_seed)
	w.science_def = science()
	w.spawn_ship(TestDefs.corvette(), BLUE)
	var facing: Quaternion = Quaternion(Vector3.UP, PI / 2.0 if broadside else 0.0)
	w.spawn_ship(foe if foe != null else TestDefs.raider(), RED, Vector3(0, 0, -dist), facing)
	w.step()
	return w


## A deployed probe of the ship's faction on the contact, so the contact is in coverage.
static func cover(w: SimWorld, contact: int = FOE, ship: int = ME) -> void:
	var p: PackedFloat64Array = w.kin.point_at(contact, Vector3.ZERO)
	var at: Vector3 = Vector3(p[0], p[1], p[2])
	var row: int = w.probes.launch(ship, w.faction_of(ship), 0, at, at)
	w.probes.deployed[row] = 1
	KnowledgeSystem.step(w)


## Submits the command, steps one tick and returns the events of that tick.
static func do(w: SimWorld, c: SimCommand, ship: int = ME) -> Array[SimEvent]:
	c.ship_id = ship
	w.submit(c)
	w.step()
	return w.drain_events()


static func scan_cmd(contact: int = FOE) -> ScienceScanCommand:
	var c: ScienceScanCommand = ScienceScanCommand.new()
	c.contact = contact
	return c


static func hack_cmd(subsystem: StringName, contact: int = FOE) -> ScienceHackCommand:
	var c: ScienceHackCommand = ScienceHackCommand.new()
	c.contact = contact
	c.subsystem_id = subsystem
	return c


static func move_cmd(node: int) -> ScienceHackMoveCommand:
	var c: ScienceHackMoveCommand = ScienceHackMoveCommand.new()
	c.node = node
	return c


static func submit_cmd(angles: Vector3) -> ScienceScanSubmitCommand:
	var c: ScienceScanSubmitCommand = ScienceScanSubmitCommand.new()
	c.ax = angles.x
	c.ay = angles.y
	c.az = angles.z
	return c


## The exact angles of the open scan's hidden pose.
static func solution(w: SimWorld, ship: int = ME) -> Vector3:
	var t: ScienceTable = w.science
	return ScanPuzzle.target_angles(w.science_def, t.puzzle_seed[ship], t.axes[ship])


## Runs a complete exact scan and returns its scan_done event.
static func scan_exactly(w: SimWorld) -> SimEvent:
	do(w, scan_cmd())
	var events: Array[SimEvent] = do(w, submit_cmd(solution(w)))
	return SimFixture.of_kind(events, &"scan_done")[0]


## Shortest route (node list after the entry) of the open hack, over all edges.
static func route(w: SimWorld, ship: int = ME) -> Array[int]:
	var def: ScienceDef = w.science_def
	var t: ScienceTable = w.science
	var goal: int = HackPuzzle.goal(def, t.subsystem[ship])
	var edges: PackedByteArray = HackPuzzle.edges(def, t.puzzle_seed[ship], goal)
	var start: int = HackPuzzle.entry(def)
	var came: Dictionary[int, int] = {start: -1}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		if n == goal:
			break
		for dir: int in [HackPuzzle.RIGHT, HackPuzzle.DOWN, HackPuzzle.LEFT, HackPuzzle.UP]:
			var m: int = HackPuzzle.neighbour(def, n, dir)
			if (edges[n] & dir) != 0 and m >= 0 and not came.has(m):
				came[m] = n
				queue.append(m)
	var out: Array[int] = []
	var at: int = goal
	while at != start:
		out.push_front(at)
		at = came[at]
	return out
