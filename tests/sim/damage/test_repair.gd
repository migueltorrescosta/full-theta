extends GdUnitTestSuite
## T033: repair crews with spare parts (L2). M1 corvette: 2 crews, 20 parts, each
## subsystem 2e7 J, repair_rate 2e5 J/s per crew, 1 part per repair. Repairs add
## repair_rate * DT per tick, so health is compared within 1e-3 J (accumulated 64-bit
## rounding over a few hundred additions of ~3333 J).


func _world(def: ShipDef = null) -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(def if def != null else TestDefs.corvette(), 1, 0, Vector3.ZERO)
	return w


func _dispatch(w: SimWorld, crew: int, id: StringName) -> void:
	var c: DispatchRepairCommand = DispatchRepairCommand.new()
	c.ship_id = 0
	c.crew = crew
	c.subsystem_id = id
	w.submit(c)


func _recall(w: SimWorld, crew: int) -> void:
	var c: RecallRepairCommand = RecallRepairCommand.new()
	c.ship_id = 0
	c.crew = crew
	w.submit(c)


func _steps(w: SimWorld, n: int) -> void:
	for i: int in n:
		w.step()


func _health(w: SimWorld, id: StringName) -> float:
	return w.damage.health[w.damage.find_subsystem(0, id)]


## Spare parts in stock: the hull row's spare_parts.
func _parts(w: SimWorld) -> int:
	return w.damage.spare_parts[w.damage.hull_row(0)]


## The subsystem the crew works on (its bit in a row's crews), or "" when idle.
func _job(w: SimWorld, crew: int) -> StringName:
	for r: int in w.damage.rows_of(0):
		if w.damage.crews[r] & (1 << crew):
			return w.damage.part_ids[r]
	return &""


# FT: FT-SIM-024, FT-M1-009, FT-SIM-030
# A subsystem damaged by hit location is repaired over time by a dispatched crew: one
# part leaves stock when the job starts, health rises at repair_rate (1e6 J in 5 s =
# 300 ticks), and the crew goes idle with &"repair_finished" once it is whole.
func test_crew_repairs_over_time_using_parts() -> void:
	var w: SimWorld = _world()
	var hit: SimHit = SimHit.new()
	hit.target_id = 0
	hit.point_local = Vector3(0, 0, -25)
	DamageSystem.apply_hit(w, hit, 2e6)
	assert_float(_health(w, &"weapons")).is_equal_approx(1.9e7, 1e-3)
	w.drain_events()
	_dispatch(w, 0, &"weapons")
	_steps(w, 150)
	assert_int(_parts(w)).is_equal(19)
	assert_str(String(_job(w, 0))).is_equal("weapons")
	assert_float(_health(w, &"weapons")).is_equal_approx(1.95e7, 1e-3)
	assert_int(w.accepted_commands().size()).is_equal(1)
	_steps(w, 149)
	assert_float(_health(w, &"weapons")).is_less(2e7)
	_steps(w, 2)
	assert_float(_health(w, &"weapons")).is_equal(2e7)
	assert_float(DamageSystem.effectiveness(w, 0, &"weapons")).is_equal(1.0)
	assert_str(String(_job(w, 0))).is_equal("")
	assert_int(_parts(w)).is_equal(19)
	var events: Array[SimEvent] = w.drain_events()
	var started: Array[SimEvent] = SimFixture.of_kind(events, &"repair_started")
	var finished: Array[SimEvent] = SimFixture.of_kind(events, &"repair_finished")
	assert_int(started.size()).is_equal(1)
	assert_int(finished.size()).is_equal(1)
	assert_str(String(started[0].tag)).is_equal("weapons")
	assert_int(started[0].tick).is_equal(0)
	assert_float(finished[0].value).is_equal(0.0)
	assert_str(String(finished[0].tag)).is_equal("weapons")


# FT: FT-SIM-024
# Two crews on one subsystem repair twice as fast and each job uses its own part.
func test_two_crews_repair_twice_as_fast() -> void:
	var w: SimWorld = _world()
	DamageSystem.damage_subsystem(w, 0, SimFixture.sub_index(w, 0, &"engines"), 1e6)
	_dispatch(w, 0, &"engines")
	_dispatch(w, 1, &"engines")
	_steps(w, 60)
	assert_float(_health(w, &"engines")).is_equal_approx(1.9e7 + 4e5, 1e-3)
	assert_int(_parts(w)).is_equal(18)


# FT: FT-SIM-024, FT-M1-009, FT-SIM-030
# No parts, no repair: the dispatch is rejected (not logged), emits &"repair_no_parts",
# and health stays put.
func test_no_parts_no_repair() -> void:
	var def: ShipDef = TestDefs.corvette().duplicate(true)
	def.spare_parts = 1
	var w: SimWorld = _world(def)
	DamageSystem.damage_subsystem(w, 0, SimFixture.sub_index(w, 0, &"engines"), 1e6)
	DamageSystem.damage_subsystem(w, 0, SimFixture.sub_index(w, 0, &"sensors"), 1e6)
	w.drain_events()
	_dispatch(w, 0, &"engines")
	_dispatch(w, 1, &"sensors")
	_steps(w, 60)
	assert_int(_parts(w)).is_equal(0)
	assert_float(_health(w, &"sensors")).is_equal(1.9e7)
	assert_str(String(_job(w, 1))).is_equal("")
	assert_int(w.accepted_commands().size()).is_equal(1)
	var no_parts: Array[SimEvent] = SimFixture.of_kind(w.drain_events(), &"repair_no_parts")
	assert_int(no_parts.size()).is_equal(1)
	assert_str(String(no_parts[0].tag)).is_equal("sensors")
	assert_float(no_parts[0].value).is_equal(1.0)


# FT: FT-SIM-024
# Rejected without using parts: a whole subsystem, an unknown subsystem or crew, and a
# crew already on that job.
func test_invalid_dispatches_rejected() -> void:
	var w: SimWorld = _world()
	assert_bool(DamageSystem.dispatch(w, 0, 0, &"engines")).is_false()
	DamageSystem.damage_subsystem(w, 0, SimFixture.sub_index(w, 0, &"engines"), 1e6)
	assert_bool(DamageSystem.dispatch(w, 0, 0, &"tractor")).is_false()
	assert_bool(DamageSystem.dispatch(w, 0, 0, &"hull")).is_false()
	assert_bool(DamageSystem.dispatch(w, 0, 2, &"engines")).is_false()
	assert_bool(DamageSystem.dispatch(w, 0, -1, &"engines")).is_false()
	assert_bool(DamageSystem.dispatch(w, 0, 0, &"engines")).is_true()
	assert_bool(DamageSystem.dispatch(w, 0, 0, &"engines")).is_false()
	assert_int(_parts(w)).is_equal(19)


# FT: FT-SIM-024, FT-SIM-030
# A recalled crew stops repairing (&"repair_recalled"); the part it used stays used.
# Sending a busy crew elsewhere moves it and starts a new job with a new part.
func test_recall_and_reassign() -> void:
	var w: SimWorld = _world()
	DamageSystem.damage_subsystem(w, 0, SimFixture.sub_index(w, 0, &"engines"), 1e6)
	DamageSystem.damage_subsystem(w, 0, SimFixture.sub_index(w, 0, &"reactor"), 1e6)
	_dispatch(w, 0, &"engines")
	_steps(w, 60)
	_recall(w, 0)
	_steps(w, 60)
	assert_float(_health(w, &"engines")).is_equal_approx(1.9e7 + 2e5, 1e-3)
	assert_int(_parts(w)).is_equal(19)
	assert_int(SimFixture.of_kind(w.drain_events(), &"repair_recalled").size()).is_equal(1)
	_dispatch(w, 0, &"engines")
	_steps(w, 1)
	_dispatch(w, 0, &"reactor")
	_steps(w, 60)
	assert_str(String(_job(w, 0))).is_equal("reactor")
	assert_float(_health(w, &"reactor")).is_equal_approx(1.9e7 + 2e5, 1e-3)
	assert_int(_parts(w)).is_equal(17)
	_recall(w, 1)
	_steps(w, 1)
	assert_int(w.accepted_commands().size()).is_equal(4)
