extends GdUnitTestSuite
## D124, D229: the scenario's one cube wraps as a 3-torus of side P (Kinematics.period,
## 400 km by default):
## offsets stay in [-P/2, P/2) and every position difference is the minimum image, so
## shots, contacts, warnings, sensors, lead, Helm's face and approach, and whole fights
## work the same across a seam (FT-SIM-035). Ships here straddle the +X / -X faces at
## +-P/2: a ship at P/2 - a and one at -P/2 + b are a + b apart.

const CORVETTE_FACTION: int = 1
const RAIDER_FACTION: int = 2
## A bow on +X (Godot bows are -Z).
const BOW_PLUS_X: Quaternion = Quaternion(Vector3.UP, -PI / 2.0)


func _half(w: SimWorld) -> float:
	return 0.5 * w.kin.period


func _hits_on(events: Array[SimEvent], target: int, kind: StringName) -> Array[SimEvent]:
	return events.filter(
		func(e: SimEvent) -> bool: return e.kind == &"hit" and e.ship_id == target and e.tag == kind
	)


# FT: FT-SIM-035, FT-SIM-009
# A projectile fired at 1500 m/s along +X from 100 m short of the +X face hits a ship
# 300 m past the -X face (400 m away by minimum image) within 30 ticks; after crossing
# the projectile's offset is back inside [-P/2, P/2).
func test_projectile_hits_across_the_seam() -> void:
	var w: SimWorld = SimWorld.new(1)
	var half: float = _half(w)
	var shooter: int = w.spawn_ship(TestDefs.corvette(), CORVETTE_FACTION, Vector3(0, 0, 9000))
	var target: int = w.spawn_ship(TestDefs.raider(), RAIDER_FACTION, Vector3(-half + 300, 0, 0))
	w.projectiles.spawn(
		shooter, CORVETTE_FACTION, half - 100.0, 0.0, 0.0, Vector3(1500, 0, 0), 0.5, 1e5, 60
	)
	var events: Array[SimEvent] = []
	var crossed: bool = false
	for i: int in 30:
		w.step()
		events.append_array(w.drain_events())
		if w.projectiles.size() > 0:
			var x: float = w.projectiles.px[0]
			assert_bool(x >= -half and x < half).override_failure_message(str(x)).is_true()
			crossed = crossed or x < 0.0
	assert_bool(crossed).is_true()
	assert_int(_hits_on(events, target, &"projectile").size()).is_equal(1)
	assert_int(w.projectiles.size()).is_equal(0)


# FT: FT-SIM-035, FT-SIM-009
# A raider (radius 20 m) centred 5 m past the -X face sticks 15 m out of the +X face.
# A shot at 1500 m/s (25 m a tick) from 110 m short of the +X face hits its near
# surface by minimum image on the 4th tick (tick 3, at 95 m, before the shot crosses
# the seam) with the hit point 20.5 m (hull plus shot radius) on the raider's -X side.
func test_projectile_hits_a_ship_straddling_the_seam() -> void:
	var w: SimWorld = SimWorld.new(1)
	var half: float = _half(w)
	var shooter: int = w.spawn_ship(TestDefs.corvette(), CORVETTE_FACTION, Vector3(0, 0, 9000))
	var target: int = w.spawn_ship(TestDefs.raider(), RAIDER_FACTION, Vector3(-half + 5, 0, 0))
	w.projectiles.spawn(
		shooter, CORVETTE_FACTION, half - 110.0, 0.0, 0.0, Vector3(1500, 0, 0), 0.5, 1e5, 60
	)
	var hits: Array[SimEvent] = _hits_on(SimFixture.run(w, 10), target, &"projectile")
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0].tick).is_equal(3)
	assert_vector(hits[0].vector).is_equal_approx(Vector3(-20.5, 0, 0), Vector3.ONE * 0.01)


# FT: FT-SIM-035, FT-SIM-009, FT-SIM-010
# Two corvettes 60 m apart across the seam, closing at 10 m/s (decoupled, coasting):
# both get &"proximity" warnings first, then they collide (a &"collision" hit on each).
func test_collision_and_warning_across_the_seam() -> void:
	var w: SimWorld = SimWorld.new(1)
	var half: float = _half(w)
	var a: int = w.spawn_ship(
		TestDefs.corvette(), CORVETTE_FACTION, Vector3(half - 30, 0, 0), BOW_PLUS_X
	)
	var b: int = w.spawn_ship(
		TestDefs.corvette(), CORVETTE_FACTION, Vector3(-half + 30, 0, 0), BOW_PLUS_X
	)
	w.kin.vel[a] = Vector3(5, 0, 0)
	w.kin.vel[b] = Vector3(-5, 0, 0)
	w.helm.decoupled[a] = 1
	w.helm.decoupled[b] = 1
	var events: Array[SimEvent] = SimFixture.run(w, 10 * SimWorld.HZ)
	var warned: Array[SimEvent] = SimFixture.of_kind(events, &"proximity")
	var hit_a: Array[SimEvent] = _hits_on(events, a, &"collision")
	var hit_b: Array[SimEvent] = _hits_on(events, b, &"collision")
	assert_bool(warned.any(func(e: SimEvent) -> bool: return e.ship_id == a)).is_true()
	assert_bool(warned.any(func(e: SimEvent) -> bool: return e.ship_id == b)).is_true()
	assert_bool(hit_a.is_empty() or hit_b.is_empty()).is_false()
	assert_int(warned[0].tick).is_less(hit_a[0].tick)


# FT: FT-SIM-035, FT-ARC-013
# Sensors use the minimum image: a raider 3 km from the corvette across the seam is
# detected and identified (corvette sensors 20 km, identification 8 km); one at the
# site centre, 99 km away, is not.
func test_sensors_across_the_seam() -> void:
	var w: SimWorld = SimWorld.new(1)
	var half: float = _half(w)
	w.spawn_ship(TestDefs.corvette(), CORVETTE_FACTION, Vector3(half - 1000, 0, 0))
	var near: int = w.spawn_ship(TestDefs.raider(), RAIDER_FACTION, Vector3(-half + 2000, 0, 0))
	var far: int = w.spawn_ship(TestDefs.raider(), RAIDER_FACTION, Vector3.ZERO)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, CORVETTE_FACTION, near)).is_true()
	assert_bool(KnowledgeSystem.is_identified(w, CORVETTE_FACTION, near)).is_true()
	assert_bool(KnowledgeSystem.is_detected(w, CORVETTE_FACTION, far)).is_false()


# FT: FT-SIM-035
# The lead intercept across the seam equals the one for the same geometry away from
# it (shooter at the centre, target 2 km on +X moving 50 m/s on +Y) within 1 mm.
func test_lead_intercept_across_the_seam() -> void:
	var aims: Array[Vector3] = []
	for across: bool in [false, true]:
		var w: SimWorld = SimWorld.new(1)
		var half: float = _half(w)
		var at: Vector3 = Vector3(half - 1000, 0, 0) if across else Vector3.ZERO
		var to: Vector3 = Vector3(-half + 1000, 0, 0) if across else Vector3(2000, 0, 0)
		var s: int = w.spawn_ship(TestDefs.corvette(), CORVETTE_FACTION, at, BOW_PLUS_X)
		var t: int = w.spawn_ship(TestDefs.raider(), RAIDER_FACTION, to)
		w.kin.vel[t] = Vector3(0, 50, 0)
		aims.append(EnemyAi.lead_aim(w, s, 0, t, 0))
	assert_bool(aims[0].is_finite()).is_true()
	assert_vector(aims[1]).is_equal_approx(aims[0], Vector3.ONE * 1e-3)


# FT: FT-SIM-035, FT-HLM-005, FT-HLM-006, FT-SIM-037
# Face and hold-to-approach to a point 3 km ahead across the seam (selected unwrapped,
# at P/2 + 2.5 km, and stored wrapped): the bow turns onto it (bow at -Z start, so a
# 90 deg turn) and the ship settles at the 500 m stand-off within 0.5 m in 60 s,
# crossing the seam on the way.
func test_face_and_approach_across_the_seam() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var half: float = _half(w)
	var id: int = FlightFixture.spawn(w, Vector3(half - 500, 0, 0))
	FlightFixture.select_point(w, id, Vector3(half + 2500, 0, 0))
	FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, true)
	w.step()
	assert_float(w.helm.target_x[id]).is_equal(-half + 2500)
	SimFixture.run(w, 6 * SimWorld.HZ)
	var to_point: Vector3 = AssistSystem.target_offset(w, id)
	assert_float(FlightFixture.bow_error_deg(w, id, to_point)).is_less(0.5)
	FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, false, true)
	SimFixture.run(w, 60 * SimWorld.HZ)
	assert_float(AssistSystem.target_offset(w, id).length()).is_equal_approx(500.0, 0.5)
	assert_float(w.kin.px[id]).is_between(-half, 0.0)


## The M1 encounter with every ship moved by `shift` (m, site frame); placing wraps.
func _shifted_encounter(shift: Vector3) -> SimWorld:
	var enc: M1Encounter = M1Encounter.new(21, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	var w: SimWorld = enc.build()
	for id: int in w.ship_count():
		w.kin.place(id, w.kin.px[id] + shift.x, w.kin.py[id] + shift.y, w.kin.pz[id] + shift.z)
	return w


## Runs the scripted crew for `ticks` ticks; returns (tick, kind, ship, other) per event.
func _fight(w: SimWorld, ticks: int) -> Array:
	var crew: ScriptedCrew = ScriptedCrew.new()
	var out: Array = []
	for i: int in ticks:
		crew.act(w)
		w.step()
		for e: SimEvent in w.drain_events():
			out.append([e.tick, e.kind, e.ship_id, e.other_id])
	return out


# FT: FT-SIM-035, FT-ARC-008
# Determinism over a seam: the M1 fight moved by P/2 on Z puts the corvette at -P/2
# and the raider 5 km away across the seam. Two runs with the same seed reach the same
# state hash; and the run behaves like the unshifted one (wrap invariance): the same
# events on the same ticks, hull fractions within 1e-6, velocities within 1 mm/s and
# the ships' minimum-image offset within 1 mm after 1200 ticks (20 s), while the
# corvette's own offset differs by P/2.
func test_fight_across_the_seam_is_deterministic_and_wrap_invariant() -> void:
	var ticks: int = 1200
	var half: float = 0.5 * Kinematics.DEFAULT_PERIOD
	var base: SimWorld = _shifted_encounter(Vector3.ZERO)
	var base_events: Array = _fight(base, ticks)
	var runs: Array[SimWorld] = []
	var shifted_events: Array = []
	for i: int in 2:
		var w: SimWorld = _shifted_encounter(Vector3(0, 0, half))
		shifted_events = _fight(w, ticks)
		runs.append(w)
	assert_str(runs[1].state_hash()).is_equal(runs[0].state_hash())
	var w: SimWorld = runs[0]
	assert_int(base_events.size()).is_greater(0)
	assert_array(shifted_events).is_equal(base_events)
	var p: int = M1Encounter.PLAYER_SHIP
	var e: int = M1Encounter.ENEMY_SHIP
	for id: int in [p, e]:
		assert_float(DamageSystem.hull_fraction(w, id)).is_equal_approx(
			DamageSystem.hull_fraction(base, id), 1e-6
		)
		assert_vector(w.kin.vel[id]).is_equal_approx(base.kin.vel[id], Vector3.ONE * 1e-3)
	assert_vector(w.kin.relative(p, e)).is_equal_approx(base.kin.relative(p, e), Vector3.ONE * 1e-3)
	var dz: float = absf(w.kin.pz[p] - base.kin.pz[p])
	assert_float(dz).is_equal_approx(half, 1e-3)


# FT: FT-SIM-035
# The site period is checked at load: it must be finite and positive, a whole number of
# both broadphase cells (250 m and 500 m, checked exactly: 1 mm over fails both, D125)
# and at least 4x the longest sensor range (the
# corvette's 20 km). A bad one is reported by validate() and build() returns null; the
# default 400 km and exactly 80 km pass.
func test_site_period_validation() -> void:
	var cases: Array[Array] = [
		[Kinematics.DEFAULT_PERIOD, 0],
		[80000.0, 0],
		[79500.0, 1],
		[200250.0, 1],
		[200000.001, 2],
		[NAN, 1],
		[-200000.0, 1],
	]
	for c: Array in cases:
		var enc: M1Encounter = M1Encounter.new(
			1, "test", TestDefs.corvette(), TestDefs.raider_enemy(), c[0]
		)
		var errors: Array[String] = enc.validate()
		var msg: String = "%s: %s" % [c[0], errors]
		assert_int(errors.size()).override_failure_message(msg).is_equal(c[1])
		assert_bool(enc.build() == null).override_failure_message(msg).is_equal(c[1] > 0)
	var short: M1Encounter = M1Encounter.new(
		1, "test", TestDefs.corvette(), TestDefs.raider_enemy(), 50000.0
	)
	assert_str(short.validate()[0]).contains("sensor range")


# FT: FT-SIM-035
# The period is also at most SimWorld.MAX_CELLS_PER_AXIS of either broadphase cell, so
# the collision grid's cell keys can't overflow: 2^20 cells of 250 m pass, one 500 m
# step more fails on the 250 m cell, and 1e12 m fails on both.
func test_site_period_upper_bound() -> void:
	var limit: float = SimWorld.MAX_CELLS_PER_AXIS * CollisionSystem.CELL
	var cases: Array[Array] = [[limit, 0], [limit + 500.0, 1], [1.0e12, 2]]
	for c: Array in cases:
		var enc: M1Encounter = M1Encounter.new(
			1, "test", TestDefs.corvette(), TestDefs.raider_enemy(), c[0]
		)
		var errors: Array[String] = enc.validate()
		var msg: String = "%s: %s" % [c[0], errors]
		assert_int(errors.size()).override_failure_message(msg).is_equal(c[1])
		for e: String in errors:
			assert_str(e).contains("cells of")
