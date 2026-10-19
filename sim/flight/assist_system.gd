class_name AssistSystem
extends RefCounted
## Flight assist (T028, promoted from S5's S5Assist and S5World): turns each ship's helm
## state into this tick's body-frame force and torque commands (kin.force_cmd,
## kin.torque_cmd). It never writes velocity, position or rotation: every hold, face,
## Align, all-stop and approach goes through the current thrust envelope, and the
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
## Align clears once within this angle (rad, 0.3 deg) and turning slower than
## ALIGN_SETTLED_RATE (rad/s).
const ALIGN_DONE: float = 0.3 * PI / 180.0
const ALIGN_SETTLED_RATE: float = 0.01
## An Align press with the roll already within this angle (rad, 1 deg) also faces.
const ROLLED: float = PI / 180.0
## With the target within about this sine of the bow line (0.6 deg) it is at 12 o'clock
## whatever the roll, so Align's roll error is 0.
const ALIGN_ON_BOW: float = 0.01
## Fastest back-off speed (m/s) when closer than the approach stand-off.
const APPROACH_BACKOFF_MAX: float = 20.0


## Writes every live ship's force and torque command for this tick, in id order.
static func step(world: SimWorld) -> void:
	for row: int in world.kin.size():
		if world.kin.is_alive(row):
			var tuning: AssistDef = world.defs[row].assist
			var rot_in: Vector3 = _dead(world.helm.input_rotation[row])
			var move_in: Vector3 = _dead(world.helm.input_translation[row])
			# The target's offset once per ship and tick; ZERO without a target.
			var targeted: bool = has_target(world, row)
			var offset: Vector3 = target_offset(world, row) if targeted else Vector3.ZERO
			_update_modes(world, row, tuning, rot_in, move_in, targeted, offset)
			_command(world, row, tuning, rot_in, move_in, targeted, offset)


## Whether the ship has a selected target it can fly to: a live ship its faction detects
## (FT-ARC-013) or a point at its own site (ships at different sites never interact).
static func has_target(world: SimWorld, row: int) -> bool:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
	if helm.target_kind[row] == HelmTable.Target.SHIP:
		var other: int = helm.target_ship[row]
		return (
			kin.can_reach(row, other)
			and KnowledgeSystem.is_detected(world, world.faction_of(row), other)
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


## Roll (rad, about the bow) that brings a target at ship-frame offset `local` to 12
## o'clock: into the ship's pitch plane, above the bow direction (FT-HLM-007, D124). 0
## with the target on the bow line, where every roll will do.
static func align_roll_error(local: Vector3) -> float:
	var d: Vector3 = local.normalized()
	if Vector2(d.x, d.y).length() < ALIGN_ON_BOW:
		return 0.0
	return atan2(-d.x, d.y)


## Angle (rad) still to go for an Align stage, for a target at site-frame offset `offset`.
static func _align_error(kin: Kinematics, row: int, stage: int, offset: Vector3) -> float:
	var err: float = absf(align_roll_error(kin.to_local(row, offset)))
	if stage == HelmTable.Align.ROLL_AND_FACE:
		err += kin.forward(row).angle_to(offset)
	return err


## Turn-rate caps (rad/s: pitch, yaw, roll): the AssistDef caps times the torque
## envelope share, so thruster pips and a boost raise Helm's turn rate with its torque
## (1 at nominal; FT-SIM-006, P1).
static func turn_rate_caps(kin: Kinematics, row: int, tuning: AssistDef) -> Vector3:
	var py: float = tuning.turn_rate_pitch_yaw * kin.torque_scale[row]
	return Vector3(py, py, tuning.turn_rate_roll * kin.torque_scale[row])


## Mode bookkeeping before the command: ends all-stop and Align, ramps the setpoint.
## rot_in and move_in are the Helm inputs after the deadzone.
## targeted and offset are has_target() and target_offset() for this tick.
static func _update_modes(
	world: SimWorld,
	row: int,
	tuning: AssistDef,
	rot_in: Vector3,
	move_in: Vector3,
	targeted: bool,
	offset: Vector3
) -> void:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
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
	if helm.align[row] != HelmTable.Align.OFF:
		# FT-HLM-007: ends within tolerance, on rotation input or with the target lost.
		var done: bool = (
			not targeted
			or (
				_align_error(kin, row, helm.align[row], offset) < ALIGN_DONE
				and kin.ang_vel[row].length() < ALIGN_SETTLED_RATE
			)
		)
		if done or rot_in != Vector3.ZERO:
			helm.align[row] = HelmTable.Align.OFF
	if not helm.is_decoupled(row) and helm.approach_held[row] == 0:
		# Throttle sets speed, not force (FT-SIM-004): input ramps the setpoint.
		helm.throttle_setpoint[row] = clampf(
			helm.throttle_setpoint[row] + move_in.z * tuning.speed_ramp * SimWorld.DT,
			tuning.speed_min,
			tuning.speed_max
		)


static func _command(
	world: SimWorld,
	row: int,
	tuning: AssistDef,
	rot_in: Vector3,
	move_in: Vector3,
	targeted: bool,
	offset: Vector3
) -> void:
	var helm: HelmTable = world.helm
	var kin: Kinematics = world.kin
	# Body-frame translation input: forward is -Z.
	var trans_in: Vector3 = Vector3(move_in.x, move_in.y, -move_in.z)
	var stopping: bool = helm.all_stop[row] == 1
	var approaching: bool = targeted and helm.approach_held[row] == 1
	var facing: bool = targeted and (helm.face_held[row] == 1 or approaching)
	var decoupled: bool = helm.is_decoupled(row)
	var rates: Vector3 = turn_rate_caps(kin, row, tuning)

	# Rotation: a body-rate setpoint held through torque, or raw torque when decoupled.
	# All-stop, face and Align are explicit assist actions, so they run decoupled too
	# (FT-HLM-006).
	var w_des: Vector3 = rot_in * rates
	var rate_hold: bool = not decoupled
	if stopping:
		w_des = Vector3.ZERO
		rate_hold = true
	elif facing:
		# FT-HLM-005: at the ship's real turn rate; roll stays manual.
		w_des = _face_rate(kin, row, offset, tuning)
		w_des.z = rot_in.z * rates.z
		rate_hold = true
	elif targeted and helm.align[row] != HelmTable.Align.OFF:
		w_des = _align_rate(kin, row, helm.align[row], tuning, offset)
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
		var v_des: Vector3 = kin.to_local(row, _approach_velocity(world, row, tuning, offset))
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
	return axis * _profile(angle, alpha, turn_rate_caps(kin, row, tuning).x, tuning)


## Align (FT-HLM-007, D124): roll the selected target to 12 o'clock; at ROLL_AND_FACE
## also turn the bow onto it. offset is the target's site-frame offset.
static func _align_rate(
	kin: Kinematics, row: int, stage: int, tuning: AssistDef, offset: Vector3
) -> Vector3:
	var w: Vector3 = Vector3.ZERO
	if stage == HelmTable.Align.ROLL_AND_FACE:
		w = _face_rate(kin, row, offset, tuning)
	var roll: float = align_roll_error(kin.to_local(row, offset))
	var alpha: float = kin.torque_limit(row).z / kin.inertia[row].z
	w.z = signf(roll) * _profile(absf(roll), alpha, turn_rate_caps(kin, row, tuning).z, tuning)
	return w


## Site-frame velocity that flies to the stand-off and matches the target
## (FT-SIM-037): target velocity plus a closing speed along the line of sight, on a
## braking curve far out and an exponential settle near the stand-off. rel is the
## target's offset (m, site frame).
static func _approach_velocity(
	world: SimWorld, row: int, tuning: AssistDef, rel: Vector3
) -> Vector3:
	var target_vel: Vector3 = target_velocity(world, row)
	var dist: float = rel.length()
	if dist < 1e-3:
		return target_vel
	var gap: float = dist - tuning.approach_standoff
	var speed: float
	if gap > 0.0:
		speed = closing_speed(world.kin, row, tuning, gap)
	else:
		speed = maxf(gap / tuning.approach_final_time_constant, -APPROACH_BACKOFF_MAX)
	return target_vel + rel / dist * speed


## Closing speed (m/s) for a gap >= 0 (m) to a stand-off, on the approach curve
## (FT-SIM-037): a braking curve on the retro thrust share far out, an exponential
## settle near, capped.
static func closing_speed(kin: Kinematics, row: int, tuning: AssistDef, gap: float) -> float:
	var brake: float = kin.thrust_limit(row, true).z / kin.mass[row] * tuning.approach_braking
	var speed: float = minf(sqrt(2.0 * brake * gap), gap / tuning.approach_final_time_constant)
	return minf(speed, tuning.approach_speed_cap)


## Full-deflection force in the current envelope for a body-frame input in [-1, 1].
static func _thrust_for_input(kin: Kinematics, row: int, input: Vector3) -> Vector3:
	var pos: Vector3 = kin.thrust_limit(row, true)
	var neg: Vector3 = kin.thrust_limit(row, false)
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
