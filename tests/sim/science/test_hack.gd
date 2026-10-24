extends GdUnitTestSuite
## E01: the node-route hack (FT-SCI-006, FT-SCI-007, FT-SCI-011), its timed effect
## (FT-SCI-008, FT-PAIR-023) and probe coverage (P13).

const ME: int = 0
const FOE: int = 1


## A world where the corvette has scanned the raider well enough to hack it.
func _scanned() -> SimWorld:
	var w: SimWorld = ScienceFixture.world()
	ScienceFixture.scan_exactly(w)
	return w


func _start(w: SimWorld, subsystem: StringName = &"weapons") -> void:
	var events: Array[SimEvent] = ScienceFixture.do(w, ScienceFixture.hack_cmd(subsystem))
	assert_int(SimFixture.of_kind(events, &"hack_started").size()).is_equal(1)


## Walks the shortest route; returns the events of the last move.
func _walk(w: SimWorld) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	for node: int in ScienceFixture.route(w):
		events = ScienceFixture.do(w, ScienceFixture.move_cmd(node))
	return events


# FT: FT-SCI-006, FT-SCI-011
# A hack needs scan access first; the route must follow edges; the goal ends the hack.
func test_hack_needs_access_and_follows_edges() -> void:
	var w: SimWorld = ScienceFixture.world()
	var events: Array[SimEvent] = ScienceFixture.do(w, ScienceFixture.hack_cmd(&"weapons"))
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("no_access")
	ScienceFixture.scan_exactly(w)
	events = ScienceFixture.do(w, ScienceFixture.hack_cmd(&"nonsense"))
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("bad_subsystem")
	_start(w)
	var def: ScienceDef = w.science_def
	var t: ScienceTable = w.science
	# A node that is not a neighbour of the entry is refused.
	var far: int = def.hack_cols * def.hack_rows - 1
	events = ScienceFixture.do(w, ScienceFixture.move_cmd(far - 1))
	assert_str(SimFixture.of_kind(events, &"science_refused")[0].tag).is_equal("no_edge")
	assert_int(t.node[ME]).is_equal(HackPuzzle.entry(def))
	events = _walk(w)
	assert_int(SimFixture.of_kind(events, &"hack_done").size()).is_equal(1)
	assert_int(t.kind[ME]).is_equal(ScienceTable.Session.NONE)


# FT: FT-SCI-006
# Every generated hack has a route from the entry to the goal, for any seed.
func test_every_hack_has_a_route() -> void:
	var def: ScienceDef = ScienceFixture.science()
	for s: int in 40:
		for sub: int in def.hack_rows:
			var goal: int = HackPuzzle.goal(def, sub)
			var edges: PackedByteArray = HackPuzzle.edges(def, s * 977 + 3, goal)
			var seen: Dictionary[int, bool] = {HackPuzzle.entry(def): true}
			var queue: Array[int] = [HackPuzzle.entry(def)]
			while not queue.is_empty():
				var n: int = queue.pop_front()
				for dir: int in [HackPuzzle.RIGHT, HackPuzzle.DOWN, HackPuzzle.LEFT, HackPuzzle.UP]:
					var m: int = HackPuzzle.neighbour(def, n, dir)
					if (edges[n] & dir) != 0 and m >= 0 and not seen.has(m):
						seen[m] = true
						queue.append(m)
			assert_bool(seen.has(goal)).is_true()


# FT: FT-SCI-006
# The trace bar fills with time and with each move; a full bar fails the hack.
func test_trace_bar_fails_a_slow_hack() -> void:
	var w: SimWorld = _scanned()
	_start(w)
	var def: ScienceDef = w.science_def
	var ticks: int = int(
		1.0 / (def.trace_rate * (1.0 + def.trace_noise_gain * w.science.noise[ME])) * 60.0
	)
	var events: Array[SimEvent] = SimFixture.run(w, ticks + 5)
	assert_int(SimFixture.of_kind(events, &"hack_traced").size()).is_equal(1)
	assert_int(w.science.kind[ME]).is_equal(ScienceTable.Session.NONE)
	assert_int(w.hacks.size()).is_equal(0)


# FT: FT-SCI-007
# Hidden nodes start hidden; a better scan reveals more of them, probe coverage more
# still, and stepping onto one reveals it.
func test_hidden_nodes_are_revealed_by_scans_and_probes() -> void:
	var def: ScienceDef = ScienceFixture.science()
	var goal: int = HackPuzzle.goal(def, 0)
	var hidden: int = HackPuzzle.hidden_order(def, 5, goal).size()
	assert_int(hidden).is_greater(0)
	var all: int = def.hack_cols * def.hack_rows
	var lone: int = _count(HackPuzzle.known_at_start(def, 5, goal, 0.0, false), all)
	var scanned: int = _count(HackPuzzle.known_at_start(def, 5, goal, 0.5, false), all)
	var probed: int = _count(HackPuzzle.known_at_start(def, 5, goal, 0.5, true), all)
	var full: int = _count(HackPuzzle.known_at_start(def, 5, goal, 1.0, false), all)
	assert_int(lone).is_equal(all - hidden)
	assert_int(scanned).is_greater(lone)
	assert_int(probed).is_greater_equal(scanned)
	assert_int(full).is_equal(all)
	# Stepping onto a hidden node reveals it.
	var w: SimWorld = _scanned()
	w.science_def = def
	w.knowledge.scan_conf[w.knowledge.row_for(1, FOE)] = def.reveal_hack
	_start(w)
	var route: Array[int] = ScienceFixture.route(w)
	for node: int in route:
		ScienceFixture.do(w, ScienceFixture.move_cmd(node))
		if w.science.kind[ME] != ScienceTable.Session.HACK:
			break
		assert_int(w.science.known[ME] & (1 << node)).is_not_equal(0)


# FT: FT-SCI-008, FT-PAIR-023
# A successful hack multiplies the subsystem's effectiveness for the data-defined window,
# which is at least 8 s, then ends; other ships and subsystems are untouched.
func test_hack_window_applies_and_ends() -> void:
	var w: SimWorld = _scanned()
	_start(w, &"weapons")
	var events: Array[SimEvent] = _walk(w)
	var done: SimEvent = SimFixture.of_kind(events, &"hack_done")[0]
	var window_s: float = done.value
	assert_float(window_s).is_greater_equal(8.0)
	assert_float(DamageSystem.effectiveness(w, FOE, &"weapons")).is_equal(0.0)
	assert_float(DamageSystem.effectiveness(w, FOE, &"engines")).is_equal(1.0)
	assert_float(DamageSystem.effectiveness(w, ME, &"weapons")).is_equal(1.0)
	(
		assert_float(ScienceSystem.hack_left(w, FOE, SimFixture.sub_index(w, FOE, &"weapons"), 1))
		. is_greater(window_s - 0.1)
	)
	var ticks: int = ceili(window_s * 60.0)
	SimFixture.run(w, ticks - 2)
	assert_float(DamageSystem.effectiveness(w, FOE, &"weapons")).is_equal(0.0)
	events = SimFixture.run(w, 4)
	assert_int(SimFixture.of_kind(events, &"hack_window_end").size()).is_equal(1)
	assert_float(DamageSystem.effectiveness(w, FOE, &"weapons")).is_equal(1.0)
	assert_int(w.hacks.size()).is_equal(0)


# FT: FT-PAIR-023
# Every hack effect in the data keeps its window at or above the 8 s minimum.
func test_every_effect_window_is_at_least_8_s() -> void:
	var def: ScienceDef = ScienceFixture.science()
	assert_array(def.validate()).is_empty()
	assert_int(def.effects.size()).is_equal(6)
	for e: HackEffectDef in def.effects:
		assert_float(e.window_s).is_greater_equal(8.0)
	var bad: HackEffectDef = def.effects[0].duplicate()
	bad.window_s = 7.9
	assert_array(bad.validate()).is_not_empty()


# FT: FT-SCI-008
# A hack on the engines slows the target's thrust (the power system reads the same
# effectiveness), and a re-hack renews the window instead of stacking.
func test_hack_reaches_engines_and_renews() -> void:
	var w: SimWorld = _scanned()
	var before: float = w.kin.thrust_scale[FOE]
	_start(w, &"engines")
	_walk(w)
	SimFixture.run(w, 2)
	assert_float(w.kin.thrust_scale[FOE]).is_less(before)
	assert_int(w.hacks.size()).is_equal(1)
	_start(w, &"engines")
	_walk(w)
	assert_int(w.hacks.size()).is_equal(1)


# FT: FT-SCI-006, FT-PAIR-003
# P13: the trace bar rises more slowly in probe coverage.
func test_probe_coverage_slows_the_trace() -> void:
	var plain: SimWorld = _scanned()
	_start(plain)
	SimFixture.run(plain, 120)
	var covered: SimWorld = _scanned()
	covered.probe_coverage = func(_ship: int, _contact: int) -> bool: return true
	_start(covered)
	SimFixture.run(covered, 120)
	assert_float(covered.science.trace[ME]).is_less(plain.science.trace[ME])
	assert_float(covered.science.noise[ME]).is_less(plain.science.noise[ME])


func _count(mask: int, total: int) -> int:
	var n: int = 0
	for i: int in total:
		n += (mask >> i) & 1
	return n
