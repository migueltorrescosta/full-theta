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
## Hot path: has_target, target_offset, _update_modes and _command inlined with the
## columns read through locals, the same arithmetic in the same order.
static func step(world: SimWorld) -> void:
	var kin: Kinematics = world.kin
	var helm: HelmTable = world.helm
	# Columns only read here (assist writes all_stop, align, throttle_setpoint,
	# torque_cmd and force_cmd, and reads those only through the tables).
	var alive: PackedByteArray = kin.alive
	var site: PackedInt32Array = kin.site
	var factions: PackedInt32Array = kin.factions
	var vel: PackedVector3Array = kin.vel
	var ang_vel: PackedVector3Array = kin.ang_vel
	var rot: Array[Quaternion] = kin.rot
	var inertias: PackedVector3Array = kin.inertia
	var mass: PackedFloat64Array = kin.mass
	var torque_scale: PackedFloat64Array = kin.torque_scale
	var max_torque: PackedVector3Array = kin.max_torque
	var input_rotation: PackedVector3Array = helm.input_rotation
	var input_translation: PackedVector3Array = helm.input_translation
	var target_kind: PackedByteArray = helm.target_kind
	var target_ship: PackedInt32Array = helm.target_ship
	var target_site: PackedInt32Array = helm.target_site
	var face_held: PackedByteArray = helm.face_held
	var approach_held: PackedByteArray = helm.approach_held
	var decoupled_col: PackedByteArray = helm.decoupled
	var defs: Array[ShipDef] = world.defs
	var knowledge: KnowledgeTable = world.knowledge
	var n: int = alive.size()
	for row: int in n:
		if alive[row] != 1:
			continue
		var tuning: AssistDef = defs[row].assist
		var rot_in: Vector3 = _dead(input_rotation[row])
		var move_in: Vector3 = _dead(input_translation[row])
		# has_target() and target_offset(), once per ship and tick.
		var targeted: bool = false
		var offset: Vector3 = Vector3.ZERO
		var kind: int = target_kind[row]
		if kind == HelmTable.Target.SHIP:
			var other: int = target_ship[row]
			if (
				other >= 0
				and other < n
				and other != row
				and alive[other] == 1
				and site[row] == site[other]
			):
				var faction: int = factions[row]
				if factions[other] == faction:
					targeted = true
				else:
					var k: int = knowledge.row_for(faction, other)
					targeted = k >= 0 and knowledge.detected[k] == 1
			if targeted:
				offset = kin.relative(row, other)
		elif kind == HelmTable.Target.POINT:
			targeted = target_site[row] == site[row]
			if targeted:
				offset = kin.relative_to_point(
					row, helm.target_x[row], helm.target_y[row], helm.target_z[row]
				)
		var face: int = face_held[row]
		var approach: int = approach_held[row]
		var decoupled: bool = decoupled_col[row] == 1
		var w: Vector3 = ang_vel[row]
		var q: Quaternion = rot[row]

		# _update_modes.
		if helm.all_stop[row] == 1:
			# FT-SIM-036, FT-HLM-014: latched until at rest or Helm takes over (any stick,
			# throttle, face or approach input).
			var manual: bool = (
				rot_in != Vector3.ZERO or move_in != Vector3.ZERO or face == 1 or approach == 1
			)
			var at_rest: bool = vel[row].length() < STOP_SPEED and w.length() < STOP_RATE
			if manual or at_rest:
				helm.all_stop[row] = 0
		if helm.align[row] != HelmTable.Align.OFF:
			# FT-HLM-007: ends within tolerance, on rotation input or with the target lost.
			var done: bool = (
				not targeted
				or (
					_align_error(kin, row, helm.align[row], offset) < ALIGN_DONE
					and w.length() < ALIGN_SETTLED_RATE
				)
			)
			if done or rot_in != Vector3.ZERO:
				helm.align[row] = HelmTable.Align.OFF
		if not decoupled and approach == 0:
			# Throttle sets speed, not force (FT-SIM-004): input ramps the setpoint.
			helm.throttle_setpoint[row] = clampf(
				helm.throttle_setpoint[row] + move_in.z * tuning.speed_ramp * SimWorld.DT,
				tuning.speed_min,
				tuning.speed_max
			)

		# _command.
		# Body-frame translation input: forward is -Z.
		var trans_in: Vector3 = Vector3(move_in.x, move_in.y, -move_in.z)
		var stopping: bool = helm.all_stop[row] == 1
		var approaching: bool = targeted and approach == 1
		var facing: bool = targeted and (face == 1 or approaching)
		var tscale: float = torque_scale[row]
		var py: float = tuning.turn_rate_pitch_yaw * tscale
		var rates: Vector3 = Vector3(py, py, tuning.turn_rate_roll * tscale)
		var inertia: Vector3 = inertias[row]
		var torque_limit: Vector3 = max_torque[row] * tscale

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
			w_des = _face_rate_at(q, inertia, torque_limit, rates.x, offset, tuning)
			w_des.z = rot_in.z * rates.z
			rate_hold = true
		elif targeted and helm.align[row] != HelmTable.Align.OFF:
			w_des = _align_rate(kin, row, helm.align[row], tuning, offset)
			rate_hold = true
		var torque: Vector3
		if rate_hold:
			# The gyroscopic term makes the hold cancel cross-coupling too.
			torque = (w_des - w) * inertia / tuning.rate_time_constant + w.cross(w * inertia)
		else:
			torque = rot_in * torque_limit
		kin.torque_cmd[row] = torque.clamp(-torque_limit, torque_limit)

		# Translation.
		var v_local: Vector3 = q.inverse() * vel[row]
		var gain: float = mass[row] / tuning.velocity_time_constant
		var force: Vector3
		if stopping:
			# FT-SIM-036: velocity relative to the site to zero.
			force = -v_local * gain
		elif approaching:
			var v_des: Vector3 = q.inverse() * _approach_velocity(world, row, tuning, offset)
			force = (v_des - v_local) * gain
		elif decoupled:
			# FT-SIM-005: stick straight to thrust.
			force = _thrust_for_input(kin, row, trans_in)
		else:
			# The three holds of FT-SIM-004: no drift without strafe input, forward speed
			# at the setpoint. Strafe input fires that axis at full thrust.
			var hold: Vector3 = (Vector3(0.0, 0.0, -helm.throttle_setpoint[row]) - v_local) * gain
			if trans_in.x != 0.0 or trans_in.y != 0.0:
				var direct: Vector3 = _thrust_for_input(kin, row, trans_in)
				force = Vector3(
					direct.x if trans_in.x != 0.0 else hold.x,
					direct.y if trans_in.y != 0.0 else hold.y,
					hold.z
				)
			else:
				force = hold
		kin.force_cmd[row] = kin.clamp_thrust(row, force)


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


## Body-frame rate that turns the bow toward a site-frame direction at the real turn
## rate, braking in time to stop on it (D47).
static func _face_rate(kin: Kinematics, row: int, direction: Vector3, tuning: AssistDef) -> Vector3:
	return _face_rate_at(
		kin.rot[row],
		kin.inertia[row],
		kin.torque_limit(row),
		turn_rate_caps(kin, row, tuning).x,
		direction,
		tuning
	)


## _face_rate from the ship's rotation, inertia, torque limit and pitch/yaw rate cap.
static func _face_rate_at(
	rot: Quaternion,
	inertia: Vector3,
	limit: Vector3,
	cap: float,
	direction: Vector3,
	tuning: AssistDef
) -> Vector3:
	if direction.length_squared() < 1e-6:
		return Vector3.ZERO
	var d: Vector3 = (rot.inverse() * direction).normalized()
	var angle: float = Vector3.FORWARD.angle_to(d)
	var axis: Vector3 = Vector3.FORWARD.cross(d)
	if axis.length_squared() < 1e-12:
		# Dead ahead, or dead astern: pitch over.
		axis = Vector3.RIGHT if angle > 1.0 else Vector3.ZERO
	axis = axis.normalized()
	var alpha: float = minf(limit.x / inertia.x, limit.y / inertia.y)
	return axis * _profile(angle, alpha, cap, tuning)


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
