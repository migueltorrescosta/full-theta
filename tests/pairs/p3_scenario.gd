class_name P3Scenario
extends RefCounted
## P3 Helm + Science pair scenario (spec §7.4, FT-PAIR-015, D58): the M1 corvette lies
## 6 km astern of a hostile raider that faces it, so the scan sees the raider bow-on,
## the noisiest aspect. Science scans it.
## - Solo: Science scans from where the ship is (ScienceHand).
## - Co-op: Science places the scan-position mark (one command, D58); Helm reads the
##   mark, selects it, holds Face and throttles up until the ship is inside the mark's
##   radius; Science opens its scan once the ship is there.
## Metrics: noise of the scan (0..1, the density of the cloud: lower is cleaner), scan
## seconds (from the scan opening to its result, the Science player's time on the
## puzzle), confidence of the result, and total seconds from the start (flight included,
## reported, not gated: the flight is Helm's course, which the ship flies for other
## reasons, so the pair is judged on the scan it buys).

const SEED: int = 43
const PLAYER: int = 0
const RAIDER: int = 1
const RAIDER_AT: Vector3 = Vector3(0.0, 0.0, -6000.0)
## Helm throttles up once the bow is within this angle of the mark (rad, 5 deg).
const ON_POINT: float = PI / 36.0
const TICK_LIMIT: int = 120 * SimWorld.HZ
## The seed of the scripted Science player's angle errors.
const PLAYER_SEED: int = 3


static func harness() -> PairHarness:
	return PairHarness.new(build, func(_w: SimWorld) -> void: pass, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p3")
	w.science_def = ScienceFixture.science()
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(TestDefs.corvette(), 1)
	var facing_player: Quaternion = Quaternion(Vector3.UP, PI)
	w.spawn_ship(TestDefs.raider(), 2, RAIDER_AT, facing_player)
	return w


static func done(w: SimWorld) -> bool:
	return ScienceKnowledge.confidence(w, 1, RAIDER) > 0.0


static func measure(w: SimWorld) -> Dictionary:
	var starts: Array[SimEvent] = SimFixture.of_kind(w.events, &"scan_started")
	var ends: Array[SimEvent] = SimFixture.of_kind(w.events, &"scan_done")
	if starts.is_empty() or ends.is_empty():
		return {}
	var started: SimEvent = starts[0]
	var finished: SimEvent = ends[0]
	return {
		"noise": started.value,
		"scan_s": (finished.tick - started.tick) * SimWorld.DT,
		"confidence": finished.value,
		"total_s": w.tick * SimWorld.DT,
	}


static func solo_crew() -> Callable:
	var hand: ScienceHand = ScienceHand.new(PLAYER, RAIDER, PLAYER_SEED)
	return func(w: SimWorld) -> void: hand.act(w)


static func coop_crew() -> Callable:
	var hand: ScienceHand = ScienceHand.new(PLAYER, RAIDER, PLAYER_SEED)
	hand.start_gate = at_mark
	return func(w: SimWorld) -> void:
		science_mark(w)
		helm(w)
		hand.act(w)


## Science (co-op): places the mark once the raider is a contact.
static func science_mark(w: SimWorld) -> void:
	if w.tick == 1:
		var c: ScienceMarkCommand = ScienceMarkCommand.new()
		c.ship_id = PLAYER
		c.contact = RAIDER
		w.submit(c)


## Helm (co-op): flies to the mark once there is one, and lets go of the throttle in it.
static func helm(w: SimWorld) -> void:
	var t: ScienceTable = w.science
	if t.mark_contact[PLAYER] < 0:
		return
	var inside: bool = at_mark(w)
	if w.tick == 2:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.ship_id = PLAYER
		select.point = true
		select.x = t.mark_x[PLAYER]
		select.y = t.mark_y[PLAYER]
		select.z = t.mark_z[PLAYER]
		w.submit(select)
		w.submit(PairHarness.helm_input(0.0))
	var to_mark: Vector3 = w.kin.relative_to_point(
		PLAYER, t.mark_x[PLAYER], t.mark_y[PLAYER], t.mark_z[PLAYER]
	)
	var on_point: bool = w.kin.forward(PLAYER).angle_to(to_mark) < ON_POINT
	var throttle: float = 1.0 if (on_point and not inside) else 0.0
	if w.tick > 2 and w.helm.input_translation[PLAYER].z != throttle:
		w.submit(PairHarness.helm_input(throttle))


static func at_mark(w: SimWorld) -> bool:
	return ScienceSystem.at_scan_mark(w, PLAYER, RAIDER)
