extends GdUnitTestSuite
## T028: flight assist holds, envelope, decoupled mode and propellant (L2: a SimWorld
## driven through Helm commands).


## Start states [name, velocity, angular velocity, throttle setpoint, rotation].
func _hold_cases() -> Array[Array]:
	return [
		[
			"drift and spin",
			Vector3(40.0, -25.0, 0.0),
			Vector3(0.3, -0.2, 0.6),
			150.0,
			Quaternion.IDENTITY
		],
		[
			"astern, yawed",
			Vector3(0.0, 0.0, 80.0),
			Vector3(0.0, 0.5, 0.0),
			-30.0,
			Quaternion(Vector3.UP, 1.2),
		],
		["at rest, to full", Vector3.ZERO, Vector3.ZERO, 300.0, Quaternion(Vector3.RIGHT, -0.7)],
	]


# FT: FT-SIM-004
# Table test: assist is on by default and, with no input, brings the angular rate to
# zero, lateral and vertical velocity to zero and forward speed to the setpoint. 30 s
# covers the slowest case (0 to 300 m/s at 20 m/s^2 is 15 s) and the 0.4 s velocity time
# constant settles to well under the tolerances (0.05 m/s, 1e-3 rad/s).
func test_holds_rate_drift_and_speed() -> void:
	for c: Array in _hold_cases():
		var w: SimWorld = SimWorld.new(1, "test")
		var id: int = FlightFixture.spawn(w, Vector3.ZERO, c[4], c[1])
		assert_bool(w.helm.is_decoupled(id)).is_false()
		w.kin.set_angular_velocity(id, c[2])
		w.helm.throttle_setpoint[id] = c[3]
		SimFixture.run(w, 60 * 30)
		var v: Vector3 = FlightFixture.local_velocity(w, id)
		var msg: String = c[0]
		assert_float(w.kin.ang_vel[id].length()).override_failure_message(msg).is_less(1e-3)
		assert_float(Vector2(v.x, v.y).length()).override_failure_message(msg).is_less(0.05)
		assert_float(-v.z).override_failure_message(msg).is_equal_approx(c[3], 0.05)


# FT: FT-SIM-004
# Throttle sets speed, not force: full throttle for 2 s ramps the setpoint by 2 s *
# 60 m/s^2 (speed_ramp) and the ship then holds that speed with the stick released.
func test_throttle_ramps_setpoint() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var id: int = FlightFixture.spawn(w)
	FlightFixture.input(w, id, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	SimFixture.run(w, 120)
	FlightFixture.input(w, id)
	SimFixture.run(w, 60 * 10)
	# Submitted input applies at the start of the next step, so it ramps for 120 ticks.
	var ramp: float = w.defs[id].assist.speed_ramp
	assert_float(w.helm.throttle_setpoint[id]).is_equal_approx(ramp * 2.0, 1e-6)
	assert_float(-FlightFixture.local_velocity(w, id).z).is_equal_approx(
		w.helm.throttle_setpoint[id], 0.05
	)


# FT: FT-SIM-004
# Strafe input fires that axis while the other holds stay on; releasing it holds the
# drift back to zero.
func test_strafe_input_overrides_its_hold_only() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var id: int = FlightFixture.spawn(w)
	FlightFixture.input(w, id, Vector3.ZERO, Vector3(1.0, 0.0, 0.0))
	SimFixture.run(w, 61)
	assert_float(w.kin.force_cmd[id].x).is_equal(w.kin.thrust_limit(id, true).x)
	assert_float(FlightFixture.local_velocity(w, id).x).is_greater(10.0)
	FlightFixture.input(w, id)
	SimFixture.run(w, 60 * 10)
	assert_float(FlightFixture.local_velocity(w, id).length()).is_less(0.05)


# FT: FT-SIM-006
# P1: Helm's turn rate follows Engineering's thruster pips. With full yaw input the
# assist holds the AssistDef cap (40 deg/s) times the torque envelope share: 1 at
# nominal, 1.5 during a boost (thrusters at 4 pips), so the boosted 90 deg turn takes
# about (pi/2) / (1.5 cap) instead of (pi/2) / cap. Tolerance 1% on the held rate (the
# 0.12 s rate hold settles from below); each turn is bounded by a 10 s tick limit.
func test_turn_rate_cap_follows_torque_envelope() -> void:
	var ticks: Array[int] = []
	for boost: bool in [false, true]:
		var w: SimWorld = SimWorld.new(1, "test")
		var id: int = FlightFixture.spawn(w)
		if boost:
			var b: BoostCommand = BoostCommand.new()
			b.ship_id = id
			w.submit(b)
		FlightFixture.input(w, id, Vector3(0, 1, 0))
		var peak: float = 0.0
		while Vector3.FORWARD.angle_to(w.kin.forward(id)) < PI / 2 and w.tick < 600:
			w.step()
			peak = maxf(peak, w.kin.ang_vel[id].y)
		var msg: String = "boost %s" % boost
		assert_int(w.tick).override_failure_message(msg).is_less(600)
		var scale: float = 1.5 if boost else 1.0
		assert_float(w.kin.torque_scale[id]).override_failure_message(msg).is_equal(scale)
		var cap: float = w.defs[id].assist.turn_rate_pitch_yaw * scale
		assert_float(peak).override_failure_message(msg).is_between(0.99 * cap, cap * 1.001)
		ticks.append(w.tick)
	assert_int(ticks[1]).is_less(ticks[0] * 4 / 5)


# FT: FT-SIM-004, FT-SIM-006
# Every mode commands force and torque inside the current envelope (here halved), and
# each tick's body-frame velocity change stays within limit / mass * dt per axis. The
# envelope is read after each step, so it is the one the tick used even once power
# writes it. Slack 1e-3 m/s covers float32 rounding of a ~300 m/s velocity.
# Per-axis clamping bends the commanded direction when several axes saturate (S5).
func test_every_mode_stays_in_envelope() -> void:
	for mode: String in ["holds", "stick", "decoupled", "all_stop", "face", "approach"]:
		var w: SimWorld = SimWorld.new(1, "test")
		var id: int = FlightFixture.spawn(w, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE * 300.0)
		w.kin.set_angular_velocity(id, Vector3(2.0, 2.0, 2.0))
		w.kin.thrust_scale[id] = 0.5
		w.kin.torque_scale[id] = 0.5
		FlightFixture.select_point(w, id, 0, Vector3(-3000.0, 2000.0, 5000.0))
		match mode:
			"stick":
				FlightFixture.input(w, id, Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0))
			"decoupled":
				FlightFixture.decouple(w, id, true)
				FlightFixture.input(w, id, Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0))
			"all_stop":
				FlightFixture.all_stop(w, id)
			"face":
				FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, true)
			"approach":
				FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, false, true)
		for i: int in 240:
			var frame: Quaternion = w.kin.rot[id]
			var v_before: Vector3 = w.kin.vel[id]
			w.step()
			var f: Vector3 = w.kin.force_cmd[id]
			var tq: Vector3 = w.kin.torque_cmd[id]
			(
				assert_bool(w.kin.clamp_thrust(id, f).is_equal_approx(f))
				. override_failure_message(mode)
				. is_true()
			)
			(
				assert_bool(w.kin.clamp_torque(id, tq).is_equal_approx(tq))
				. override_failure_message(mode)
				. is_true()
			)
			var dv: Vector3 = frame.inverse() * (w.kin.vel[id] - v_before)
			var up_to: Vector3 = w.kin.thrust_limit(id, true) / w.kin.mass[id] * SimWorld.DT
			var down_to: Vector3 = w.kin.thrust_limit(id, false) / w.kin.mass[id] * SimWorld.DT
			for axis: int in 3:
				(
					assert_float(dv[axis])
					. override_failure_message("%s tick %d axis %d" % [mode, i, axis])
					. is_between(-down_to[axis] - 1e-3, up_to[axis] + 1e-3)
				)


# FT: FT-SIM-005, FT-SIM-003
# Decoupled turns the holds off: with zero input the ship keeps its velocity and spin
# (about a principal axis), commands nothing and spends nothing. Back to assist, the
# setpoint becomes the current forward speed and the holds come back.
func test_decoupled_disables_assist() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var id: int = FlightFixture.spawn(
		w, Vector3.ZERO, Quaternion.IDENTITY, Vector3(30.0, 0.0, -50.0)
	)
	w.kin.set_angular_velocity(id, Vector3(0.0, 0.2, 0.0))
	FlightFixture.decouple(w, id, true)
	SimFixture.run(w, 120)
	assert_bool(w.helm.is_decoupled(id)).is_true()
	assert_vector(w.kin.force_cmd[id]).is_equal(Vector3.ZERO)
	assert_vector(w.kin.torque_cmd[id]).is_equal(Vector3.ZERO)
	assert_vector(w.kin.vel[id]).is_equal(Vector3(30.0, 0.0, -50.0))
	assert_float(w.kin.ang_vel[id].y).is_equal_approx(0.2, 1e-6)
	assert_float(w.kin.propellant_used[id]).is_equal(0.0)
	var fwd: float = w.kin.vel[id].dot(w.kin.forward(id))
	FlightFixture.decouple(w, id, false)
	w.step()
	assert_float(w.helm.throttle_setpoint[id]).is_equal_approx(fwd, 1e-3)
	SimFixture.run(w, 600)
	assert_float(w.kin.ang_vel[id].length()).is_less(1e-3)
	var v: Vector3 = FlightFixture.local_velocity(w, id)
	assert_float(Vector2(v.x, v.y).length()).is_less(0.05)


# FT: FT-SIM-005
# Decoupled, the stick maps straight to thrust and torque at the envelope's limits.
func test_decoupled_stick_maps_to_thrust() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var id: int = FlightFixture.spawn(w)
	FlightFixture.decouple(w, id, true)
	FlightFixture.input(w, id, Vector3(1.0, -0.5, 0.0), Vector3(0.0, -1.0, 1.0))
	w.step()
	var tq_lim: Vector3 = w.kin.torque_limit(id)
	assert_vector(w.kin.torque_cmd[id]).is_equal(Vector3(tq_lim.x, -0.5 * tq_lim.y, 0.0))
	var neg: Vector3 = w.kin.thrust_limit(id, false)
	assert_vector(w.kin.force_cmd[id]).is_equal(Vector3(0.0, -neg.y, -neg.z))


# FT: FT-SIM-007
# Propellant is impulse over exhaust velocity: full main drive for 1 s through assist
# (decoupled) spends 1 MN s / 60 km/s.
func test_assist_propellant_proportional_to_impulse() -> void:
	var d: SimWorld = SimWorld.new(1, "test")
	var s: int = FlightFixture.spawn(d)
	FlightFixture.decouple(d, s, true)
	FlightFixture.input(d, s, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	SimFixture.run(d, 60)
	var impulse: float = d.kin.thrust_limit(s, false).z * 60.0 * SimWorld.DT
	assert_float(d.kin.propellant_used[s]).is_equal_approx(
		impulse / d.kin.exhaust_velocity[s], 1e-6
	)


# FT: FT-SIM-007, FT-SIM-004
# Coasting costs nothing: with assist on and nothing to correct (at rest, or at the
# setpoint speed) the holds command exactly zero, as does a decoupled coast.
func test_coasting_consumes_no_propellant() -> void:
	var w: SimWorld = SimWorld.new(1, "test")
	var rest: int = FlightFixture.spawn(w)
	var cruise: int = FlightFixture.spawn(
		w, Vector3(0.0, 0.0, 5000.0), Quaternion.IDENTITY, Vector3(0.0, 0.0, -100.0)
	)
	w.helm.throttle_setpoint[cruise] = 100.0
	var drift: int = FlightFixture.spawn(
		w, Vector3(5000.0, 0.0, 0.0), Quaternion.IDENTITY, Vector3(7.0, -3.0, 2.0)
	)
	FlightFixture.decouple(w, drift, true)
	SimFixture.run(w, 600)
	for id: int in [rest, cruise, drift]:
		assert_float(w.kin.propellant_used[id]).override_failure_message(str(id)).is_equal(0.0)
	assert_float(w.kin.pz[cruise]).is_equal_approx(4000.0, 1e-6)
