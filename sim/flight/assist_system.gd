class_name AssistSystem
extends RefCounted
## Flight assist (T028, promoted from S5's S5Assist and S5World): turns each ship's helm
## state into this tick's body-frame force and torque commands (kin.force_cmd,
## kin.torque_cmd). It never writes velocity, position or rotation: every hold, face,
## Level, all-stop and approach goes through the current thrust envelope, and the
## integrator charges propellant for exactly that command, so no mode moves a ship for
## free (FT-SIM-004, FT-SIM-007, D24, D97).
##
## Commands are clamped per axis to the envelope. When several axes saturate this bends
## the commanded direction away from the wanted one (S5: fine in play; the holds correct
## it as axes come out of saturation).
##
## Tuning is the ship's AssistDef, read from world.defs (read-only, FT-ARC-020).

## Stick deflection treated as none; device dead zones are applied by the input layer.
const INPUT_DEAD_ZONE: float = 0.02
## All-stop ends once the ship is below both (m/s, rad/s; FT-SIM-036).
const STOP_SPEED: float = 0.05
const STOP_RATE: float = 0.002
## Level clears once within this angle (rad, 0.3 deg) and turning slower than
## LEVEL_SETTLED_RATE (rad/s).
const LEVEL_DONE: float = 0.3 * PI / 180.0
const LEVEL_SETTLED_RATE: float = 0.01
## A Level press with the roll already within this angle (rad, 1 deg) also pitches.
const ROLLED_LEVEL: float = PI / 180.0
## Fastest back-off speed (m/s) when closer than the approach stand-off.
const APPROACH_BACKOFF_MAX: float = 20.0


## Writes every live ship's force and torque command for this tick, in id order.
static func step(world: SimWorld) -> void:
	for row: int in world.kin.size():
		if world.kin.is_alive(row):
			var tuning: AssistDef = world.defs[row].assist
			_update_modes(world, row, tuning)
			_command(world, row, tuning)


## Whether the ship has a selected target it can fly to: a live ship or a point at its
## own site (ships at different sites never interact).
static func has_target(world: SimWorld, row: int) -> bool:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
	if helm.target_kind[row] == HelmTable.Target.SHIP:
		var other: int = helm.target_ship[row]
		return (
			other >= 0
			and other < kin.size()
			and other != row
			and kin.is_alive(other)
			and kin.same_site(row, other)
		)
	if helm.target_kind[row] == HelmTable.Target.POINT:
		return helm.target_site[row] == kin.site[row]
	return false


## Offset of the selected target from the ship (m, site frame), computed in 64-bit.
static func target_offset(world: SimWorld, row: int) -> Vector3:
	var helm: HelmTable = world.helm
	if helm.target_kind[row] == HelmTable.Target.SHIP:
		return world.kin.relative(row, helm.target_ship[row])
	return world.kin.relative_to_point(
		row, helm.target_x[row], helm.target_y[row], helm.target_z[row]
	)


## Velocity of the selected target relative to the site (m/s); points are at rest.
static func target_velocity(world: SimWorld, row: int) -> Vector3:
	if world.helm.target_kind[row] == HelmTable.Target.SHIP:
		return world.kin.vel[world.helm.target_ship[row]]
	return Vector3.ZERO


## Forward speed (m/s) clamped to the setpoint range: the setpoint that hands control
## back without a lurch (decoupled off, approach released).
static func forward_speed(world: SimWorld, row: int) -> float:
	var tuning: AssistDef = world.defs[row].assist
	var fwd: float = world.kin.vel[row].dot(world.kin.forward(row))
	return clampf(fwd, tuning.speed_min, tuning.speed_max)


## Roll (rad, about the bow) that brings the ship's up nearest to ecliptic up (+Y).
static func roll_error(kin: Kinematics, row: int) -> float:
	var fwd: Vector3 = kin.forward(row)
	var want_up: Vector3 = Vector3.UP - fwd * fwd.dot(Vector3.UP)
	if want_up.length_squared() < 1e-4:
		return 0.0  # Bow straight up or down: any roll is as level as it gets.
	var u: Vector3 = kin.to_local(row, want_up.normalized())
	return atan2(-u.x, u.y)


## Angle (rad) still to go for a Level stage.
static func level_error(kin: Kinematics, row: int, stage: int) -> float:
	var err: float = absf(roll_error(kin, row))
	if stage == HelmTable.Level.ROLL_AND_PITCH:
		err += absf(asin(clampf(kin.forward(row).y, -1.0, 1.0)))
	return err


## Mode bookkeeping before the command: ends all-stop and Level, ramps the setpoint.
static func _update_modes(world: SimWorld, row: int, tuning: AssistDef) -> void:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
	var rot_in: Vector3 = _dead(helm.input_rotation[row])
	var move_in: Vector3 = _dead(helm.input_translation[row])
	if helm.all_stop[row] == 1:
		# FT-SIM-036, FT-HLM-014: latched until at rest or Helm takes over (any stick,
		# throttle, face or approach input).
		var manual: bool = (
			rot_in != Vector3.ZERO
			or move_in != Vector3.ZERO
			or helm.face_held[row] == 1
			or helm.approach_held[row] == 1
		)
		var at_rest: bool = (
			kin.vel[row].length() < STOP_SPEED and kin.ang_vel[row].length() < STOP_RATE
		)
		if manual or at_rest:
			helm.all_stop[row] = 0
	if helm.level[row] != HelmTable.Level.OFF:
		var done: bool = (
			level_error(kin, row, helm.level[row]) < LEVEL_DONE
			and kin.ang_vel[row].length() < LEVEL_SETTLED_RATE
		)
		if done or rot_in != Vector3.ZERO:
			helm.level[row] = HelmTable.Level.OFF
	if not helm.is_decoupled(row) and helm.approach_held[row] == 0:
		# Throttle sets speed, not force (FT-SIM-004): input ramps the setpoint.
		helm.throttle_setpoint[row] = clampf(
			helm.throttle_setpoint[row] + move_in.z * tuning.speed_ramp * SimWorld.DT,
			tuning.speed_min,
			tuning.speed_max
		)


static func _command(world: SimWorld, row: int, tuning: AssistDef) -> void:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
	var rot_in: Vector3 = _dead(helm.input_rotation[row])
	var move_in: Vector3 = _dead(helm.input_translation[row])
	# Body-frame translation input: forward is -Z.
	var trans_in: Vector3 = Vector3(move_in.x, move_in.y, -move_in.z)
	var targeted: bool = has_target(world, row)
	var stopping: bool = helm.all_stop[row] == 1
	var approaching: bool = targeted and helm.approach_held[row] == 1
	var facing: bool = targeted and (helm.face_held[row] == 1 or approaching)
	var decoupled: bool = helm.is_decoupled(row)
	var rates: Vector3 = Vector3(
		tuning.turn_rate_pitch_yaw, tuning.turn_rate_pitch_yaw, tuning.turn_rate_roll
	)

	# Rotation: a body-rate setpoint held through torque, or raw torque when decoupled.
	# All-stop, face and Level are explicit assist actions, so they run decoupled too
	# (FT-HLM-006).
	var w_des: Vector3 = rot_in * rates
	var rate_hold: bool = not decoupled
	if stopping:
		w_des = Vector3.ZERO
		rate_hold = true
	elif facing:
		# FT-HLM-005: at the ship's real turn rate; roll stays manual.
		w_des = _face_rate(kin, row, target_offset(world, row), tuning)
		w_des.z = rot_in.z * tuning.turn_rate_roll
		rate_hold = true
	elif helm.level[row] != HelmTable.Level.OFF:
		w_des = _level_rate(kin, row, helm.level[row], tuning)
		rate_hold = true
	var torque: Vector3
	if rate_hold:
		var w: Vector3 = kin.ang_vel[row]
		var inertia: Vector3 = kin.inertia[row]
		# The gyroscopic term makes the hold cancel cross-coupling too.
		torque = (w_des - w) * inertia / tuning.rate_time_constant + w.cross(w * inertia)
	else:
		torque = rot_in * kin.torque_limit(row)
	kin.torque_cmd[row] = kin.clamp_torque(row, torque)

	# Translation.
	var v_local: Vector3 = kin.to_local(row, kin.vel[row])
	var gain: float = kin.mass[row] / tuning.velocity_time_constant
	var force: Vector3
	if stopping:
		# FT-SIM-036: velocity relative to the site to zero.
		force = -v_local * gain
	elif approaching:
		var v_des: Vector3 = kin.to_local(row, _approach_velocity(world, row, tuning))
		force = (v_des - v_local) * gain
	elif decoupled:
		# FT-SIM-005: stick straight to thrust.
		force = _thrust_for_input(kin, row, trans_in)
	else:
		# The three holds of FT-SIM-004: no drift without strafe input, forward speed
		# at the setpoint. Strafe input fires that axis at full thrust.
		var hold: Vector3 = (Vector3(0.0, 0.0, -helm.throttle_setpoint[row]) - v_local) * gain
		var direct: Vector3 = _thrust_for_input(kin, row, trans_in)
		force = Vector3(
			direct.x if trans_in.x != 0.0 else hold.x,
			direct.y if trans_in.y != 0.0 else hold.y,
			hold.z
		)
	kin.force_cmd[row] = kin.clamp_thrust(row, force)


## Body-frame rate that turns the bow toward a site-frame direction at the real turn
## rate, braking in time to stop on it (D47).
static func _face_rate(kin: Kinematics, row: int, direction: Vector3, tuning: AssistDef) -> Vector3:
	if direction.length_squared() < 1e-6:
		return Vector3.ZERO
	var d: Vector3 = kin.to_local(row, direction).normalized()
	var angle: float = Vector3.FORWARD.angle_to(d)
	var axis: Vector3 = Vector3.FORWARD.cross(d)
	if axis.length_squared() < 1e-12:
		# Dead ahead, or dead astern: pitch over.
		axis = Vector3.RIGHT if angle > 1.0 else Vector3.ZERO
	axis = axis.normalized()
	var limit: Vector3 = kin.torque_limit(row)
	var inertia: Vector3 = kin.inertia[row]
	var alpha: float = minf(limit.x / inertia.x, limit.y / inertia.y)
	return axis * _profile(angle, alpha, tuning.turn_rate_pitch_yaw, tuning)


## Level (FT-HLM-007, D97): roll so the ship's up is as close to ecliptic up as the
## heading allows; at ROLL_AND_PITCH also pitch the bow onto the ecliptic.
static func _level_rate(kin: Kinematics, row: int, stage: int, tuning: AssistDef) -> Vector3:
	var w: Vector3 = Vector3.ZERO
	if stage == HelmTable.Level.ROLL_AND_PITCH:
		var fwd: Vector3 = kin.forward(row)
		var flat: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
		if flat.length_squared() <= 1e-6:
			# Bow (nearly) straight up or down: no heading to keep, so pitch toward
			# the ship's up, which lies (nearly) in the ecliptic.
			var u: Vector3 = kin.to_world(row, Vector3.UP)
			flat = Vector3(u.x, 0.0, u.z)
		w = _face_rate(kin, row, flat, tuning)
	var roll: float = roll_error(kin, row)
	var alpha: float = kin.torque_limit(row).z / kin.inertia[row].z
	w.z = signf(roll) * _profile(absf(roll), alpha, tuning.turn_rate_roll, tuning)
	return w


## Site-frame velocity that flies to the stand-off and matches the target
## (FT-SIM-037): target velocity plus a closing speed along the line of sight, on a
## braking curve far out and an exponential settle near the stand-off.
static func _approach_velocity(world: SimWorld, row: int, tuning: AssistDef) -> Vector3:
	var kin: Kinematics = world.kin
	var rel: Vector3 = target_offset(world, row)
	var target_vel: Vector3 = target_velocity(world, row)
	var dist: float = rel.length()
	if dist < 1e-3:
		return target_vel
	var gap: float = dist - tuning.approach_standoff
	var brake: float = kin.thrust_limit_pos(row).z / kin.mass[row] * tuning.approach_braking
	var speed: float
	if gap > 0.0:
		speed = minf(sqrt(2.0 * brake * gap), gap / tuning.approach_final_time_constant)
		speed = minf(speed, tuning.approach_speed_cap)
	else:
		speed = maxf(gap / tuning.approach_final_time_constant, -APPROACH_BACKOFF_MAX)
	return target_vel + rel / dist * speed


## Full-deflection force in the current envelope for a body-frame input in [-1, 1].
static func _thrust_for_input(kin: Kinematics, row: int, input: Vector3) -> Vector3:
	var pos: Vector3 = kin.thrust_limit_pos(row)
	var neg: Vector3 = kin.thrust_limit_neg(row)
	return Vector3(
		input.x * (pos.x if input.x > 0.0 else neg.x),
		input.y * (pos.y if input.y > 0.0 else neg.y),
		input.z * (pos.z if input.z > 0.0 else neg.z)
	)


## Rate for a move with `angle` (rad) to go: the braking curve on a share of the
## angular acceleration, capped, and linear near zero.
static func _profile(angle: float, alpha: float, cap: float, tuning: AssistDef) -> float:
	var braking: float = sqrt(2.0 * alpha * tuning.attitude_braking * angle)
	return minf(cap, minf(braking, angle / tuning.attitude_time_constant))


static func _dead(v: Vector3) -> Vector3:
	return Vector3(
		v.x if absf(v.x) > INPUT_DEAD_ZONE else 0.0,
		v.y if absf(v.y) > INPUT_DEAD_ZONE else 0.0,
		v.z if absf(v.z) > INPUT_DEAD_ZONE else 0.0
	)
