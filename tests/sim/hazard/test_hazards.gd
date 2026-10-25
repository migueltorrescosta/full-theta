extends GdUnitTestSuite
## D208: the sim's hazards. A zone damages and drags the ships inside it; a front (plane or
## sphere shell) hits a ship once when its surface reaches it; a faction knows of a hazard
## when its sensors or a probe's bubble reach its surface. M1 corvette at rest at the
## origin unless a test moves it.


func _def(cls: String = "zone") -> HazardDef:
	var h: HazardDef = HazardDef.new()
	h.id = StringName(cls)
	return h


func _world(hazards: Array[HazardDef], at: Vector3 = Vector3.ZERO) -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "hazard")
	w.spawn_ship(TestDefs.corvette(), 1, 0, at)
	w.hazards = hazards
	return w


func _zone(centre: Vector3, radius: float) -> HazardDef:
	var h: HazardDef = _def()
	h.center = centre
	h.radius = radius
	h.damage_w = 1e6
	h.drag = 0.1
	return h


func _plane(start: Vector3, speed: float) -> HazardDef:
	var h: HazardDef = _def("plane")
	h.kind = HazardDef.Kind.FRONT
	h.shape = HazardDef.Shape.PLANE
	h.center = start
	h.direction = Vector3(0.0, 0.0, 1.0)
	h.speed = speed
	h.hit_j = 5e6
	return h


func _hull(w: SimWorld) -> float:
	return w.damage.health[w.damage.hull_row(0)]


# FT: FT-RLY-001, FT-PAIR-015
# A ship inside a zone loses hull at damage_w and speed at drag; outside it loses neither.
func test_zone_damages_and_drags_ships_inside() -> void:
	var w: SimWorld = _world([_zone(Vector3.ZERO, 500.0)])
	w.kin.vel[0] = Vector3(0.0, 0.0, -100.0)
	var full: float = _hull(w)
	for i: int in SimWorld.HZ:
		w.step()
	# One second: 1 MJ off the hull, about 10 % off the speed (the helm may add thrust).
	assert_float(full - _hull(w)).is_equal_approx(1e6, 1e4)
	assert_float(w.kin.vel[0].length()).is_less(95.0)
	var out: SimWorld = _world([_zone(Vector3(0.0, 0.0, -5000.0), 500.0)])
	out.kin.vel[0] = Vector3(0.0, 0.0, -1.0)
	out.step()
	assert_float(_hull(out)).is_equal(full)


# FT: FT-RLY-001
# A zone's damage can go to named subsystems instead of the hull, in a few chunks a second.
func test_zone_damage_goes_to_the_named_subsystems() -> void:
	var h: HazardDef = _zone(Vector3.ZERO, 500.0)
	h.targets = [&"sensors"]
	var w: SimWorld = _world([h])
	var full: float = _hull(w)
	var events: Array[SimEvent] = SimFixture.run(w, SimWorld.HZ)
	assert_float(_hull(w)).is_equal(full)
	var row: int = w.damage.find_subsystem(0, &"sensors")
	var max_h: float = TestDefs.corvette().subsystems[SimFixture.sub_index(w, 0, &"sensors")].health_max
	assert_float(max_h - w.damage.health[row]).is_equal_approx(1e6, 2e5)
	assert_int(SimFixture.of_kind(events, &"subsystem_damaged").size()).is_less_equal(
		SimWorld.HZ / HazardSystem.DAMAGE_EVERY
	)


# FT: FT-RLY-001, FT-PAIR-015
# A plane front hits a ship the tick its surface reaches it, once, and not again.
func test_plane_front_hits_once_on_arrival() -> void:
	var w: SimWorld = _world([_plane(Vector3(0.0, 0.0, -600.0), 100.0)])
	var events: Array[SimEvent] = SimFixture.run(w, 6 * SimWorld.HZ + 30)
	var hits: Array[SimEvent] = SimFixture.of_kind(events, &"hazard_hit")
	assert_int(hits.size()).is_equal(1)
	# 600 m at 100 m/s: tick 360.
	assert_int(hits[0].tick).is_equal(360)
	assert_float(hits[0].value).is_equal(5e6)
	assert_float(TestDefs.corvette().hull_max - _hull(w)).is_equal(5e6)


# FT: FT-RLY-001
# A sphere shell grows from its centre and hits the ship it reaches; a ship already inside
# when it sets off is not hit; a front aimed away never hits.
func test_sphere_shell_and_ships_already_behind_are_not_hit() -> void:
	var shell: HazardDef = _plane(Vector3(0.0, 0.0, -400.0), 50.0)
	shell.shape = HazardDef.Shape.SPHERE
	shell.radius = 100.0
	var w: SimWorld = _world([shell])
	var events: Array[SimEvent] = SimFixture.run(w, 7 * SimWorld.HZ)
	# 300 m more at 50 m/s: 6 s.
	assert_int(SimFixture.of_kind(events, &"hazard_hit").size()).is_equal(1)
	assert_int(SimFixture.of_kind(events, &"hazard_hit")[0].tick).is_equal(6 * SimWorld.HZ)
	var inside: SimWorld = _world([shell], Vector3(0.0, 0.0, -400.0))
	assert_int(SimFixture.of_kind(SimFixture.run(inside, 600), &"hazard_hit").size()).is_equal(0)
	var away: HazardDef = _plane(Vector3(0.0, 0.0, 600.0), 100.0)
	assert_int(SimFixture.of_kind(SimFixture.run(_world([away]), 600), &"hazard_hit").size()).is_equal(0)


# FT: FT-RLY-001
# A front hits the named subsystems, and a hardened one takes less (FT-ENG-008).
func test_front_hits_named_subsystems_and_hardening_applies() -> void:
	var h: HazardDef = _plane(Vector3(0.0, 0.0, -100.0), 100.0)
	h.targets = [&"sensors", &"shields"]
	var plain: SimWorld = _world([h])
	SimFixture.run(plain, 2 * SimWorld.HZ)
	var hard: SimWorld = _world([h])
	var c: HardenCommand = HardenCommand.new()
	c.ship_id = 0
	c.subsystem_id = &"sensors"
	hard.submit(c)
	SimFixture.run(hard, 2 * SimWorld.HZ)
	var row: int = plain.damage.find_subsystem(0, &"sensors")
	assert_float(plain.damage.health[row]).is_less(hard.damage.health[row])
	var shields: int = plain.damage.find_subsystem(0, &"shields")
	assert_float(plain.damage.health[shields]).is_less(
		TestDefs.corvette().subsystems[SimFixture.sub_index(plain, 0, &"shields")].health_max
	)


# FT: FT-RLY-001, FT-RLY-004
# Sensors know a hazard within detect_range of its surface; a deployed probe's bubble knows
# it from further; the other faction knows neither; a front is unknown before it sets off.
func test_knowledge_by_sensors_and_probes() -> void:
	var h: HazardDef = _zone(Vector3(0.0, 0.0, -4000.0), 1000.0)
	h.detect_range = 1500.0
	var w: SimWorld = _world([h])
	# The surface is 3 km out: out of the sensors' reach.
	assert_bool(HazardSystem.known_to(w, 1, 0)).is_false()
	var launch: LaunchProbeCommand = LaunchProbeCommand.new()
	launch.ship_id = 0
	launch.z = -2000.0
	w.submit(launch)
	SimFixture.run(w, 5 * SimWorld.HZ)
	assert_int(w.probes.deployed[0]).is_equal(1)
	assert_bool(HazardSystem.known_to(w, 1, 0)).is_true()
	assert_bool(HazardSystem.known_to(w, 2, 0)).is_false()
	var near: SimWorld = _world([h], Vector3(0.0, 0.0, -2600.0))
	assert_bool(HazardSystem.known_to(near, 1, 0)).is_true()
	var late: HazardDef = _plane(Vector3(0.0, 0.0, -100.0), 10.0)
	late.detect_range = 5000.0
	late.start_s = 5.0
	assert_bool(HazardSystem.known_to(_world([late]), 1, 0)).is_false()


# FT: FT-RLY-001, FT-ENG-008
# The arrival forecast: a front 12 km out at 200 m/s is 60 s away; a ship flying into it
# shortens that; a zone ahead counts to its edge; one behind the ship is not coming.
func test_eta() -> void:
	var front: HazardDef = _plane(Vector3(0.0, 0.0, -12000.0), 200.0)
	var w: SimWorld = _world([front])
	assert_float(HazardSystem.eta(w, 0, 0)).is_equal_approx(60.0, 1e-3)
	w.kin.vel[0] = Vector3(0.0, 0.0, -100.0)
	assert_float(HazardSystem.eta(w, 0, 0)).is_equal_approx(40.0, 1e-3)
	var ahead: SimWorld = _world([_zone(Vector3(0.0, 0.0, -3000.0), 1000.0)])
	ahead.kin.vel[0] = Vector3(0.0, 0.0, -100.0)
	assert_float(HazardSystem.eta(ahead, 0, 0)).is_equal_approx(20.0, 1e-3)
	ahead.kin.vel[0] = Vector3(0.0, 0.0, 100.0)
	assert_float(HazardSystem.eta(ahead, 0, 0)).is_equal(-1.0)


# FT: FT-ARC-008
# Hazards are in the hash through the fronts that crossed, and a run repeats: the same world
# stepped twice agrees.
func test_hazard_state_is_hashed_and_deterministic() -> void:
	var h: Array[HazardDef] = [_plane(Vector3(0.0, 0.0, -100.0), 100.0)]
	var a: SimWorld = _world(h)
	var b: SimWorld = _world(h)
	var before: String = a.state_hash()
	SimFixture.run(a, 3 * SimWorld.HZ)
	SimFixture.run(b, 3 * SimWorld.HZ)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_int(a.hazard_state.crossed[0]).is_equal(1)
	assert_str(a.state_hash()).is_not_equal(before)
