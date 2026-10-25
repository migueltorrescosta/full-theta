extends GdUnitTestSuite
## M2 strand C: faults of unknown cause and their diagnosis (FT-SIM-025, FT-ENG-006,
## P10) and pre-hardening a subsystem (FT-ENG-008, P11). One raider, as faction 2, with
## its engines listing three possible causes. Engines: 2e7 J, repaired at 2e5 J/s per
## crew (so a 2e6 J fault takes 10 s at full rate); brute force is a quarter of that.

const CAUSES: Array[StringName] = [&"coolant_leak", &"short", &"software"]
const FAULT_J: float = 2e6
const TICKS_FULL: int = 600


func _def(fields: Dictionary = {}) -> ShipDef:
	var def: ShipDef = TestDefs.raider().duplicate()
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = s.duplicate()
		if copy.id == &"engines":
			copy.fault_causes = CAUSES
			for k: String in fields:
				copy.set(k, fields[k])
		else:
			copy.fault_causes = []
		subs.append(copy)
	def.subsystems = subs
	return def


func _world(fields: Dictionary = {}) -> SimWorld:
	var world: SimWorld = SimWorld.new(9)
	world.spawn_ship(_def(fields), 2, 0)
	return world


func _health(world: SimWorld, id: StringName = &"engines") -> float:
	return world.damage.health[world.damage.find_subsystem(0, id)]


func _dispatch(world: SimWorld) -> void:
	var c: DispatchRepairCommand = DispatchRepairCommand.new()
	c.ship_id = 0
	c.crew = 0
	c.subsystem_id = &"engines"
	world.submit(c)


## Ticks from dispatching a crew until the fault clears (-1: not in 6000 ticks).
func _repair_ticks(world: SimWorld) -> int:
	_dispatch(world)
	for t: int in 6000:
		world.step()
		if not SimFixture.of_kind(world.drain_events(), &"fault_cleared").is_empty():
			return t
	return -1


# FT: FT-SIM-025
# A fault damages the subsystem and hides its cause: the events never name it and
# known_fault_cause stays empty until it is revealed. Unknown subsystems, unlisted causes
# and no energy are refused.
func test_inflicted_fault_hides_its_cause() -> void:
	var world: SimWorld = _world()
	assert_bool(DamageSystem.inflict_fault(world, 0, &"engines", &"magic", FAULT_J)).is_false()
	assert_bool(DamageSystem.inflict_fault(world, 0, &"engines", &"short", 0.0)).is_false()
	assert_bool(DamageSystem.inflict_fault(world, 0, &"sensors", &"short", FAULT_J)).is_false()
	assert_bool(DamageSystem.inflict_fault(world, 0, &"nope", &"short", FAULT_J)).is_false()
	assert_float(_health(world)).is_equal(2e7)
	assert_bool(DamageSystem.inflict_fault(world, 0, &"engines", &"short", FAULT_J)).is_true()
	assert_float(_health(world)).is_equal_approx(2e7 - FAULT_J, 1e-6)
	var events: Array[SimEvent] = world.drain_events()
	var raised: Array[SimEvent] = SimFixture.of_kind(events, &"fault_inflicted")
	assert_int(raised.size()).is_equal(1)
	assert_str(String(raised[0].tag)).is_equal("engines")
	assert_float(raised[0].value).is_equal(0.0)
	assert_str(String(DamageSystem.known_fault_cause(world, 0, &"engines"))).is_equal("")


# FT: FT-SIM-025, FT-ENG-006
# P10: repair with the correct cause picked is faster than brute force (no pick, or a
# wrong pick), by the subsystem's brute-force factor; brute force still repairs.
func test_correct_cause_repairs_fast_and_brute_force_slow() -> void:
	var times: Dictionary[String, int] = {}
	for mode: String in ["correct", "wrong", "none"]:
		var world: SimWorld = _world()
		DamageSystem.inflict_fault(world, 0, &"engines", &"short", FAULT_J)
		if mode != "none":
			var pick: PickFaultCauseCommand = PickFaultCauseCommand.new()
			pick.ship_id = 0
			pick.subsystem_id = &"engines"
			pick.cause = &"short" if mode == "correct" else &"software"
			world.submit(pick)
			world.step()
			assert_bool(pick.accepted).is_true()
		times[mode] = _repair_ticks(world)
		assert_int(times[mode]).is_greater(0)
		assert_float(_health(world)).is_equal(2e7)
	assert_int(times["correct"]).is_between(TICKS_FULL - 5, TICKS_FULL + 5)
	assert_int(times["wrong"]).is_between(4 * TICKS_FULL - 20, 4 * TICKS_FULL + 20)
	assert_int(times["none"]).is_equal(times["wrong"])
	assert_int(times["correct"]).is_less(times["none"])


# FT: FT-SIM-025
# The brute-force speed is the subsystem's own data value.
func test_brute_force_factor_is_data() -> void:
	var world: SimWorld = _world({"fault_brute_force_factor": 0.5})
	DamageSystem.inflict_fault(world, 0, &"engines", &"short", FAULT_J)
	assert_int(_repair_ticks(world)).is_between(2 * TICKS_FULL - 10, 2 * TICKS_FULL + 10)


# FT: FT-SIM-025, FT-ENG-006
# Science's scan reveals the cause (the station may then read it); Engineering still has
# to pick it. Revealing a subsystem without a fault does nothing.
func test_revealed_cause() -> void:
	var world: SimWorld = _world()
	assert_bool(DamageSystem.reveal_fault_cause(world, 0, &"engines")).is_false()
	DamageSystem.inflict_fault(world, 0, &"engines", &"software", FAULT_J)
	world.drain_events()
	assert_bool(DamageSystem.reveal_fault_cause(world, 0, &"engines")).is_true()
	assert_str(String(DamageSystem.known_fault_cause(world, 0, &"engines"))).is_equal("software")
	var revealed: Array[SimEvent] = SimFixture.of_kind(
		world.drain_events(), &"fault_cause_revealed"
	)
	assert_float(revealed[0].value).is_equal(3.0)
	# Revealed but not picked: still brute force.
	assert_int(_repair_ticks(world)).is_greater(3 * TICKS_FULL)


# FT: FT-ENG-006
# Picking needs a fault and one of the subsystem's causes; the pick is a guess, so a
# wrong one is accepted; a finished repair clears the fault, its cause and the pick.
func test_picking_a_cause() -> void:
	var world: SimWorld = _world()
	assert_bool(DamageSystem.pick_fault_cause(world, 0, &"engines", &"short")).is_false()
	DamageSystem.inflict_fault(world, 0, &"engines", &"short", FAULT_J)
	assert_bool(DamageSystem.pick_fault_cause(world, 0, &"engines", &"magic")).is_false()
	assert_bool(DamageSystem.pick_fault_cause(world, 0, &"engines", &"software")).is_true()
	assert_bool(DamageSystem.pick_fault_cause(world, 0, &"engines", &"short")).is_true()
	_repair_ticks(world)
	var t: DamageTable = world.damage
	var r: int = t.find_subsystem(0, &"engines")
	assert_str(String(t.fault_cause[r])).is_equal("")
	assert_str(String(t.fault_pick[r])).is_equal("")
	assert_int(t.fault_known[r]).is_equal(0)


# FT: FT-SIM-025
# A subsystem with a fault repairs at the normal rate otherwise: an ordinary hit does not
# slow the repair.
func test_ordinary_damage_repairs_at_full_rate() -> void:
	var world: SimWorld = _world()
	DamageSystem.damage_subsystem(world, 0, 0, FAULT_J)
	_dispatch(world)
	var ticks: int = 0
	while _health(world) < 2e7 and ticks < 2000:
		world.step()
		ticks += 1
	assert_int(ticks).is_between(TICKS_FULL - 5, TICKS_FULL + 5)


# FT: FT-ENG-008
# Hardening takes the subsystem's parts, lasts its duration, and while it lasts a hit
# damages the subsystem by the hardened factor only; the hull share is unchanged. Without
# hardening the same hit does full damage.
func test_hardening_reduces_damage_for_its_duration() -> void:
	var world: SimWorld = _world({"harden_duration": 2.0, "harden_factor": 0.4, "harden_parts": 2})
	var hull: int = world.damage.hull_row(0)
	var parts: int = world.damage.spare_parts[hull]
	var cmd: HardenCommand = HardenCommand.new()
	cmd.ship_id = 0
	cmd.subsystem_id = &"engines"
	world.submit(cmd)
	world.step()
	assert_bool(cmd.accepted).is_true()
	assert_int(world.damage.spare_parts[hull]).is_equal(parts - 2)
	# Already hardened: refused, and no more parts are taken.
	var again: HardenCommand = HardenCommand.new()
	again.ship_id = 0
	again.subsystem_id = &"engines"
	world.submit(again)
	world.step()
	assert_bool(again.accepted).is_false()
	assert_int(world.damage.spare_parts[hull]).is_equal(parts - 2)
	world.shields.strength[0] = 0.0
	var h: SimHit = SimHit.new()
	h.target_id = 0
	h.source_id = -1
	h.kind = &"projectile"
	h.point_local = Vector3(0, 0, 18)
	h.energy = 1e6
	world.hits.append(h)
	HitResolver.resolve(world)
	# Subsystem share 0.5 of 1e6, taken at 0.4.
	assert_float(2e7 - _health(world)).is_equal_approx(0.5e6 * 0.4, 1e-6)
	assert_float(world.defs[0].hull_max - world.damage.health[hull]).is_equal_approx(0.5e6, 1e-6)
	var events: Array[SimEvent] = SimFixture.run(world, 130)
	assert_int(SimFixture.of_kind(events, &"harden_expired").size()).is_equal(1)
	var before: float = _health(world)
	world.shields.strength[0] = 0.0
	h = SimHit.new()
	h.target_id = 0
	h.source_id = -1
	h.kind = &"projectile"
	h.point_local = Vector3(0, 0, 18)
	h.energy = 1e6
	world.hits.append(h)
	HitResolver.resolve(world)
	assert_float(before - _health(world)).is_equal_approx(0.5e6, 1e-6)


# FT: FT-ENG-008
# Hardening is refused, changing nothing, without enough spare parts (it says so), and for
# an unknown subsystem.
func test_hardening_needs_parts_and_a_subsystem() -> void:
	var world: SimWorld = _world()
	world.damage.spare_parts[world.damage.hull_row(0)] = 0
	assert_bool(DamageSystem.harden(world, 0, &"engines")).is_false()
	assert_int(SimFixture.of_kind(world.drain_events(), &"harden_no_parts").size()).is_equal(1)
	assert_bool(DamageSystem.harden(world, 0, &"nope")).is_false()
	assert_int(world.damage.hardened_ticks[world.damage.find_subsystem(0, &"engines")]).is_equal(0)


# FT: FT-ENG-008
# A hit that would finish a hardened subsystem passes on only the energy beyond what the
# subsystem could absorb, so hull and other subsystems still take the rest (D123).
func test_hardened_overflow_passes_on() -> void:
	var world: SimWorld = _world({"harden_factor": 0.5})
	DamageSystem.harden(world, 0, &"engines")
	var r: int = world.damage.find_subsystem(0, &"engines")
	world.damage.health[r] = 1e6
	world.shields.strength[0] = 0.0
	var h: SimHit = SimHit.new()
	h.target_id = 0
	h.source_id = -1
	h.kind = &"projectile"
	h.point_local = Vector3(0, 0, 18)
	h.energy = 6e6
	world.hits.append(h)
	HitResolver.resolve(world)
	assert_float(world.damage.health[r]).is_equal(0.0)
	# 3e6 aimed at the subsystem; 1e6 of health absorbs 2e6 of it; 1e6 passes to the
	# next-nearest subsystem (thrusters here) and the hull takes its own 3e6.
	var lost: float = 0.0
	for s: StringName in [&"thrusters", &"weapons", &"shields", &"sensors", &"reactor"]:
		lost += 2e7 - _health(world, s)
	assert_float(lost).is_equal_approx(1e6, 1e-6)
	var hull: int = world.damage.hull_row(0)
	assert_float(world.defs[0].hull_max - world.damage.health[hull]).is_equal_approx(3e6, 1e-6)


# FT: FT-SIM-025, FT-ENG-008
# The new commands survive the command log's round trip.
func test_commands_round_trip() -> void:
	var pick: PickFaultCauseCommand = PickFaultCauseCommand.new()
	pick.subsystem_id = &"engines"
	pick.cause = &"short"
	assert_dict(SimCommands.from_dict(pick.to_dict()).to_dict()).is_equal(pick.to_dict())
	var harden: HardenCommand = HardenCommand.new()
	harden.subsystem_id = &"engines"
	assert_dict(SimCommands.from_dict(harden.to_dict()).to_dict()).is_equal(harden.to_dict())


## A world whose ship has the given fault-on-hit numbers and fault causes everywhere.
func _heavy_world(world_seed: int, threshold: float, chance: float) -> SimWorld:
	var def: ShipDef = _def()
	def.fault_hit_threshold = threshold
	def.fault_hit_chance = chance
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = s.duplicate()
		copy.fault_causes = CAUSES
		subs.append(copy)
	def.subsystems = subs
	var world: SimWorld = SimWorld.new(world_seed)
	world.spawn_ship(def, 2, 0)
	return world


func _hit(world: SimWorld, energy: float) -> void:
	var hit: SimHit = SimHit.new()
	hit.target_id = 0
	hit.point_local = world.defs[0].subsystems[0].position
	hit.kind = &"projectile"
	DamageSystem.apply_hit(world, hit, energy)


func _faults(world: SimWorld) -> int:
	var n: int = 0
	for cause: StringName in world.damage.fault_cause:
		n += 1 if cause != &"" else 0
	return n


# FT: FT-SIM-025
# D220: a hit above the ship's threshold causes an unknown-cause fault in the subsystem it
# landed on with the ship's chance; a lighter hit, a chance of 0 and a subsystem that
# already has a fault change nothing; the draw is seeded, so a world repeats.
func test_heavy_hits_can_cause_a_fault() -> void:
	var light: SimWorld = _heavy_world(4, 1.0e6, 1.0)
	_hit(light, 1.0e6)
	assert_int(_faults(light)).is_equal(0)
	var never: SimWorld = _heavy_world(4, 1.0e6, 0.0)
	_hit(never, 5.0e6)
	assert_int(_faults(never)).is_equal(0)
	var heavy: SimWorld = _heavy_world(4, 1.0e6, 1.0)
	_hit(heavy, 5.0e6)
	assert_int(_faults(heavy)).is_equal(1)
	var row: int = heavy.damage.subsystem_row(0, 0)
	assert_bool(heavy.damage.fault_cause[row] in CAUSES).is_true()
	assert_int(SimFixture.of_kind(heavy.drain_events(), &"fault_inflicted").size()).is_equal(1)
	var before: StringName = heavy.damage.fault_cause[row]
	_hit(heavy, 5.0e6)
	assert_str(heavy.damage.fault_cause[row]).is_equal(before)
	var again: SimWorld = _heavy_world(4, 1.0e6, 1.0)
	_hit(again, 5.0e6)
	var first: SimWorld = _heavy_world(4, 1.0e6, 1.0)
	_hit(first, 5.0e6)
	assert_str(again.state_hash()).is_equal(first.state_hash())
	# About a fifth of the heavy hits fault at the shipped 0.2.
	var hits: int = 0
	for i: int in 200:
		var w: SimWorld = _heavy_world(i, 1.0e6, 0.2)
		_hit(w, 5.0e6)
		hits += _faults(w)
	assert_int(hits).is_between(20, 60)
