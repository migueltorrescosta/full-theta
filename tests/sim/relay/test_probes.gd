extends GdUnitTestSuite
## E02: probes, their coverage bubbles, Engineering's fabrication and the firing-lane
## warning (L1/L2). M1 corvette: 3 probes, 500 m/s, 8 km bubble, 4 parts and 30 s each.

const RAIDER_AT: float = -6000.0


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(TestDefs.corvette(), 1, Vector3.ZERO)
	return w


func _launch(w: SimWorld, to: Vector3) -> LaunchProbeCommand:
	var c: LaunchProbeCommand = LaunchProbeCommand.new()
	c.ship_id = 0
	c.x = to.x
	c.y = to.y
	c.z = to.z
	w.submit(c)
	return c


func _steps(w: SimWorld, n: int) -> Array[SimEvent]:
	return SimFixture.run(w, n)


# FT: FT-RLY-004
# A probe flies to the chosen point at the ship's probe speed, deploys there and covers
# its faction's bubble from then on; the stock is finite.
func test_launch_flight_deploy_and_coverage() -> void:
	var w: SimWorld = _world()
	assert_int(w.relay.stock[0]).is_equal(3)
	var c: LaunchProbeCommand = _launch(w, Vector3(0, 0, -5000))
	var events: Array[SimEvent] = _steps(w, 1)
	assert_bool(c.accepted).is_true()
	assert_int(w.relay.stock[0]).is_equal(2)
	assert_int(SimFixture.of_kind(events, &"probe_launched").size()).is_equal(1)
	assert_int(w.probes.size()).is_equal(1)
	# Flying: no bubble yet.
	assert_bool(ProbeSystem.coverage_at(w, 1, Vector3(0, 0, -5000))).is_false()
	# 5 km at 500 m/s is 10 s.
	events = _steps(w, 60 * 10 + 2)
	assert_int(w.probes.deployed[0]).is_equal(1)
	assert_int(SimFixture.of_kind(events, &"probe_deployed").size()).is_equal(1)
	assert_float(w.probes.at_z[0]).is_equal_approx(-5000.0, 0.01)
	assert_bool(ProbeSystem.coverage_at(w, 1, Vector3(0, 0, -5000 - 7900))).is_true()
	assert_bool(ProbeSystem.coverage_at(w, 1, Vector3(0, 0, -5000 - 8100))).is_false()
	# Per faction: the other side has no coverage.
	assert_bool(ProbeSystem.coverage_at(w, 2, Vector3(0, 0, -5000))).is_false()
	# Three launches, then the stock is empty and the fourth is refused.
	_launch(w, Vector3(100, 0, 0))
	_launch(w, Vector3(200, 0, 0))
	var fourth: LaunchProbeCommand = _launch(w, Vector3(300, 0, 0))
	events = _steps(w, 1)
	assert_int(w.relay.stock[0]).is_equal(0)
	assert_bool(fourth.accepted).is_false()
	assert_int(SimFixture.of_kind(events, &"probe_no_stock").size()).is_equal(1)
	assert_int(w.probes.size()).is_equal(3)
	assert_int(w.probes.serial[2]).is_equal(2)


# FT: FT-RLY-004, FT-SIM-035
# Space wraps: a bubble reaches across the seam by the minimum image.
func test_coverage_wraps_across_the_seam() -> void:
	var w: SimWorld = _world()
	var half: float = w.kin.period / 2.0
	_launch(w, Vector3(0, 0, half - 1000.0))
	_steps(w, 60 * 410)
	assert_int(w.probes.deployed[0]).is_equal(1)
	# 3 km past the seam is 4 km from the probe.
	assert_bool(ProbeSystem.coverage_at(w, 1, Vector3(0, 0, -half + 3000.0))).is_true()
	assert_bool(ProbeSystem.coverage_at(w, 1, Vector3(0, 0, -half + 12000.0))).is_false()


# FT: FT-RLY-004
# A run reset of the ship drops its probes and restores the stock; the state hash covers
# probes and stock.
func test_reset_drops_probes_and_hash_covers_them() -> void:
	var w: SimWorld = _world()
	var before: String = w.state_hash()
	_launch(w, Vector3(0, 0, -1000))
	_steps(w, 2)
	assert_str(w.state_hash()).is_not_equal(before)
	w.reset_ship(0)
	assert_int(w.probes.size()).is_equal(0)
	assert_int(w.relay.stock[0]).is_equal(3)
	var copy: SimWorld = SimCopy.of(w)
	assert_str(copy.state_hash()).is_equal(w.state_hash())


# FT: FT-RLY-004
# Engineering fabricates a probe from spare parts: the parts go at once, the probe joins
# the stock after the build time, and a second build waits for the first.
func test_fabrication_takes_parts_and_adds_one_probe() -> void:
	var w: SimWorld = _world()
	var hull: int = w.damage.hull_row(0)
	var parts: int = w.damage.spare_parts[hull]
	var c: FabricateProbeCommand = FabricateProbeCommand.new()
	c.ship_id = 0
	w.submit(c)
	var again: FabricateProbeCommand = FabricateProbeCommand.new()
	again.ship_id = 0
	w.submit(again)
	_steps(w, 1)
	assert_bool(c.accepted).is_true()
	assert_bool(again.accepted).is_false()
	assert_int(w.damage.spare_parts[hull]).is_equal(parts - 4)
	assert_int(w.relay.stock[0]).is_equal(3)
	var events: Array[SimEvent] = _steps(w, 60 * 30 + 2)
	assert_int(w.relay.stock[0]).is_equal(4)
	assert_int(SimFixture.of_kind(events, &"probe_fabricated").size()).is_equal(1)
	# Short of parts: refused with its event.
	w.damage.spare_parts[hull] = 3
	var poor: FabricateProbeCommand = FabricateProbeCommand.new()
	poor.ship_id = 0
	w.submit(poor)
	events = _steps(w, 1)
	assert_bool(poor.accepted).is_false()
	assert_int(SimFixture.of_kind(events, &"probe_no_parts").size()).is_equal(1)
	assert_int(w.damage.spare_parts[hull]).is_equal(3)


func _lane_world(flag: bool) -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(TestDefs.corvette(), 1, Vector3.ZERO)
	# A friendly dead ahead on the bow mount's line, and the hostile beyond it.
	w.spawn_ship(TestDefs.corvette(), 1, Vector3(0, 0, RAIDER_AT / 3.0))
	w.spawn_ship(TestDefs.raider(), 2, Vector3(0, 0, RAIDER_AT))
	if flag:
		var f: FlagLanesCommand = FlagLanesCommand.new()
		f.ship_id = 0
		w.submit(f)
	return w


# FT: FT-RLY-011
# With lanes flagged, the warning comes before the shot, once per crossing; unflagged
# there is none from the lane system (the shot's own warning is FT-SIM-016).
func test_flagged_lane_warns_before_the_shot_once() -> void:
	var w: SimWorld = _lane_world(true)
	var events: Array[SimEvent] = _steps(w, 30)
	var warned: Array[SimEvent] = SimFixture.of_kind(events, &"lane_warning")
	assert_int(warned.size()).is_equal(1)
	assert_int(warned[0].ship_id).is_equal(0)
	assert_int(warned[0].other_id).is_equal(1)
	assert_int(SimFixture.of_kind(events, &"fired").size()).is_equal(0)
	# Still crossing: no second warning. The lane clears and re-crosses: a new one.
	assert_int(SimFixture.of_kind(_steps(w, 30), &"lane_warning").size()).is_equal(0)
	w.kin.place(1, 8000.0, 0.0, 0.0)
	_steps(w, 2)
	assert_int(w.relay.lane_warned[0]).is_equal(-1)
	w.kin.place(1, 0.0, 0.0, RAIDER_AT / 3.0)
	assert_int(SimFixture.of_kind(_steps(w, 2), &"lane_warning").size()).is_equal(1)
	var off: SimWorld = _lane_world(false)
	assert_int(SimFixture.of_kind(_steps(off, 30), &"lane_warning").size()).is_equal(0)
