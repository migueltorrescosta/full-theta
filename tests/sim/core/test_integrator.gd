extends GdUnitTestSuite
## T027: the 6DOF integrator against analytic results (FT-TST-007).

const DT: float = 1.0 / 60.0


func _table(def: ShipDef = TestDefs.corvette()) -> Kinematics:
	var kin: Kinematics = Kinematics.new()
	kin.add_ship(0, 0, def)
	return kin


# FT: FT-SIM-038, FT-SIM-001, FT-TST-007
# Constant thrust from rest: x = a t^2 / 2 after 600 ticks. The update
# x += v dt + a dt^2 / 2 is exact; what is left is float32 rounding of the velocity,
# at most one ulp (2^-23 relative) per tick, so 600 ticks allow 600 * 2^-23 = 7.2e-5
# relative. Position is 64-bit (D104).
func test_constant_thrust_matches_analytic() -> void:
	var kin: Kinematics = _table()
	kin.force_cmd[0] = Vector3(0.0, 0.0, -5.0e5)
	for i: int in 600:
		Integrator.step(kin, 0, DT)
	var a: float = 5.0e5 / kin.mass[0]
	var t: float = 600 * DT
	var expected: float = 0.5 * a * t * t
	var tolerance: float = 600.0 * pow(2.0, -23.0)
	assert_float(-kin.pz[0]).is_equal_approx(expected, expected * tolerance)
	assert_float(-kin.vel[0].z).is_equal_approx(a * t, a * t * tolerance)
	assert_float(kin.px[0]).is_equal(0.0)
	assert_float(kin.py[0]).is_equal(0.0)


# FT: FT-SIM-003, FT-TST-007
# Zero input holds linear and angular velocity (about a principal axis) and spends no
# propellant.
func test_zero_input_holds_velocity() -> void:
	var kin: Kinematics = _table()
	kin.vel[0] = Vector3(10.0, -3.0, 40.0)
	kin.set_angular_velocity(0, Vector3(0.0, 0.0, 0.4))
	var fuel: float = kin.propellant[0]
	for i: int in 600:
		Integrator.step(kin, 0, DT)
	assert_vector(kin.vel[0]).is_equal(Vector3(10.0, -3.0, 40.0))
	assert_float(kin.ang_vel[0].z).is_equal_approx(0.4, 1e-6)
	assert_float(kin.propellant[0]).is_equal(fuel)
	assert_float(kin.px[0]).is_equal_approx(10.0 * 10.0, 1e-4)


# FT: FT-TST-007, FT-SIM-001
# Momentum: with no force the linear momentum is exactly kept; with no torque the
# world-frame angular momentum state is never touched, and the body rate derived from it
# gives back the same L up to float32 rounding of the rotations (measured 1.3e-7 after 600
# ticks; 1e-5 is about 80 float32 ulps). The old explicit Euler step drifted 3.2e-3.
func test_momentum_conserved() -> void:
	var kin: Kinematics = _table()
	kin.vel[0] = Vector3(5.0, 6.0, -7.0)
	kin.set_angular_velocity(0, Vector3(0.3, 0.2, 0.5))
	var p0: Vector3 = kin.vel[0] * kin.mass[0]
	var l0: Vector3 = kin.ang_mom[0]
	for i: int in 600:
		Integrator.step(kin, 0, DT)
	assert_vector(kin.vel[0] * kin.mass[0]).is_equal(p0)
	assert_vector(kin.ang_mom[0]).is_equal(l0)
	var l1: Vector3 = kin.rot[0] * (kin.inertia[0] * kin.ang_vel[0])
	assert_float((l1 - l0).length() / l0.length()).is_less(1e-5)


# FT: FT-ARC-007, FT-SIM-001
# Property test over seeded random tumbles, 36,000 ticks (10 min at 60 Hz) with no
# input: quaternions stay unit and rotational energy stays within 1 % of the start.
# The splitting keeps the energy error O(dt^2) and oscillating, not growing (measured
# 6.3e-5 at worst); 1 % leaves room for float32 rounding while still catching the
# explicit Euler drift this replaced (+9 % to +185 % over the same run).
func test_property_unit_quaternion_bounded_energy() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 27
	for case: int in 20:
		var kin: Kinematics = _table()
		var axis: Vector3 = Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5)
		kin.rot[0] = Quaternion(axis.normalized(), rng.randf() * TAU)
		kin.set_angular_velocity(
			0, Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		)
		var e0: float = _energy(kin)
		for i: int in 36000:
			Integrator.step(kin, 0, DT)
			if i % 100 == 0:
				assert_float(kin.rot[0].length()).is_equal_approx(1.0, 1e-6)
				assert_float(_energy(kin)).is_between(e0 * 0.99, e0 * 1.01)


# FT: FT-SIM-007
# Propellant spent equals impulse over exhaust velocity, torque counted over the lever.
func test_propellant_proportional_to_impulse() -> void:
	var kin: Kinematics = _table()
	kin.force_cmd[0] = Vector3(1.0e5, 0.0, -2.0e5)
	kin.torque_cmd[0] = Vector3(0.0, 1.0e5, 0.0)
	for i: int in 60:
		Integrator.step(kin, 0, DT)
	var effort: float = 1.0e5 + 2.0e5 + 1.0e5 / kin.lever_arm[0]
	var expected: float = effort * 1.0 / kin.exhaust_velocity[0]
	assert_float(kin.propellant_used[0]).is_equal_approx(expected, expected * 1e-9)


# FT: FT-SIM-006
# Commands are clamped to the definition's limits times the current envelope scale.
func test_envelope_clamps_thrust() -> void:
	var kin: Kinematics = _table()
	kin.thrust_scale[0] = 0.5
	kin.force_cmd[0] = Vector3(0.0, 0.0, -1.0e9)
	Integrator.step(kin, 0, DT)
	var a: float = 0.5 * kin.max_thrust_neg[0].z / kin.mass[0]
	assert_float(-kin.vel[0].z).is_equal_approx(a * DT, 1e-6)


func _energy(kin: Kinematics) -> float:
	var w: Vector3 = kin.ang_vel[0]
	return 0.5 * w.dot(kin.inertia[0] * w)
