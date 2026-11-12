class_name ScienceSystem
extends RefCounted
## Science rules (E01): the sensor mode and active ping, scan noise, the silhouette-
## alignment scan, the node-route hack and its timed effect, the scan-position mark and
## the own-ship scan. The Science commands call the functions below; step() runs the
## clocks (ping, session timeouts, trace bar, hack windows). Runs first in the tick, so
## a hack window opened by this tick's commands already applies this tick.
##
## Events, keyed to the scanning ship (other_id the contact):
## - &"science_refused": a command was refused; tag the reason (REASON_*).
## - &"scan_started": value noise, vector (open axes mask, 0, 0).
## - &"scan_done": value confidence, vector (match quality, noise, 0), tag &"locked" when
##   the match reached the lock threshold (FT-SCI-016).
## - &"scan_failed", &"hack_failed": tag &"timeout", &"lost" (contact gone) or
##   &"cancelled".
## - &"hack_started": value noise; &"hack_traced": the trace bar filled.
## - &"hack_done": value window (s), tag the subsystem id.
## - &"scan_mark": the scan-position mark was placed, vector its offset from the contact.
## - &"self_scan_done".
## scan_started and hack_started stay on the server (NetCoop's probe-scan stat); a ping,
## an own-ship scan's start and a hack window's end emit nothing (R02-7: no reader).

const REASON_NO_SCIENCE: StringName = &"no_science"
const REASON_BUSY: StringName = &"busy"
const REASON_BAD_CONTACT: StringName = &"bad_contact"
const REASON_NOT_DETECTED: StringName = &"not_detected"
const REASON_OUT_OF_RANGE: StringName = &"out_of_range"
const REASON_NO_ACCESS: StringName = &"no_access"
const REASON_NO_SESSION: StringName = &"no_session"
const REASON_BAD_SUBSYSTEM: StringName = &"bad_subsystem"
const REASON_NO_EDGE: StringName = &"no_edge"
const REASON_COOLING: StringName = &"cooling"


static func step(world: SimWorld) -> void:
	var def: ScienceDef = world.science_def
	if def != null:
		var t: ScienceTable = world.science
		for ship: int in world.ship_count():
			if t.ping_left[ship] > 0.0:
				t.ping_left[ship] = maxf(0.0, t.ping_left[ship] - SimWorld.DT)
			if t.ping_cool[ship] > 0.0:
				t.ping_cool[ship] = maxf(0.0, t.ping_cool[ship] - SimWorld.DT)
			if t.kind[ship] != ScienceTable.Session.NONE:
				_step_session(world, def, t, ship)
			var sel: int = t.selected[ship]
			if sel >= 0 and world.kin.is_alive(ship):
				t.preview[ship] = noise_parts(world, ship, sel)
			elif not t.preview[ship].is_empty():
				t.preview[ship] = {}
	_apply_hacks(world)


## The noise a scan of the contact would have now, with its terms: {noise, range,
## aspect, health, active, ping, probe, mark}. range, aspect and health are the 0..1
## terms before their weights; the rest flags and the final noise.
static func noise_parts(world: SimWorld, ship: int, contact: int) -> Dictionary:
	var def: ScienceDef = world.science_def
	var t: ScienceTable = world.science
	var kin: Kinematics = world.kin
	var dist: float = INF
	var aspect: float = 0.0
	if ship != contact:
		var los: Vector3 = kin.relative(ship, contact)
		dist = los.length()
		if dist > 0.0:
			aspect = absf(kin.forward(contact).dot(los / dist))
	var eff: float = DamageSystem.effectiveness(world, ship, KnowledgeSystem.SENSORS)
	var pips: int = 0
	var nominal: int = 0
	var r: int = world.damage.find_subsystem(ship, KnowledgeSystem.SENSORS)
	if r >= 0:
		pips = world.damage.pips[r]
		nominal = DamageSystem.sub_def(world, ship, r).nominal_pips
	var is_active: bool = t.active[ship] == 1
	var pinging: bool = t.ping_left[ship] > 0.0
	var probe: bool = probe_covered(world, ship, contact)
	var at_mark: bool = at_scan_point(world, ship)
	var total: float = ScienceNoise.compute(
		def, dist, aspect, eff, pips, nominal, is_active, pinging, probe, at_mark
	)
	return {
		"noise": total,
		"range": clampf(dist / def.range_ref, 0.0, 1.0),
		"aspect": aspect,
		"health": 1.0 - eff,
		"active": is_active,
		"ping": pinging,
		"probe": probe,
		"mark": at_mark,
	}


## The noise of a scan of the contact now (see noise_parts), 0..1.
static func contact_noise(world: SimWorld, ship: int, contact: int) -> float:
	return noise_parts(world, ship, contact)["noise"]


## Whether the contact is inside a probe's coverage for the ship's faction (FT-SCI-005,
## P13): Relay's deployed probes (ProbeSystem.covers_contact).
static func probe_covered(world: SimWorld, ship: int, contact: int) -> bool:
	return ProbeSystem.covers_contact(world, ship, contact)


## Whether the ship is within mark_radius of its scan point (P3), whatever it scans: the
## point is the crew's scan position, which Relay can change (D378).
static func at_scan_point(world: SimWorld, ship: int) -> bool:
	var t: ScienceTable = world.science
	if not t.has_scan_point(ship):
		return false
	var off: Vector3 = world.kin.relative_to_column(ship, t.scan_x, t.scan_y, t.scan_z, ship)
	return off.length() <= world.science_def.mark_radius


## The server moved or cleared the ship's crew-state scan position (D378): the sim's scan
## point follows. A non-finite point is refused; others wrap into the cube.
static func set_scan_point(world: SimWorld, ship: int, at: PackedFloat64Array) -> bool:
	if at.size() == 3:
		at = world.kin.wrap_point(at)
		if at.is_empty():
			return false
	world.science.set_scan_point(ship, at)
	return true


## Sensors to active (true) or passive (false) mode (FT-SCI-003).
static func set_mode(world: SimWorld, ship: int, is_active: bool) -> bool:
	world.science.active[ship] = 1 if is_active else 0
	return true


## Starts an active ping: noise drops for ping_duration_s (P key).
static func ping(world: SimWorld, ship: int) -> bool:
	var def: ScienceDef = world.science_def
	if def == null:
		return _refuse(world, ship, -1, REASON_NO_SCIENCE)
	var t: ScienceTable = world.science
	if t.ping_cool[ship] > 0.0:
		return _refuse(world, ship, -1, REASON_COOLING)
	t.ping_left[ship] = def.ping_duration_s
	t.ping_cool[ship] = def.ping_cooldown_s
	return true


## Selects the contact for the noise preview (-1 clears).
static func select(world: SimWorld, ship: int, contact: int) -> bool:
	if contact != -1 and not world.has_ship(contact):
		return _refuse(world, ship, contact, REASON_BAD_CONTACT)
	world.science.selected[ship] = contact
	return true


## Places the scan-position mark for the contact (FT-SCI-010, P3): broadside to the
## contact, mark_distance away, on the side the ship is on: the ship's scan point, which
## the server turns into the crew-state scan position (D378). Replaces the old one.
static func place_mark(world: SimWorld, ship: int, contact: int) -> bool:
	var reason: StringName = _check_target(world, ship, contact, false)
	if reason != &"" and reason != REASON_OUT_OF_RANGE:
		return _refuse(world, ship, contact, reason)
	var kin: Kinematics = world.kin
	var fwd: Vector3 = kin.forward(contact)
	var away: Vector3 = kin.relative(contact, ship)
	var side: Vector3 = away - fwd * away.dot(fwd)
	if side.length() < 1.0:
		side = kin.rot[contact] * Vector3.RIGHT
	var offset: Vector3 = side.normalized() * world.science_def.mark_distance
	var t: ScienceTable = world.science
	var at: PackedFloat64Array = kin.point_at(contact, offset)
	t.set_scan_point(ship, at)
	world.emit(&"scan_mark", ship, contact, 0.0, offset)
	return true


## Opens a silhouette-alignment scan of the contact (FT-SCI-004, FT-SCI-011).
static func start_scan(world: SimWorld, ship: int, contact: int) -> bool:
	var reason: StringName = _check_target(world, ship, contact, true)
	if reason != &"":
		return _refuse(world, ship, contact, reason)
	var def: ScienceDef = world.science_def
	var faction: int = world.faction_of(ship)
	var noise: float = contact_noise(world, ship, contact)
	var pre: bool = ScienceKnowledge.class_fully_scanned(world, faction, contact)
	var mask: int = 0
	var puzzle_seed: int = _draw_seed(world)
	mask = ScanPuzzle.axes_mask(puzzle_seed, ScienceNoise.axes_for(def, noise, pre))
	var t: ScienceTable = world.science
	t.clear_session(ship)
	t.kind[ship] = ScienceTable.Session.SCAN
	t.target[ship] = contact
	t.puzzle_seed[ship] = puzzle_seed
	t.noise[ship] = noise
	t.start_tick[ship] = world.tick
	t.axes[ship] = mask
	t.probe[ship] = 1 if probe_covered(world, ship, contact) else 0
	world.emit(&"scan_started", ship, contact, noise, Vector3(mask, 0.0, 0.0))
	return true


## Checks the submitted angles (rad, about x, y, z; closed axes ignored) against the
## hidden pose and records the scan (FT-SCI-016).
static func submit_scan(world: SimWorld, ship: int, angles: Vector3) -> bool:
	var t: ScienceTable = world.science
	if world.science_def == null or t.kind[ship] != ScienceTable.Session.SCAN:
		return _refuse(world, ship, -1, REASON_NO_SESSION)
	var def: ScienceDef = world.science_def
	var contact: int = t.target[ship]
	var q: float = ScanPuzzle.quality(def, t.puzzle_seed[ship], t.axes[ship], angles)
	var noise: float = t.noise[ship]
	var conf: float = ScanPuzzle.confidence(def, q, noise)
	ScienceKnowledge.record(world, world.faction_of(ship), contact, conf)
	var tag: StringName = &"locked" if q >= def.lock_threshold else &""
	world.emit(&"scan_done", ship, contact, conf, Vector3(q, noise, 0.0), tag)
	t.clear_session(ship)
	return true


## Opens a node-route hack on a subsystem of the contact (FT-SCI-006). The contact's
## scan confidence must reach the hack-access threshold (D59); scans and probe
## coverage reveal hidden nodes (FT-SCI-007).
static func start_hack(world: SimWorld, ship: int, contact: int, subsystem_id: StringName) -> bool:
	var reason: StringName = _check_target(world, ship, contact, true)
	if reason != &"":
		return _refuse(world, ship, contact, reason)
	var def: ScienceDef = world.science_def
	var faction: int = world.faction_of(ship)
	if not ScienceKnowledge.revealed(world, faction, contact, ScienceKnowledge.HACK):
		return _refuse(world, ship, contact, REASON_NO_ACCESS)
	var row: int = world.damage.find_subsystem(contact, subsystem_id)
	var index: int = world.damage.index_of_row(contact, row)
	if row < 0:
		return _refuse(world, ship, contact, REASON_BAD_SUBSYSTEM)
	var probe: bool = probe_covered(world, ship, contact)
	var puzzle_seed: int = _draw_seed(world)
	var goal: int = HackPuzzle.goal(def, index)
	var t: ScienceTable = world.science
	t.clear_session(ship)
	t.kind[ship] = ScienceTable.Session.HACK
	t.target[ship] = contact
	t.puzzle_seed[ship] = puzzle_seed
	t.noise[ship] = contact_noise(world, ship, contact)
	t.start_tick[ship] = world.tick
	t.subsystem[ship] = index
	t.node[ship] = HackPuzzle.entry(def)
	t.known[ship] = (
		HackPuzzle.known_at_start(
			def, puzzle_seed, goal, ScienceKnowledge.confidence(world, faction, contact), probe
		)
		| (1 << t.node[ship])
	)
	t.probe[ship] = 1 if probe else 0
	world.emit(&"hack_started", ship, contact, t.noise[ship], Vector3.ZERO, subsystem_id)
	return true


## Moves the route to an adjacent node (FT-SCI-006, FT-SCI-011): the edge must exist (a move
## along a missing edge is refused but still raises the trace by trace_per_move, so mapping
## the maze by trying edges isn't free); the node becomes known, the trace bar rises by
## trace_per_move, and reaching the goal opens the hack window.
static func hack_move(world: SimWorld, ship: int, node: int) -> bool:
	var t: ScienceTable = world.science
	var def: ScienceDef = world.science_def
	if def == null or t.kind[ship] != ScienceTable.Session.HACK:
		return _refuse(world, ship, -1, REASON_NO_SESSION)
	var contact: int = t.target[ship]
	var goal: int = HackPuzzle.goal(def, t.subsystem[ship])
	var edges: PackedByteArray = HackPuzzle.edges(def, t.puzzle_seed[ship], goal)
	if node < 0 or node >= edges.size() or not HackPuzzle.connected(edges, def, t.node[ship], node):
		t.trace[ship] += def.trace_per_move
		var refused: bool = _refuse(world, ship, contact, REASON_NO_EDGE)  # false
		if t.trace[ship] >= 1.0:
			_fail(world, t, ship, &"hack_traced", &"")
		return refused
	t.node[ship] = node
	t.known[ship] |= 1 << node
	t.trace[ship] += def.trace_per_move
	if node == goal:
		_finish_hack(world, def, t, ship)
	elif t.trace[ship] >= 1.0:
		_fail(world, t, ship, &"hack_traced", &"")
	return true


## Closes the ship's open session without a result.
static func cancel(world: SimWorld, ship: int) -> bool:
	var t: ScienceTable = world.science
	var k: int = t.kind[ship]
	if k == ScienceTable.Session.NONE:
		return _refuse(world, ship, -1, REASON_NO_SESSION)
	var kind: StringName = &"hack_failed" if k == ScienceTable.Session.HACK else &"scan_failed"
	_fail(world, t, ship, kind, &"cancelled")
	return true


## Starts the own-ship scan (FT-SCI-009, P10): it ends after self_scan_s and then names
## the ship's hidden fault causes.
static func start_self_scan(world: SimWorld, ship: int) -> bool:
	var def: ScienceDef = world.science_def
	if def == null:
		return _refuse(world, ship, -1, REASON_NO_SCIENCE)
	var t: ScienceTable = world.science
	if t.kind[ship] != ScienceTable.Session.NONE:
		return _refuse(world, ship, -1, REASON_BUSY)
	t.clear_session(ship)
	t.kind[ship] = ScienceTable.Session.SELF
	t.target[ship] = ship
	t.start_tick[ship] = world.tick
	return true


static func _step_session(world: SimWorld, def: ScienceDef, t: ScienceTable, ship: int) -> void:
	var k: int = t.kind[ship]
	var elapsed: int = world.tick - t.start_tick[ship]
	if not world.kin.is_alive(ship):
		t.clear_session(ship)
		return
	if k == ScienceTable.Session.SELF:
		if elapsed >= SimRate.ticks(def.self_scan_s):
			_finish_self_scan(world, t, ship)
		return
	var fail_kind: StringName = &"hack_failed" if k == ScienceTable.Session.HACK else &"scan_failed"
	var contact: int = t.target[ship]
	var faction: int = world.faction_of(ship)
	var row: int = world.knowledge.row_for(faction, contact)
	# A probe's bubble makes a contact detected too (KnowledgeSystem), so this covers it.
	var seen: bool = row >= 0 and world.knowledge.detected[row] == 1
	if not world.kin.is_alive(contact) or not seen:
		_fail(world, t, ship, fail_kind, &"lost")
	elif k == ScienceTable.Session.SCAN:
		if elapsed >= SimRate.ticks(def.scan_cap_s):
			_fail(world, t, ship, fail_kind, &"timeout")
	else:
		var speed: float = def.trace_rate * (1.0 + def.trace_noise_gain * t.noise[ship])
		if t.probe[ship] == 1:
			speed *= def.probe_trace_factor
		t.trace[ship] += speed * SimWorld.DT
		if t.trace[ship] >= 1.0:
			_fail(world, t, ship, &"hack_traced", &"")


static func _finish_hack(world: SimWorld, def: ScienceDef, t: ScienceTable, ship: int) -> void:
	var contact: int = t.target[ship]
	var index: int = t.subsystem[ship]
	var sub: SubsystemDef = world.defs[contact].subsystems[index]
	var effect: HackEffectDef = def.effect_for(sub.kind)
	var window: float = 0.0
	if effect != null:
		window = effect.window_s
		var until: int = world.tick + SimRate.ticks(window)
		world.hacks.open(contact, world.faction_of(ship), index, effect.factor, until, ship)
	world.emit(&"hack_done", ship, contact, window, Vector3.ZERO, sub.id)
	t.clear_session(ship)


static func _finish_self_scan(world: SimWorld, t: ScienceTable, ship: int) -> void:
	t.self_scanned[ship] = world.tick
	t.clear_session(ship)
	world.emit(&"self_scan_done", ship, ship)
	# P10 (FT-SIM-025): the scan names the cause of every unknown fault. Easy's diagnosed-cause
	# shortcut (FT-ENG-006) is the net layer's (NetShares.prefill_cause).
	for sub: SubsystemDef in world.defs[ship].subsystems:
		DamageSystem.reveal_fault_cause(world, ship, sub.id)


static func _fail(
	world: SimWorld, t: ScienceTable, ship: int, kind: StringName, reason: StringName
) -> void:
	world.emit(kind, ship, t.target[ship], t.trace[ship], Vector3.ZERO, reason)
	t.clear_session(ship)


## Removes closed hack windows and writes the open ones' product into
## DamageTable.hack_scale (a derived cache, not state).
static func _apply_hacks(world: SimWorld) -> void:
	var hacks: HackTable = world.hacks
	var d: DamageTable = world.damage
	if hacks.size() == 0 and not d.hack_dirty:
		return
	var r: int = hacks.size() - 1
	while r >= 0:
		if world.tick >= hacks.until_tick[r]:
			hacks.remove_rows(PackedInt32Array([r]))
		r -= 1
	d.hack_scale.fill(1.0)
	for i: int in hacks.size():
		var row: int = d.subsystem_row(hacks.subject_ship[i], hacks.subsystem[i])
		d.hack_scale[row] *= hacks.factor[i]
	d.hack_dirty = hacks.size() > 0


## Why the ship can't open a scan or hack on the contact, or &"". `need_free` also
## requires no open session; `place_mark` reuses the checks without it.
static func _check_target(world: SimWorld, ship: int, contact: int, need_free: bool) -> StringName:
	var def: ScienceDef = world.science_def
	if def == null:
		return REASON_NO_SCIENCE
	var t: ScienceTable = world.science
	if need_free and t.kind[ship] != ScienceTable.Session.NONE:
		return REASON_BUSY
	var kin: Kinematics = world.kin
	if (
		not world.has_ship(contact)
		or contact == ship
		or world.faction_of(contact) == world.faction_of(ship)
		or not kin.is_alive(contact)
	):
		return REASON_BAD_CONTACT
	var probe: bool = probe_covered(world, ship, contact)
	var row: int = world.knowledge.row_for(world.faction_of(ship), contact)
	if row < 0 or world.knowledge.detected[row] == 0:
		return REASON_NOT_DETECTED
	var reach: float = KnowledgeSystem.sensor_reach(world, ship) * def.scan_range_factor
	if not probe and kin.relative(ship, contact).length() > reach:
		return REASON_OUT_OF_RANGE
	return &""


static func _draw_seed(world: SimWorld) -> int:
	return world.rng.stream(&"science").randi()


static func _refuse(world: SimWorld, ship: int, contact: int, reason: StringName) -> bool:
	world.emit(&"science_refused", ship, contact, 0.0, Vector3.ZERO, reason)
	return false
