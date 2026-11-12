extends GdUnitTestSuite
## R09-15: jump edge conditions (FT-SIM-034, FT-SIM-035) on the M3 map.


# FT: FT-SIM-034
# A ship tumbling when the spool ends arrives at the stand-off with linear velocity zero.
# Pinned current behaviour: JumpSystem._arrive resets only velocity, force_cmd and the
# throttle setpoint, so the angular velocity the integrator derived is kept (not zeroed).
func test_arrival_zeroes_velocity_and_keeps_the_spin() -> void:
	var w: SimWorld = SiteFixture.world()
	var mark: PackedFloat64Array = CubePoint.make(0.0, 0.0, -60000.0)
	var ship: int = SiteFixture.corvette_facing(w, CubePoint.make(), mark)
	SiteFixture.jump_to_mark(w, ship, mark)
	w.step()
	while w.helm.jump_left[ship] > 1:
		w.step()
	w.kin.set_angular_velocity(ship, Vector3(0.0, 0.3, 0.0))
	w.kin.vel[ship] = Vector3(5.0, 0.0, 0.0)
	w.step()
	assert_int(w.helm.jump_left[ship]).is_equal(0)
	assert_float(w.kin.relative_to_point(ship, mark).length()).is_equal_approx(
		TestDefs.corvette().jump_standoff, 0.5
	)
	assert_float(w.kin.vel[ship].length()).is_equal(0.0)
	assert_float(w.kin.ang_vel[ship].length()).is_greater(0.1)


# FT: FT-SIM-034
# A target within 1 m is refused: no spool, no propellant.
func test_target_within_one_metre_is_refused() -> void:
	var w: SimWorld = SiteFixture.world()
	var near: PackedFloat64Array = CubePoint.make(0.0, 0.0, -0.5)
	var ship: int = SiteFixture.corvette_facing(w, CubePoint.make(), CubePoint.make(0, 0, -100))
	var fuel: float = w.kin.propellant[ship]
	var c: JumpCommand = SiteFixture.jump_to_mark(w, ship, near)
	w.step()
	assert_bool(c.accepted).is_false()
	assert_int(w.helm.jump_left[ship]).is_equal(0)
	assert_float(w.kin.propellant[ship]).is_equal(fuel)


# FT: FT-SIM-034, FT-SIM-035
# A non-finite mark (NaN or infinity in any axis) is refused with nothing spent.
func test_non_finite_mark_is_refused() -> void:
	var w: SimWorld = SiteFixture.world()
	var ship: int = SiteFixture.corvette_facing(w, CubePoint.make(), CubePoint.make(0, 0, -100))
	var fuel: float = w.kin.propellant[ship]
	var cmds: Array[JumpCommand] = [
		SiteFixture.jump_to_mark(w, ship, CubePoint.make(INF, 0.0, 0.0)),
		SiteFixture.jump_to_mark(w, ship, CubePoint.make(0.0, NAN, 0.0)),
		SiteFixture.jump_to_mark(w, ship, CubePoint.make(0.0, 0.0, -INF)),
	]
	w.step()
	for c: JumpCommand in cmds:
		assert_bool(c.accepted).is_false()
	assert_int(w.helm.jump_left[ship]).is_equal(0)
	assert_float(w.kin.propellant[ship]).is_equal(fuel)
