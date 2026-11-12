extends GdUnitTestSuite
## R09-14: edges of hit splitting, hardening and repair. M1 corvette: hull 1e8 J, six
## subsystems of 2e7 J, subsystem share 0.5, harden_factor 0.5, 20 parts. Hits are applied
## straight to the damage table (no shields), at the bow so the weapons take the share.

const BOW: Vector3 = Vector3(0, 0, -25)


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(TestDefs.corvette(), 1, CubePoint.make())
	return w


func _hit(w: SimWorld, energy: float) -> void:
	var h: SimHit = SimHit.new()
	h.target_id = 0
	h.source_id = -1
	h.kind = &"projectile"
	h.point_local = BOW
	h.energy = energy
	DamageSystem.apply_hit(w, h, energy)


func _health(w: SimWorld, id: StringName) -> float:
	return w.damage.health[w.damage.find_subsystem(0, id)]


func _hull(w: SimWorld) -> float:
	return w.damage.health[w.damage.hull_row(0)]


func _subsystems_lost(w: SimWorld) -> float:
	var lost: float = 0.0
	for r: int in w.damage.rows_of(0):
		if r != w.damage.hull_row(0):
			lost += 2e7 - w.damage.health[r]
	return lost


# FT: FT-SIM-020, FT-SIM-030
# A hit whose subsystem share equals the subsystem's remaining health destroys it exactly:
# one subsystem_destroyed, nothing passes on, and the hull takes only its own share.
func test_hit_equal_to_remaining_health_destroys_once_with_no_overflow() -> void:
	var w: SimWorld = _world()
	_hit(w, 4e7)
	assert_float(_health(w, &"weapons")).is_equal(0.0)
	assert_float(_hull(w)).is_equal(1e8 - 2e7)
	assert_float(_subsystems_lost(w)).is_equal(2e7)
	var destroyed: Array[SimEvent] = SimFixture.of_kind(w.drain_events(), &"subsystem_destroyed")
	assert_int(destroyed.size()).is_equal(1)
	assert_str(String(destroyed[0].tag)).is_equal("weapons")


# FT: FT-SIM-020, FT-ENG-008
# A hardened subsystem takes harden_factor of the energy: a share it can absorb is halved
# and nothing overflows; the hull share is unchanged.
func test_hardened_subsystem_takes_harden_factor_of_the_share() -> void:
	var w: SimWorld = _world()
	assert_bool(DamageSystem.harden(w, 0, &"weapons")).is_true()
	_hit(w, 4e7)
	assert_float(_health(w, &"weapons")).is_equal(1e7)
	assert_float(_hull(w)).is_equal(1e8 - 2e7)


# FT: FT-SIM-020, FT-ENG-008
# The share that finishes a hardened subsystem exactly overflows nothing; one beyond it
# overflows only the energy past the part that finishes it (_damage_row) to the next live
# subsystem. Hull and subsystems then took 1e8 - 1e7 (the 1e7 absorbed by the hardening
# is gone: FT-SIM-020 holds for unhardened subsystems, R16-9).
func test_hardened_overflow_is_the_energy_beyond_what_finishes_it() -> void:
	var w: SimWorld = _world()
	DamageSystem.harden(w, 0, &"weapons")
	_hit(w, 8e7)
	assert_float(_health(w, &"weapons")).is_equal(0.0)
	assert_float(_subsystems_lost(w)).is_equal(2e7)
	assert_float(_hull(w)).is_equal(1e8 - 4e7)
	var over: SimWorld = _world()
	DamageSystem.harden(over, 0, &"weapons")
	_hit(over, 1e8)
	# Share 5e7: the weapons finish at 4e7 of it, 1e7 passes on, the hull takes 5e7.
	assert_float(_health(over, &"weapons")).is_equal(0.0)
	assert_float(_subsystems_lost(over)).is_equal_approx(3e7, 1e-6)
	assert_float(_hull(over)).is_equal_approx(5e7, 1e-6)
	assert_int(SimFixture.of_kind(over.drain_events(), &"subsystem_destroyed").size()).is_equal(1)


# FT: FT-ENG-008, FT-SIM-024
# Hardening that ends on the tick a repair finishes: both events come out of that one tick,
# the subsystem is whole and no longer hardened.
func test_hardening_expires_the_tick_a_repair_finishes() -> void:
	var w: SimWorld = _world()
	var r: int = w.damage.find_subsystem(0, &"weapons")
	DamageSystem.harden(w, 0, &"weapons")
	w.damage.health[r] = 2e7 - 1.0
	assert_bool(DamageSystem.dispatch(w, 0, 0, &"weapons")).is_true()
	w.damage.hardened_ticks[r] = 1
	w.drain_events()
	w.step()
	var events: Array[SimEvent] = w.drain_events()
	assert_int(SimFixture.of_kind(events, &"harden_expired").size()).is_equal(1)
	assert_int(SimFixture.of_kind(events, &"repair_finished").size()).is_equal(1)
	assert_int(w.damage.hardened_ticks[r]).is_equal(0)
	assert_int(w.damage.crews[r]).is_equal(0)
	assert_float(_health(w, &"weapons")).is_equal(2e7)


# FT: FT-SIM-024
# A crew sent to a destroyed subsystem repairs it from 0, at repair_rate per tick.
func test_repair_dispatched_to_a_destroyed_subsystem_starts_from_zero() -> void:
	var w: SimWorld = _world()
	_hit(w, 4e7)
	assert_float(_health(w, &"weapons")).is_equal(0.0)
	assert_bool(DamageSystem.dispatch(w, 0, 0, &"weapons")).is_true()
	w.step()
	assert_float(_health(w, &"weapons")).is_equal_approx(2e5 / SimWorld.HZ, 1e-3)
