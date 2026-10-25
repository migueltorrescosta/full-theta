class_name ScienceShotBlocks
extends RefCounted
## SCIENCE blocks for the L5 shots (tests/visual/station_shot.gd, `science`): contact
## cards (H2 well scanned, U3 barely seen), a scan puzzle with three open axes and a hack
## route on a 5 x 3 grid. The same shapes as tests/stations/test_science_panel.gd builds.

const H2: int = StationFixture.H2
const U3: int = StationFixture.U3


## The block for `kind`: "cards", "scan" or "hack".
static func block(kind: String) -> Dictionary:
	var b: Dictionary = ScienceView._empty()
	b["cards"] = [
		{
			"contact": H2,
			"detect": 0.9,
			"scan": 0.9,
			"class_id": ScienceView.code(&"m1_raider"),
			"intent": 3,
			"weak_mask": 1,
			"resist": [{"type": ScienceView.code(&"kinetic"), "factor": 0.5}],
			"hack": true,
		},
		{
			"contact": U3,
			"detect": 0.2,
			"scan": 0.0,
			"class_id": 0,
			"intent": 0,
			"weak_mask": 0,
			"resist": [],
			"hack": false,
		},
	]
	if kind == "scan":
		b.merge(_scan(Vector3(0.5, -0.7, 0.3), 7), true)
	elif kind == "hack":
		b.merge(_hack(7, 0x7FF), true)
	return b


static func _scan(truth: Vector3, axes: int) -> Dictionary:
	var wire: Array = []
	var cloud: Array = []
	var verts: Array[Vector3] = [
		Vector3(1, 0, 0),
		Vector3(0, 0.8, 0.2),
		Vector3(-0.5, -0.4, 0.6),
		Vector3(0.1, 0.3, -0.9),
		Vector3(-0.7, 0.5, -0.2),
		Vector3(0.4, -0.7, -0.3),
	]
	var pose: Basis = Basis.from_euler(truth)
	for v: Vector3 in verts:
		wire.append({"p": v})
		cloud.append({"p": pose * v})
	return {
		"session": 1,
		"session_target": H2,
		"session_start": 10,
		"session_noise": 0.33,
		"axes": axes,
		"wire": wire,
		"cloud": cloud,
	}


## A 5 x 3 grid with a corridor along the middle row; `known` is the revealed-node mask.
static func _hack(node: int, known: int) -> Dictionary:
	var edges: Array = []
	for n: int in 15:
		var mask: int = 0
		if n / 5 == 1:
			mask = (HackGame.RIGHT if n % 5 < 4 else 0) | (HackGame.LEFT if n % 5 > 0 else 0)
			if n == 7:
				mask |= HackGame.UP
		elif n == 2:
			mask = HackGame.DOWN
		edges.append({"mask": mask if (known >> n) & 1 == 1 else 0})
	return {
		"session": 2,
		"session_target": H2,
		"session_start": 10,
		"session_noise": 0.3,
		"hack_cols": 5,
		"hack_rows": 3,
		"hack_node": node,
		"hack_goal": 9,
		"hack_sub": 2,
		"trace": 0.25,
		"known": known,
		"edges": edges,
	}
