extends GdUnitTestSuite
## T028: all-stop, hold-to-approach, face and Level (L2: a SimWorld driven through Helm
## commands).


# FT: FT-SIM-036
# All-stop from a tumbling 185 m/s (S5's start): assist brings velocity relative to the
# site and rotation to rest (< 0.05 m/s, < 0.002 rad/s, then it clears itself) through
# real thrust, in under 30 s (S5: 17.6 s), and propellant is spent. It runs decoupled
# too.
func test_all_stop_from_tumble() -> void:
	for decoupled: bool in [false, true]:
		var w: SimWorld = FlightFixture.world()
		var id: int = FlightFixture.spawn(
			w, Vector3.ZERO, Quaternion.IDENTITY, Vector3(90.0, 25.0, -160.0)
		)
		w.kin.ang_vel[id] = Vector3(0.3, -0.2, 0.5)
		w.helm.throttle_setpoint[id] = 180.0
		FlightFixture.decouple(w, id, decoupled)
		FlightFixture.all_stop(w, id)
		w.step()
		assert_int(w.helm.all_stop[id]).is_equal(1)
		assert_float(w.helm.throttle_setpoint[id]).is_equal(0.0)
		var ticks: int = 0
		while w.helm.all_stop[id] == 1 and ticks < 60 * 60:
			w.step()
			ticks += 1
		var msg: String = "decoupled %s" % decoupled
		assert_float(ticks * FlightFixture.DT).override_failure_message(msg).is_less(30.0)
		assert_float(w.kin.vel[id].length()).override_failure_message(msg).is_less(0.05)
		assert_float(w.kin.ang_vel[id].length()).override_failure_message(msg).is_less(0.002)
		assert_float(w.kin.propellant_used[id]).override_failure_message(msg).is_greater(100.0)


# FT: FT-SIM-036
# Manual input ends all-stop at once; Helm has the ship back.
func test_all_stop_ends_on_manual_input() -> void:
	var w: SimWorld = FlightFixture.world()
	var id: int = FlightFixture.spawn(
		w, Vector3.ZERO, Quaternion.IDENTITY, Vector3(0.0, 0.0, -100.0)
	)
	FlightFixture.all_stop(w, id)
	FlightFixture.run(w, 30)
	assert_int(w.helm.all_stop[id]).is_equal(1)
	FlightFixture.input(w, id, Vector3(0.0, 0.5, 0.0))
	w.step()
	assert_int(w.helm.all_stop[id]).is_equal(0)
	assert_float(w.kin.torque_cmd[id].y).is_greater(0.0)


# FT: FT-SIM-037, FT-HLM-006
# Hold-to-approach to a mark 7.2 km away: assist faces it, flies to the 500 m stand-off
# (AssistDef data) and stops there. S5 settles in 60 s; at 90 s the state is within
# 0.05 m of 500 m and 0.01 m/s (the final 4 s time constant has long decayed). Releasing
# returns control: the setpoint becomes the current forward speed and the stick turns
# the ship again.
func test_approach_point_stops_at_standoff() -> void:
	var w: SimWorld = FlightFixture.world()
	var id: int = FlightFixture.spawn(w)
	var mark: Vector3 = Vector3(4000.0, -800.0, -6000.0)
	FlightFixture.select_point(w, id, 0, mark)
	FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, false, true)
	FlightFixture.run(w, 60 * 90)
	var rel: Vector3 = w.kin.relative_to_point(id, mark.x, mark.y, mark.z)
	var standoff: float = w.defs[id].assist.approach_standoff
	assert_float(standoff).is_equal(500.0)
	assert_float(rel.length()).is_equal_approx(standoff, 0.05)
	assert_float(w.kin.vel[id].length()).is_less(0.01)
	assert_float(FlightFixture.bow_error_deg(w, id, rel)).is_less(0.5)
	assert_float(w.kin.propellant_used[id]).is_greater(0.0)
	_assert_release_returns_control(w, id)


# FT: FT-SIM-037
# Hold-to-approach on a ship 5.6 km off flying 114 m/s: assist closes, stops at the
# stand-off and matches its velocity. S5 run: 500.4 m and 0.11 m/s relative at 60 s;
# at 120 s within 0.05 m and 0.01 m/s.
func test_approach_moving_ship_matches_velocity() -> void:
	var w: SimWorld = FlightFixture.world()
	var id: int = FlightFixture.spawn(w)
	var target: int = FlightFixture.spawn(
		w, Vector3(-3000.0, 1500.0, -4500.0), Quaternion.IDENTITY, Vector3(110.0, 0.0, 30.0)
	)
	FlightFixture.decouple(w, target, true)
	FlightFixture.select_ship(w, id, target)
	FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, false, true)
	FlightFixture.run(w, 60 * 120)
	var rel: Vector3 = w.kin.relative(id, target)
	assert_float(rel.length()).is_equal_approx(500.0, 0.05)
	assert_float((w.kin.vel[target] - w.kin.vel[id]).length()).is_less(0.01)
	assert_float(FlightFixture.bow_error_deg(w, id, rel)).is_less(0.5)
	_assert_release_returns_control(w, id)


# FT: FT-HLM-005, FT-HLM-006
# Face turns the bow onto a contact or a mark, with assist and decoupled, at the ship's
# real turn rate: the body rate never passes the AssistDef cap (40 deg/s) and a large
# turn reaches it, so it neither snaps nor crawls. The turn costs propellant.
func test_face_contact_and_mark_in_both_modes() -> void:
	for decoupled: bool in [false, true]:
		for on_ship: bool in [false, true]:
			var w: SimWorld = FlightFixture.world()
			var id: int = FlightFixture.spawn(w)
			var where: Vector3 = Vector3(3000.0, 1200.0, 2500.0)  # behind, up, starboard
			var other: int = FlightFixture.spawn(w, where)
			if on_ship:
				FlightFixture.select_ship(w, id, other)
			else:
				FlightFixture.select_point(w, id, 0, where)
			FlightFixture.decouple(w, id, decoupled)
			FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, true)
			var cap: float = w.defs[id].assist.turn_rate_pitch_yaw
			var peak: float = 0.0
			for i: int in 60 * 10:
				w.step()
				var rate: Vector3 = w.kin.ang_vel[id]
				peak = maxf(peak, Vector2(rate.x, rate.y).length())
			var msg: String = "decoupled %s ship %s" % [decoupled, on_ship]
			var err: float = FlightFixture.bow_error_deg(w, id, w.kin.relative(id, other))
			assert_float(err).override_failure_message(msg).is_less(0.5)
			assert_float(peak).override_failure_message(msg).is_between(0.95 * cap, cap * 1.001)
			assert_float(w.kin.propellant_used[id]).override_failure_message(msg).is_greater(0.0)


# FT: FT-HLM-006
# A target at another site is out of reach (ships at different sites never interact):
# face does nothing and the holds stay on.
func test_face_ignores_other_site() -> void:
	var w: SimWorld = FlightFixture.world()
	var id: int = FlightFixture.spawn(w)
	FlightFixture.select_point(w, id, 7, Vector3(0.0, 0.0, 3000.0))
	FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, true)
	FlightFixture.run(w, 120)
	assert_bool(AssistSystem.has_target(w, id)).is_false()
	assert_vector(w.kin.ang_vel[id]).is_equal(Vector3.ZERO)
	assert_float(w.kin.propellant_used[id]).is_equal(0.0)


# FT: FT-HLM-007
# Level rolls first and keeps the heading (the bow stays 30 deg up); a second press
# also pitches onto the ecliptic. Done within 0.5 deg, then Level clears.
func test_level_rolls_then_pitches() -> void:
	var w: SimWorld = FlightFixture.world()
	var start: Quaternion = (
		Quaternion(Vector3.RIGHT, deg_to_rad(30.0)) * Quaternion(Vector3.FORWARD, deg_to_rad(70.0))
	)
	var id: int = FlightFixture.spawn(w, Vector3.ZERO, start)
	FlightFixture.level(w, id)
	w.step()
	assert_int(w.helm.level[id]).is_equal(HelmTable.Level.ROLL)
	FlightFixture.run(w, 60 * 6)
	assert_float(rad_to_deg(absf(AssistSystem.roll_error(w.kin, id)))).is_less(0.5)
	assert_float(rad_to_deg(asin(w.kin.forward(id).y))).is_equal_approx(30.0, 0.5)
	assert_int(w.helm.level[id]).is_equal(HelmTable.Level.OFF)
	FlightFixture.level(w, id)
	w.step()
	assert_int(w.helm.level[id]).is_equal(HelmTable.Level.ROLL_AND_PITCH)
	FlightFixture.run(w, 60 * 6)
	assert_float(rad_to_deg(absf(asin(w.kin.forward(id).y)))).is_less(0.5)
	assert_float(w.kin.to_world(id, Vector3.UP).y).is_greater(0.9999)
	assert_int(w.helm.level[id]).is_equal(HelmTable.Level.OFF)


# FT: FT-HLM-007
# A second press while still rolling goes straight to roll and pitch; rotation input
# cancels Level. With the bow within 0.03 deg of straight up or down there is no
# heading to keep, and Level still pitches onto the ecliptic.
func test_level_second_press_cancel_and_bow_vertical() -> void:
	var w: SimWorld = FlightFixture.world()
	var id: int = FlightFixture.spawn(w, Vector3.ZERO, Quaternion(Vector3.FORWARD, 1.0))
	FlightFixture.level(w, id)
	FlightFixture.level(w, id)
	w.step()
	assert_int(w.helm.level[id]).is_equal(HelmTable.Level.ROLL_AND_PITCH)
	FlightFixture.input(w, id, Vector3(0.0, 0.0, 0.5))
	w.step()
	assert_int(w.helm.level[id]).is_equal(HelmTable.Level.OFF)
	for pitch_deg: float in [89.97, 90.0, -90.0]:
		var v: SimWorld = FlightFixture.world()
		var s: int = FlightFixture.spawn(
			v, Vector3.ZERO, Quaternion(Vector3.RIGHT, deg_to_rad(pitch_deg))
		)
		FlightFixture.level(v, s)
		v.step()
		var msg: String = str(pitch_deg)
		assert_int(v.helm.level[s]).override_failure_message(msg).is_equal(
			HelmTable.Level.ROLL_AND_PITCH
		)
		FlightFixture.run(v, 60 * 10)
		var pitch: float = rad_to_deg(absf(asin(v.kin.forward(s).y)))
		assert_float(pitch).override_failure_message(msg).is_less(0.5)
		assert_int(v.helm.level[s]).override_failure_message(msg).is_equal(HelmTable.Level.OFF)


# FT: FT-M1-003, FT-SIM-004, FT-SIM-005, FT-SIM-036, FT-SIM-037
# The M1 ship flies 6DOF with assist on by default and its holds, all-stop,
# hold-to-approach and decoupled mode, in one flight through Helm commands.
func test_m1_ship_flight_modes() -> void:
	var w: SimWorld = FlightFixture.world()
	var id: int = FlightFixture.spawn(w)
	assert_bool(w.helm.is_decoupled(id)).is_false()
	# Holds: a turn and a throttle burst, then hands off.
	FlightFixture.input(w, id, Vector3(0.0, 1.0, 0.3), Vector3(0.5, 0.0, 1.0))
	FlightFixture.run(w, 120)
	FlightFixture.input(w, id)
	FlightFixture.run(w, 600)
	var v: Vector3 = FlightFixture.local_velocity(w, id)
	assert_float(w.kin.ang_vel[id].length()).is_less(1e-3)
	assert_float(Vector2(v.x, v.y).length()).is_less(0.05)
	assert_float(-v.z).is_equal_approx(w.helm.throttle_setpoint[id], 0.05)
	assert_float(w.helm.throttle_setpoint[id]).is_greater(100.0)
	# All-stop.
	FlightFixture.all_stop(w, id)
	FlightFixture.run(w, 60 * 30)
	assert_int(w.helm.all_stop[id]).is_equal(0)
	assert_float(w.kin.vel[id].length()).is_less(0.05)
	# Hold-to-approach to a point 3 km off.
	var p: Vector3 = Vector3(w.kin.px[id] + 2000.0, w.kin.py[id], w.kin.pz[id] + 2236.0)
	FlightFixture.select_point(w, id, 0, p)
	FlightFixture.input(w, id, Vector3.ZERO, Vector3.ZERO, false, true)
	FlightFixture.run(w, 60 * 60)
	assert_float(w.kin.relative_to_point(id, p.x, p.y, p.z).length()).is_equal_approx(500.0, 0.5)
	FlightFixture.input(w, id)
	# Decoupled: the ship now keeps whatever it has.
	FlightFixture.decouple(w, id, true)
	FlightFixture.input(w, id, Vector3.ZERO, Vector3(1.0, 0.0, 0.0))
	FlightFixture.run(w, 60)
	FlightFixture.input(w, id)
	w.step()
	var drift: Vector3 = w.kin.vel[id]
	FlightFixture.run(w, 300)
	assert_float(drift.length()).is_greater(10.0)
	assert_vector(w.kin.vel[id]).is_equal(drift)


func _assert_release_returns_control(w: SimWorld, id: int) -> void:
	FlightFixture.input(w, id)
	w.step()
	assert_int(w.helm.approach_held[id]).is_equal(0)
	# The setpoint range clamps it (here a target flying away: astern past -50 m/s).
	var tuning: AssistDef = w.defs[id].assist
	var fwd: float = w.kin.vel[id].dot(w.kin.forward(id))
	fwd = clampf(fwd, tuning.speed_min, tuning.speed_max)
	assert_float(w.helm.throttle_setpoint[id]).is_equal_approx(fwd, 0.01)
	FlightFixture.input(w, id, Vector3(0.0, 1.0, 0.0))
	FlightFixture.run(w, 60)
	assert_float(w.kin.ang_vel[id].y).is_greater(0.5 * w.defs[id].assist.turn_rate_pitch_yaw)
