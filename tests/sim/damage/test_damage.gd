extends GdUnitTestSuite
## T033: hit-location damage, effectiveness curves, hull and destruction (L2). Numbers
## come from the M1 corvette: hull 1e8 J, subsystems 2e7 J each, subsystem share 0.5 (a
## hit's energy past the shields is split: half to the nearest subsystem, half to the hull).
## Tolerances: 1e-12 on fractions and 1e-6 J on energies (a few 64-bit additions);
## 1e-6 on curve values, whose points are stored as 32-bit floats (Vector2).


func _world(world_seed: int = 1) -> SimWorld:
	var w: SimWorld = SimWorld.new(world_seed, "test")
	w.spawn_ship(TestDefs.corvette(), 1, 0, Vector3.ZERO)
	w.spawn_ship(TestDefs.raider(), 2, 0, Vector3(0, 0, -2000))
	return w


func _hit(target: int, point: Vector3, energy: float, source: int = 1) -> SimHit:
	var h: SimHit = SimHit.new()
	h.target_id = target
	h.source_id = source
	h.kind = &"projectile"
	h.point_local = point
	h.energy = energy
	return h


func _health(w: SimWorld, ship: int, id: StringName) -> float:
	return w.damage.health[w.damage.find_subsystem(ship, id)]


func _set_health_fraction(w: SimWorld, ship: int, id: StringName, frac: float) -> void:
	var r: int = w.damage.find_subsystem(ship, id)
	w.damage.health[r] = frac * 2e7


func _kinds(events: Array[SimEvent]) -> Array:
	return events.map(func(e: SimEvent) -> StringName: return e.kind)


# FT: FT-SIM-020
# The subsystem nearest the impact point (ship frame) is the one hit, table-driven over
# the corvette's six subsystems; an exact tie goes to the earlier subsystem.
func test_nearest_subsystem_table() -> void:
	var def: ShipDef = TestDefs.corvette()
	var cases: Array = [
		[Vector3(0, 0, 30), &"engines"],
		[Vector3(0, 0, 14), &"engines"],
		[Vector3(0, 3, 1), &"thrusters"],
		[Vector3(0, 0, -30), &"weapons"],
		[Vector3(0, 10, -4), &"shields"],
		[Vector3(0, 6, -15), &"sensors"],
		[Vector3(0, -10, 6), &"reactor"],
		[Vector3(25, -4, 6), &"reactor"],
	]
	for c: Array in cases:
		var i: int = DamageSystem.nearest_subsystem(def, c[0])
		(
			assert_str(String(def.subsystems[i].id))
			. override_failure_message("point %s" % c[0])
			. is_equal(String(c[1]))
		)
	var tie: ShipDef = def.duplicate(true)
	tie.subsystems[1].position = Vector3(0, 0, -18)
	assert_int(DamageSystem.nearest_subsystem(tie, Vector3(0, 0, -18))).is_equal(1)


# FT: FT-SIM-020, FT-M1-009
# Through HitResolver: the shields take their share first, then the energy that passes is
# split half to the weapons subsystem (nearest the bow) and half to the hull; the other
# subsystems and the other ship are untouched. The 4e6 J hit meets full shields at
# nominal power, so 4e6 x (1 - absorb_fraction) passes.
func test_hit_damages_hull_and_nearest_subsystem_only() -> void:
	var w: SimWorld = _world()
	var hit: SimHit = _hit(0, Vector3(0, 0, -25), 4e6)
	hit.from_local = Vector3(0, 0, -1)
	var through: float = 4e6 * (1.0 - ShieldSystem.absorb_fraction(w, 0, hit.from_local))
	assert_float(through).is_between(1e5, 3.9e6)
	w.hits.append(hit)
	HitResolver.resolve(w)
	assert_float(DamageSystem.hull_fraction(w, 0)).is_equal_approx(1.0 - 0.5 * through / 1e8, 1e-12)
	assert_float(_health(w, 0, &"weapons")).is_equal_approx(2e7 - 0.5 * through, 1e-6)
	for id: StringName in [&"engines", &"thrusters", &"shields", &"sensors", &"reactor"]:
		assert_float(_health(w, 0, id)).is_equal(2e7)
	assert_float(DamageSystem.hull_fraction(w, 1)).is_equal(1.0)
	assert_float(_health(w, 1, &"weapons")).is_equal(2e7)


# FT: FT-SIM-020
# With the shields down (strength 0) the whole hit passes: a 4e6 J bow hit takes 2e6 J
# off the weapons subsystem and 2e6 J off the hull (the share splits, it does not add).
func test_hit_split_between_subsystem_and_hull() -> void:
	var w: SimWorld = _world()
	w.shields.strength[0] = 0.0
	w.hits.append(_hit(0, Vector3(0, 0, -25), 4e6))
	HitResolver.resolve(w)
	assert_float(DamageSystem.hull_fraction(w, 0)).is_equal_approx(0.98, 1e-12)
	assert_float(_health(w, 0, &"weapons")).is_equal_approx(1.8e7, 1e-6)


# FT: FT-SIM-021
# Effectiveness follows the data curve, linear between its points, at table points of
# the engines curve (0,0) (0.25,0.3) (0.5,0.8) (1,1) and the reactor curve (0,0)
# (0.3,0.5) (1,1).
func test_effectiveness_curve_table_points() -> void:
	var w: SimWorld = _world()
	var cases: Array = [
		[&"engines", 1.0, 1.0],
		[&"engines", 0.75, 0.9],
		[&"engines", 0.5, 0.8],
		[&"engines", 0.375, 0.55],
		[&"engines", 0.25, 0.3],
		[&"engines", 0.125, 0.15],
		[&"engines", 0.0, 0.0],
		[&"reactor", 0.65, 0.75],
		[&"reactor", 0.15, 0.25],
		[&"reactor", 0.3, 0.5],
	]
	for c: Array in cases:
		_set_health_fraction(w, 0, c[0], c[1])
		(
			assert_float(DamageSystem.effectiveness(w, 0, c[0]))
			. override_failure_message("%s at %s" % [c[0], c[1]])
			. is_equal_approx(c[2], 1e-6)
		)


# FT: FT-SIM-021
# A ship without the named subsystem reports full effectiveness.
func test_unknown_subsystem_is_fully_effective() -> void:
	var w: SimWorld = _world()
	assert_float(DamageSystem.effectiveness(w, 0, &"tractor")).is_equal(1.0)
	assert_float(DamageSystem.effectiveness(w, 0, &"hull")).is_equal(1.0)


# FT: FT-SIM-030
# A hull at 0 destroys the ship once (alive 0, one &"destroyed" naming the source); a
# subsystem at 0 emits &"subsystem_destroyed"; later hits change nothing. 1.2e8 J splits
# 6e7 to the raider's weapons (2e7) and 6e7 to its hull (5e7).
func test_hull_zero_destroys_ship_with_events() -> void:
	var w: SimWorld = _world()
	w.drain_events()
	DamageSystem.apply_hit(w, _hit(1, Vector3(0, 0, -30), 1.2e8), 1.2e8)
	assert_bool(w.kin.is_alive(1)).is_false()
	assert_float(DamageSystem.hull_fraction(w, 1)).is_equal(0.0)
	var events: Array[SimEvent] = w.drain_events()
	assert_array(_kinds(events)).is_equal(
		[&"subsystem_damaged", &"subsystem_destroyed", &"destroyed"]
	)
	assert_str(String(events[0].tag)).is_equal("weapons")
	assert_float(events[0].value).is_equal(0.0)
	assert_int(events[2].ship_id).is_equal(1)
	assert_int(events[2].faction).is_equal(2)
	assert_int(events[2].other_id).is_equal(1)
	DamageSystem.apply_hit(w, _hit(1, Vector3.ZERO, 1e6), 1e6)
	assert_array(w.drain_events()).is_empty()


# FT: FT-SIM-030
# A hit emits &"subsystem_damaged" with the subsystem as tag, its health fraction, its
# ship-frame position and the shooter; a fully absorbed hit (0 J through) emits nothing.
func test_subsystem_damaged_event_fields() -> void:
	var w: SimWorld = _world()
	w.drain_events()
	DamageSystem.apply_hit(w, _hit(0, Vector3(0, 0, 25), 4e6, 1), 4e6)
	var events: Array[SimEvent] = w.drain_events()
	assert_array(_kinds(events)).is_equal([&"subsystem_damaged"])
	var e: SimEvent = events[0]
	assert_str(String(e.tag)).is_equal("engines")
	assert_float(e.value).is_equal_approx(0.9, 1e-12)
	assert_vector(e.vector).is_equal(Vector3(0, 0, 18))
	assert_int(e.other_id).is_equal(1)
	DamageSystem.apply_hit(w, _hit(0, Vector3(0, 0, 25), 4e6), 0.0)
	assert_array(w.drain_events()).is_empty()
	assert_float(DamageSystem.hull_fraction(w, 0)).is_equal_approx(0.98, 1e-12)


# damage_subsystem (heat faults) damages only the named subsystem, not the hull.
func test_damage_subsystem_direct() -> void:
	var w: SimWorld = _world()
	DamageSystem.damage_subsystem(w, 0, &"thrusters", 5e6)
	assert_float(_health(w, 0, &"thrusters")).is_equal(1.5e7)
	assert_float(DamageSystem.hull_fraction(w, 0)).is_equal(1.0)
	DamageSystem.damage_subsystem(w, 0, &"nope", 5e6)
	DamageSystem.damage_subsystem(w, 0, &"thrusters", 1e9)
	assert_float(_health(w, 0, &"thrusters")).is_equal(0.0)
	assert_float(DamageSystem.effectiveness(w, 0, &"thrusters")).is_equal(0.0)


# Damage is a function of the hit and the state only: worlds with different seeds take
# the same hits to the same table, and equal hits take equal amounts.
func test_damage_independent_of_seed() -> void:
	var a: SimWorld = _world(1)
	var b: SimWorld = _world(999)
	for w: SimWorld in [a, b]:
		for k: int in 3:
			DamageSystem.apply_hit(w, _hit(0, Vector3(0, 7, -4), 1e6), 1e6)
	assert_array(a.damage.columns()).is_equal(b.damage.columns())
	assert_float(_health(a, 0, &"shields")).is_equal_approx(2e7 - 1.5e6, 1e-6)
	assert_float(DamageSystem.hull_fraction(a, 0)).is_equal_approx(0.985, 1e-12)


# FT: FT-ARC-012
# The table holds a hull row then one row per subsystem per ship, keyed by ship and
# faction; reset_ship restores one ship's rows and leaves the other's damage alone.
func test_rows_and_reset_ship() -> void:
	var w: SimWorld = _world()
	assert_int(w.damage.size()).is_equal(14)
	assert_array(Array(w.damage.rows_of(1))).is_equal([7, 8, 9, 10, 11, 12, 13])
	assert_int(w.damage.factions[7]).is_equal(2)
	assert_str(String(w.damage.part_ids[7])).is_equal("hull")
	DamageSystem.apply_hit(w, _hit(0, Vector3(0, 0, -25), 4e6), 4e6)
	DamageSystem.apply_hit(w, _hit(1, Vector3(0, 0, -25), 4e6), 4e6)
	DamageSystem.damage_subsystem(w, 0, &"engines", 1e6)
	assert_bool(DamageSystem.dispatch(w, 0, 1, &"engines")).is_true()
	w.reset_ship(0, 0)
	assert_float(DamageSystem.hull_fraction(w, 0)).is_equal(1.0)
	assert_float(_health(w, 0, &"weapons")).is_equal(2e7)
	assert_int(w.damage.spare_parts[w.damage.hull_row(0)]).is_equal(20)
	for r: int in w.damage.rows_of(0):
		assert_int(w.damage.crews[r]).is_equal(0)
	assert_float(DamageSystem.hull_fraction(w, 1)).is_equal_approx(0.96, 1e-12)
