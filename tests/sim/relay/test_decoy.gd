extends GdUnitTestSuite
## gp-13: Relay's decoy. The M1 corvette (faction 1, at the origin, a hull the raider can't
## break) and the M1 raider (faction 2) 2.5 km ahead; the corvette's decoy lasts 20 s, draws
## hostile NPCs within 5 km and flies 3 km out, square to the line to the raider.

const HZ: int = SimWorld.HZ


func _world(with_raider: bool = true) -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	var def: ShipDef = TestDefs.corvette().duplicate()
	def.hull_max = 1e12
	w.spawn_ship(def, 1, CubePoint.make())
	if with_raider:
		w.spawn_npc(TestDefs.raider_enemy(), 2, CubePoint.make(0, 0, -2500))
		# Until the corvette has identified the raider (an H contact).
		for i: int in HZ:
			if ProbeSystem.hostile_in_play(w, 0) >= 0:
				break
			w.step()
		assert_int(ProbeSystem.hostile_in_play(w, 0)).is_equal(1)
	return w


func _decoy(w: SimWorld) -> LaunchDecoyCommand:
	var c: LaunchDecoyCommand = LaunchDecoyCommand.new()
	c.ship_id = 0
	w.submit(c)
	return c


## Distance (m) from the raider's selected face point to a point.
func _face_off(w: SimWorld, at: Vector3) -> float:
	var h: HelmTable = w.helm
	assert_int(h.sel_kind[1]).is_equal(HelmTable.Selection.POINT)
	return Vector3(h.sel_x[1], h.sel_y[1], h.sel_z[1]).distance_to(at)


# FT: FT-RLY-013
# A decoy takes a probe from stock and flies out square to the raider's line; within its
# range the raider turns on it for decoy_time, then the decoy is spent and the raider goes
# back for the ship.
func test_decoy_draws_the_raider_for_its_time_then_reverts() -> void:
	var w: SimWorld = _world()
	var def: ShipDef = w.defs[0]
	var c: LaunchDecoyCommand = _decoy(w)
	var events: Array[SimEvent] = SimFixture.run(w, 1)
	assert_bool(c.accepted).is_true()
	assert_int(w.relay.stock[0]).is_equal(def.probes - 1)
	assert_int(SimFixture.of_kind(events, &"decoy_launched").size()).is_equal(1)
	assert_int(w.probes.size()).is_equal(1)
	assert_float(w.probes.decoy_left[0]).is_equal_approx(def.decoy_time - SimWorld.DT, 1e-6)
	# 3 km at 500 m/s: on station after 6 s, abeam of the raider's line; a decoy on station
	# is no probe on station (it covers nothing).
	events = SimFixture.run(w, 7 * HZ)
	assert_int(SimFixture.of_kind(events, &"probe_deployed").size()).is_equal(0)
	assert_bool(w.probes.covers(0)).is_false()
	var at: Vector3 = Vector3(w.probes.pos_x[0], w.probes.pos_y[0], w.probes.pos_z[0])
	assert_float(at.length()).is_equal_approx(def.decoy_offset, 1.0)
	assert_float(absf(at.z)).is_less(1.0)
	assert_int(ProbeSystem.decoy_near(w, 1)).is_equal(0)
	# The raider faces the decoy, not the corvette, and its target is still the corvette.
	var ship: Vector3 = Vector3.ZERO
	assert_float(_face_off(w, at)).is_less(200.0)
	assert_float(_face_off(w, ship)).is_greater(2000.0)
	assert_int(w.ai.target[1]).is_equal(0)
	# A decoy covers nothing.
	assert_bool(ProbeSystem.coverage_at(w, 1, CubePoint.of(at))).is_false()
	# Spent after 20 s: the row goes and the raider turns back on the corvette.
	events = SimFixture.run(w, 14 * HZ)
	assert_int(SimFixture.of_kind(events, &"decoy_spent").size()).is_equal(1)
	assert_int(w.probes.size()).is_equal(0)
	assert_int(ProbeSystem.decoy_near(w, 1)).is_equal(-1)
	SimFixture.run(w, HZ)
	var to_ship: Vector3 = w.kin.relative(1, 0)
	var face: Vector3 = w.kin.relative_to_column(1, w.helm.sel_x, w.helm.sel_y, w.helm.sel_z, 1)
	assert_float(face.angle_to(to_ship)).is_less(0.2)


# FT: FT-RLY-013
# No probe in stock, no decoy: refused with probe_no_stock; no hostile in play: refused.
func test_decoy_refused_without_a_probe_or_a_hostile() -> void:
	var w: SimWorld = _world()
	w.relay.stock[0] = 0
	assert_bool(ProbeSystem.can_decoy(w, 0)).is_false()
	var c: LaunchDecoyCommand = _decoy(w)
	var events: Array[SimEvent] = SimFixture.run(w, 1)
	assert_bool(c.accepted).is_false()
	assert_int(SimFixture.of_kind(events, &"probe_no_stock").size()).is_equal(1)
	assert_int(w.probes.size()).is_equal(0)
	var calm: SimWorld = _world(false)
	assert_bool(ProbeSystem.can_decoy(calm, 0)).is_false()
	var d: LaunchDecoyCommand = _decoy(calm)
	SimFixture.run(calm, 1)
	assert_bool(d.accepted).is_false()
	assert_int(calm.relay.stock[0]).is_equal(calm.defs[0].probes)


# FT: FT-RLY-013
# Debris is hostile in a debris leg but unarmed: no decoy against rocks.
func test_no_decoy_against_debris() -> void:
	var w: SimWorld = _world(false)
	var rock: int = w.spawn_npc(
		load("res://content/npcs/debris.tres") as NpcDef, 4, CubePoint.make(0, 0, -2500)
	)
	SimFixture.run(w, HZ)
	assert_bool(KnowledgeSystem.is_identified(w, 1, rock)).is_true()
	assert_int(ProbeSystem.hostile_in_play(w, 0)).is_equal(-1)
	assert_bool(ProbeSystem.can_decoy(w, 0)).is_false()
