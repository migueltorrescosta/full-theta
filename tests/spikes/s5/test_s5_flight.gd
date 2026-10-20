extends GdUnitTestSuite
## S5 spike (T012): integrator, assist and the two headless scenarios. Spike-verified,
## so no tags yet; the ids are named here for the promoting M1 issue (#5: T027, T028):
## FT-SIM-001, FT-SIM-003, FT-SIM-004, FT-SIM-005, FT-SIM-007, FT-SIM-036, FT-SIM-037,
## FT-ARC-006.

const DT: float = 1.0 / 60.0


func _run(world: S5World, input: S5HelmInput, ticks: int) -> void:
	for i: int in ticks:
		world.step(input)


# FT-SIM-001, FT-SIM-038: constant thrust from rest gives x = a t^2 / 2; the update
# x += v dt + a dt^2 / 2 is exact, so only float32 rounding is left.
func test_constant_thrust_matches_analytic() -> void:
	var body: S5ShipBody = S5ShipBody.new()
	var force: Vector3 = Vector3(0.0, 0.0, -5.0e5)
	for i: int in 600:
		S5Integrator.step(body, force, Vector3.ZERO, DT)
	var a: float = 5.0e5 / body.mass
	var t: float = 600 * DT
	var expected: float = 0.5 * a * t * t
	assert_float(-body.position.z).is_equal_approx(expected, expected * 1e-6)
	assert_float(-body.velocity.z).is_equal_approx(a * t, 1e-3)


# FT-SIM-003: no input, decoupled: velocity and spin are kept, no propellant used.
func test_zero_input_keeps_motion_and_propellant() -> void:
	var world: S5World = S5World.new()
	world.helm.decoupled = true
	world.ship.velocity = Vector3(10.0, -3.0, 40.0)
	world.ship.angular_velocity = Vector3(0.0, 0.0, 0.4)  # about a principal axis
	var fuel: float = world.ship.propellant
	_run(world, S5HelmInput.new(), 600)
	assert_vector(world.ship.velocity).is_equal_approx(
		Vector3(10.0, -3.0, 40.0), Vector3.ONE * 1e-4
	)
	assert_float(world.ship.angular_velocity.z).is_equal_approx(0.4, 1e-5)
	assert_float(world.ship.propellant).is_equal(fuel)
	assert_float(world.ship.orientation.length()).is_equal_approx(1.0, 1e-5)


# FT-SIM-004: with assist and no input, rotation and drift die out and forward speed
# settles on the throttle setpoint.
func test_assist_holds_rate_drift_and_speed() -> void:
	var world: S5World = S5World.new()
	world.ship.velocity = Vector3(40.0, -25.0, 0.0)
	world.ship.angular_velocity = Vector3(0.3, -0.2, 0.6)
	world.helm.throttle_setpoint = 150.0
	_run(world, S5HelmInput.new(), 60 * 30)
	var v: Vector3 = world.ship.to_local(world.ship.velocity)
	assert_float(world.ship.angular_velocity.length()).is_less(1e-3)
	assert_float(Vector2(v.x, v.y).length()).is_less(0.05)
	assert_float(-v.z).is_equal_approx(150.0, 0.05)


# FT-SIM-004: assist acts only through commands inside the thrust envelope, so the
# ship's velocity changes per tick by at most max thrust / mass * dt on each body axis.
func test_assist_stays_in_envelope() -> void:
	var world: S5World = S5World.new()
	world.ship.velocity = Vector3(300.0, 300.0, 300.0)
	world.ship.angular_velocity = Vector3(2.0, 2.0, 2.0)
	var input: S5HelmInput = S5HelmInput.new()
	input.approach = true
	var ship: S5ShipBody = world.ship
	var up_to: Vector3 = ship.max_thrust_pos / ship.mass * DT
	var down_to: Vector3 = ship.max_thrust_neg / ship.mass * DT
	var slack: float = 1e-3
	for i: int in 120:
		var frame: Quaternion = ship.orientation
		var v_before: Vector3 = ship.velocity
		world.step(input)
		var f: Vector3 = world.last_command.force
		assert_bool(ship.clamp_thrust(f).is_equal_approx(f)).is_true()
		var t: Vector3 = world.last_command.torque
		assert_bool(ship.clamp_torque(t).is_equal_approx(t)).is_true()
		# Thrust acts in the body frame at the start of the tick.
		var dv: Vector3 = frame.inverse() * (ship.velocity - v_before)
		for axis: int in 3:
			assert_float(dv[axis]).is_between(-down_to[axis] - slack, up_to[axis] + slack)


# FT-SIM-005: decoupled turns the holds off; toggling back to assist holds again.
func test_decoupled_disables_assist() -> void:
	var world: S5World = S5World.new()
	var toggle: S5HelmInput = S5HelmInput.new()
	toggle.decoupled_pressed = true
	world.step(toggle)
	assert_bool(world.helm.decoupled).is_true()
	world.ship.velocity = Vector3(30.0, 0.0, 0.0)
	world.ship.angular_velocity = Vector3(0.0, 0.2, 0.0)
	_run(world, S5HelmInput.new(), 120)
	assert_float(world.last_command.force.length()).is_equal(0.0)
	assert_float(world.ship.angular_velocity.y).is_equal_approx(0.2, 1e-5)
	world.step(toggle)
	_run(world, S5HelmInput.new(), 600)
	assert_float(world.ship.angular_velocity.length()).is_less(1e-3)


# FT-SIM-007: propellant use is proportional to impulse.
func test_propellant_proportional_to_impulse() -> void:
	var body: S5ShipBody = S5ShipBody.new()
	var used: float = 0.0
	for i: int in 60:
		used += S5Integrator.step(body, Vector3(0.0, 0.0, -4.0e5), Vector3.ZERO, DT)
	assert_float(used).is_equal_approx(4.0e5 / body.exhaust_velocity, 1e-3)


# FT-HLM-005/006: face assist puts the bow on the target, in decoupled mode too.
func test_face_assist_points_at_item() -> void:
	for decoupled: bool in [false, true]:
		var world: S5World = S5World.new()
		world.helm.decoupled = decoupled
		world.helm.selected = S5World.MARK
		var input: S5HelmInput = S5HelmInput.new()
		input.face = true
		_run(world, input, 60 * 10)
		var to_mark: Vector3 = world.items[S5World.MARK].position - world.ship.position
		var err: float = rad_to_deg(world.ship.forward().angle_to(to_mark))
		assert_float(err).is_less(0.5)


# FT-HLM-007: Level rolls first; a second press also pitches onto the ecliptic.
func test_level_rolls_then_pitches() -> void:
	var world: S5World = S5World.new()
	world.ship.orientation = (
		Quaternion(Vector3.RIGHT, deg_to_rad(30.0)) * Quaternion(Vector3.FORWARD, deg_to_rad(70.0))
	)
	var press: S5HelmInput = S5HelmInput.new()
	press.level_pressed = true
	world.step(press)
	_run(world, S5HelmInput.new(), 60 * 6)
	assert_float(rad_to_deg(absf(S5Assist.roll_error(world.ship)))).is_less(0.5)
	assert_float(rad_to_deg(asin(world.ship.forward().y))).is_greater(20.0)
	world.step(press)
	_run(world, S5HelmInput.new(), 60 * 6)
	assert_float(rad_to_deg(absf(asin(world.ship.forward().y)))).is_less(0.5)
	assert_float(world.ship.up().y).is_greater(0.999)


# FT-HLM-007: with the bow within 0.06° of straight up there is no heading to keep;
# Level still pitches down onto the ecliptic and clears.
func test_level_from_bow_vertical() -> void:
	for pitch_deg: float in [89.97, 90.0, -90.0]:
		var world: S5World = S5World.new()
		world.ship.orientation = Quaternion(Vector3.RIGHT, deg_to_rad(pitch_deg))
		var press: S5HelmInput = S5HelmInput.new()
		press.level_pressed = true
		world.step(press)
		assert_int(world.helm.level).is_equal(S5HelmState.Level.ROLL_AND_PITCH)
		_run(world, S5HelmInput.new(), 60 * 10)
		var msg: String = str(pitch_deg)
		var pitch: float = rad_to_deg(absf(asin(world.ship.forward().y)))
		assert_float(pitch).override_failure_message(msg).is_less(0.5)
		assert_int(world.helm.level).override_failure_message(msg).is_equal(S5HelmState.Level.OFF)


# T012 criterion: the scripted autopilot, with assist, intercepts the moving target
# within 60 s of sim time from three starting states.
func test_autopilot_intercepts_within_60_s() -> void:
	for c: Array in S5Scenarios.intercept_cases():
		var r: Dictionary = S5Scenarios.intercept(c[1], c[2])
		assert_bool(r.captured).override_failure_message("%s: %s" % [c[0], r]).is_true()
		assert_float(r.time).is_less(S5Scenarios.INTERCEPT_LIMIT)


# FT-SIM-036, FT-SIM-037 (NAV-3): all-stop brings a tumbling ship to rest, then
# hold-to-approach stops it at rest within 1 km of the Bravo mark.
func test_all_stop_then_approach_stops_near_mark() -> void:
	var r: Dictionary = S5Scenarios.stop_then_approach(90.0)
	assert_float(r.stop_speed).is_less(S5World.STOP_SPEED)
	assert_float(r.stop_time).is_less(30.0)
	assert_float(r.approach_settled).is_greater(0.0)
	assert_float(r.distance).is_less(1000.0)
	assert_float(r.speed).is_less(0.5)
	assert_float(r.rate).is_less(0.01)


# FT-ARC-006: the accumulator yields whole 60 Hz ticks and keeps the remainder.
func test_fixed_step_accumulator() -> void:
	var fs: S5FixedStep = S5FixedStep.new()
	var total: int = 0
	for i: int in 144:
		total += fs.advance(1.0 / 144.0)
	assert_int(total).is_between(59, 60)
	assert_int(fs.advance(1.0)).is_equal(fs.max_ticks)
