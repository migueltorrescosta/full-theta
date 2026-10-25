class_name ScienceView
extends RefCounted
## The SCIENCE snapshot section (StationViews.BLOCKS[Section.SCIENCE], E01): what a
## Science client draws and plays, read from a (copied) world for the ship and its
## faction's knowledge. Pure reads; the field set is in StationViews.
##
## Client API for the minigames (the panels are strand E's):
## - Scan: when `session` is 1, `wire` is the wireframe the player turns, `cloud` the
##   point cloud to match, `axes` the open rotation axes (bit 0 x, 1 y, 2 z). The player
##   sets an angle per open axis; the pose is Basis.from_euler(Vector3(ax, ay, az)) with
##   the closed axes at 0. The client sends `science_scan_submit` {ax, ay, az}; the
##   result arrives as the `scan_done` event (value confidence, vector.x match quality).
## - Hack: when `session` is 2, nodes are numbered row * hack_cols + col; `known` is the
##   bit mask of visible nodes, `edges[n].mask` the edge bits of node n (RIGHT 1, DOWN 2,
##   LEFT 4, UP 8; 0 for a node not yet known); `hack_node` is where the route is,
##   `hack_goal` the chosen subsystem's node, `trace` the bar (0..1). The client sends
##   `science_hack_move` {node} for an adjacent node; `hack_done` or `hack_traced`
##   ends it. Unknown nodes can still be stepped onto along a known node's edge.
## - The open session started on tick `session_start`; its age is the snapshot tick
##   minus that.

## Most card rows (the wire format counts rows in a byte).
const MAX_CARDS: int = 255


## The class id sent for a ship definition id (a stable hash; the client maps it back
## through its own definitions) and for a damage type.
static func code(id: StringName) -> int:
	return String(id).hash()


static func block(world: SimWorld, ship: int) -> Dictionary:
	var t: ScienceTable = world.science
	var out: Dictionary = _empty()
	out["active"] = t.active[ship] == 1
	out["ping_left"] = t.ping_left[ship]
	out["ping_cool"] = t.ping_cool[ship]
	out["selected"] = t.selected[ship]
	out["mark_contact"] = t.mark_contact[ship]
	out["mark_site"] = t.mark_site[ship]
	out["mark_pos"] = Vector3(t.mark_x[ship], t.mark_y[ship], t.mark_z[ship])
	out["self_scanned"] = t.self_scanned[ship] >= 0
	_preview(out, t.preview[ship])
	if world.science_def != null:
		_session(out, world, ship)
		out["cards"] = _cards(world, ship)
		out["hacks"] = hacks(world, world.faction_of(ship))
	return out


static func _empty() -> Dictionary:
	return {
		"active": false,
		"ping_left": 0.0,
		"ping_cool": 0.0,
		"selected": -1,
		"noise": 0.0,
		"noise_range": 0.0,
		"noise_aspect": 0.0,
		"noise_health": 0.0,
		"noise_flags": 0,
		"mark_contact": -1,
		"mark_site": 0,
		"mark_pos": Vector3.ZERO,
		"self_scanned": false,
		"session": 0,
		"session_target": -1,
		"session_noise": 0.0,
		"session_start": 0,
		"session_probe": false,
		"axes": 0,
		"wire": [],
		"cloud": [],
		"hack_cols": 0,
		"hack_rows": 0,
		"hack_node": -1,
		"hack_goal": -1,
		"hack_sub": -1,
		"trace": 0.0,
		"known": 0,
		"edges": [],
		"cards": [],
		"hacks": [],
	}


static func _preview(out: Dictionary, parts: Dictionary) -> void:
	if parts.is_empty():
		return
	out["noise"] = parts["noise"]
	out["noise_range"] = parts["range"]
	out["noise_aspect"] = parts["aspect"]
	out["noise_health"] = parts["health"]
	out["noise_flags"] = (
		(1 if parts["active"] else 0)
		| (2 if parts["ping"] else 0)
		| (4 if parts["probe"] else 0)
		| (8 if parts["mark"] else 0)
	)


static func _session(out: Dictionary, world: SimWorld, ship: int) -> void:
	var t: ScienceTable = world.science
	var def: ScienceDef = world.science_def
	var kind: int = t.kind[ship]
	out["session"] = kind
	if kind == ScienceTable.Session.NONE:
		return
	out["session_target"] = t.target[ship]
	out["session_noise"] = t.noise[ship]
	out["session_start"] = t.start_tick[ship]
	out["session_probe"] = t.probe[ship] == 1
	if kind == ScienceTable.Session.SCAN:
		out["axes"] = t.axes[ship]
		out["wire"] = _points(ScanPuzzle.wire(def, t.puzzle_seed[ship]))
		out["cloud"] = _points(
			ScanPuzzle.cloud(def, t.puzzle_seed[ship], t.noise[ship], t.axes[ship])
		)
	elif kind == ScienceTable.Session.HACK:
		var goal: int = HackPuzzle.goal(def, t.subsystem[ship])
		var edges: PackedByteArray = HackPuzzle.edges(def, t.puzzle_seed[ship], goal)
		var known: int = t.known[ship]
		var rows: Array = []
		for n: int in edges.size():
			rows.append({"mask": edges[n] if (known >> n) & 1 == 1 else 0})
		out["hack_cols"] = def.hack_cols
		out["hack_rows"] = def.hack_rows
		out["hack_node"] = t.node[ship]
		out["hack_goal"] = goal
		out["hack_sub"] = t.subsystem[ship]
		out["trace"] = t.trace[ship]
		out["known"] = known
		out["edges"] = rows


static func _points(points: PackedVector3Array) -> Array:
	return Array(points).map(func(p: Vector3) -> Dictionary: return {"p": p})


## One card per contact the faction detects or has scanned (FT-SCI-001, FT-SCI-002):
## detection confidence for the icon size, the scan confidence, and each part only once
## its threshold is reached (class id, intent as AI mode + 1, weak-point subsystem mask,
## resistances), 0 or empty before.
static func _cards(world: SimWorld, ship: int) -> Array:
	var faction: int = world.faction_of(ship)
	var k: KnowledgeTable = world.knowledge
	var rows: Array = []
	for r: int in k.size():
		if k.factions[r] != faction or not (k.detected[r] == 1 or k.scan_conf[r] > 0.0):
			continue
		if rows.size() >= MAX_CARDS:
			break
		var contact: int = k.ship_ids[r]
		var card: Dictionary = {
			"contact": contact,
			"detect": ScienceKnowledge.detection_confidence(world, faction, contact),
			"scan": k.scan_conf[r],
			"class_id": 0,
			"intent": 0,
			"weak_mask": 0,
			"resist": [],
			"hack": ScienceKnowledge.revealed(world, faction, contact, ScienceKnowledge.HACK),
		}
		if ScienceKnowledge.revealed(world, faction, contact, ScienceKnowledge.CLASS):
			card["class_id"] = code(world.defs[contact].id)
		if ScienceKnowledge.revealed(world, faction, contact, ScienceKnowledge.INTENT):
			card["intent"] = 1 + world.ai.mode[contact] if world.ai.enabled[contact] == 1 else 1
		card.merge(revealed_traits(world, faction, contact), true)
		rows.append(card)
	return rows


## The contact's weak-point subsystem mask and resistances (`weak_mask`, `resist`: rows of
## {type, factor}) as far as the faction's scans revealed them; 0 and [] before.
static func revealed_traits(world: SimWorld, faction: int, contact: int) -> Dictionary:
	var mask: int = 0
	for i: int in ScienceKnowledge.weak_points(world, faction, contact):
		mask |= 1 << i
	var resist: Array = []
	var factors: Dictionary[StringName, float] = ScienceKnowledge.resistances(
		world, faction, contact
	)
	for type: StringName in factors:
		resist.append({"type": code(type), "factor": factors[type]})
	return {"weak_mask": mask, "resist": resist}


## The faction's open hack windows (P7: the hack-window timer Weapons sees).
static func hacks(world: SimWorld, faction: int) -> Array:
	var h: HackTable = world.hacks
	var rows: Array = []
	for r: int in h.size():
		if h.factions[r] == faction and rows.size() < MAX_CARDS:
			(
				rows
				. append(
					{
						"target": h.ship_ids[r],
						"sub": h.subsystem[r],
						"left": maxf(0.0, (h.until_tick[r] - world.tick) * SimWorld.DT),
						"by": h.by[r],
					}
				)
			)
	return rows
