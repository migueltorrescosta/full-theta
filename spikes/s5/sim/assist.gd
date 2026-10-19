class_name S5Assist
extends RefCounted
## Flight assist (FT-SIM-004, FT-SIM-005, D24, D97): turns Helm intent into thruster
## commands. It never writes the ship's state; every hold, face, Level, all-stop and
## approach goes through S5ShipBody's thrust and torque limits, and the integrator
## charges propellant for it (FT-SIM-007). Pure; promote to T028.

# Tuning (provisional; data in M1, owner playtest T013 adjusts it).
var max_pitch_yaw_rate: float = deg_to_rad(40.0)
var max_roll_rate: float = deg_to_rad(90.0)
## Time constant (s) of the angular-rate hold.
var rate_time: float = 0.12
## Time constant (s) of the velocity holds.
var velocity_time: float = 0.4
## Final time constant (s) of attitude moves (face, Level).
var attitude_time: float = 0.3
## Share of the angular acceleration that attitude moves plan to brake with.
var attitude_margin: float = 0.6
var max_speed: float = 300.0
var max_reverse: float = 50.0
## Setpoint ramp (m/s per s) at full throttle input.
var throttle_ramp: float = 60.0
## Small: device dead zones are applied (and rescaled) by the input layer.
var input_dead_zone: float = 0.02
## Hold-to-approach stand-off (m), data in M1 (FT-SIM-037: default 500 m).
var standoff: float = 500.0
var approach_max_speed: float = 300.0
## Share of the retro thrust that approach plans to brake with.
var approach_brake_margin: float = 0.5
## Time constant (s) of the approach's last few hundred metres.
var approach_position_time: float = 4.0


func command(
	body: S5ShipBody, helm: S5HelmState, input: S5HelmInput, item: S5Item
) -> S5ThrustCommand:
	var cmd: S5ThrustCommand = S5ThrustCommand.new()
	var rot_in: Vector3 = _dead(Vector3(input.pitch, input.yaw, input.roll))
	var trans_in: Vector3 = _dead(Vector3(input.strafe, input.lift, -input.throttle))
	var facing: bool = (input.face or input.approach) and item != null

	# Rotation: a rate setpoint, or raw torque in decoupled mode.
	var w_des: Vector3 = rot_in * Vector3(max_pitch_yaw_rate, max_pitch_yaw_rate, max_roll_rate)
	var rate_hold: bool = not helm.decoupled
	if helm.all_stop:
		w_des = Vector3.ZERO
		rate_hold = true
	elif facing:
		# Face assist works in both modes (FT-HLM-006); roll stays manual.
		w_des = face_rate(body, item.position - body.position)
		w_des.z = rot_in.z * max_roll_rate
		rate_hold = true
	elif helm.level != S5HelmState.Level.OFF:
		w_des = level_rate(body, helm.level)
		rate_hold = true
	if rate_hold:
		var w: Vector3 = body.angular_velocity
		# Gyroscopic term so the hold also cancels cross-coupling.
		cmd.torque = (w_des - w) * body.inertia / rate_time + w.cross(w * body.inertia)
	else:
		cmd.torque = rot_in * body.max_torque

	# Translation.
	var v_local: Vector3 = body.to_local(body.velocity)
	if helm.all_stop:
		cmd.force = -v_local * body.mass / velocity_time
	elif input.approach and item != null:
		var v_des: Vector3 = body.to_local(approach_velocity(body, item))
		cmd.force = (v_des - v_local) * body.mass / velocity_time
	elif helm.decoupled:
		cmd.force = body.thrust_for_input(trans_in)
	else:
		# The three holds of FT-SIM-004: no drift without strafe input, and forward
		# speed at the setpoint (forward is -Z).
		var hold: Vector3 = Vector3(0.0, 0.0, -helm.throttle_setpoint) - v_local
		hold *= body.mass / velocity_time
		var direct: Vector3 = body.thrust_for_input(trans_in)
		cmd.force = Vector3(
			direct.x if trans_in.x != 0.0 else hold.x,
			direct.y if trans_in.y != 0.0 else hold.y,
			hold.z
		)
	cmd.force = body.clamp_thrust(cmd.force)
	cmd.torque = body.clamp_torque(cmd.torque)
	return cmd


## Body-frame rate that turns the bow toward a world direction at the real turn rate,
## braking in time to stop on it (D47).
func face_rate(body: S5ShipBody, world_dir: Vector3) -> Vector3:
	if world_dir.length_squared() < 1e-6:
		return Vector3.ZERO
	var d: Vector3 = body.to_local(world_dir).normalized()
	var angle: float = Vector3.FORWARD.angle_to(d)
	var axis: Vector3 = Vector3.FORWARD.cross(d)
	if axis.length_squared() < 1e-12:
		# Dead ahead, or dead astern: pitch over.
		axis = Vector3.RIGHT if angle > 1.0 else Vector3.ZERO
	axis = axis.normalized()
	var alpha: float = minf(body.max_torque.x / body.inertia.x, body.max_torque.y / body.inertia.y)
	return axis * _profile(angle, alpha, max_pitch_yaw_rate)


## Level (FT-HLM-007, D97): roll so the ship's up is as close to ecliptic up (+Y) as the
## heading allows; at ROLL_AND_PITCH also pitch the bow onto the ecliptic.
func level_rate(body: S5ShipBody, stage: S5HelmState.Level) -> Vector3:
	var w: Vector3 = Vector3.ZERO
	if stage == S5HelmState.Level.ROLL_AND_PITCH:
		var fwd: Vector3 = body.forward()
		var flat: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
		if flat.length_squared() <= 1e-6:
			# Bow (nearly) straight up or down: no heading to keep, so pitch about +X
			# toward the ship's up, which lies (nearly) in the ecliptic.
			var u: Vector3 = body.up()
			flat = Vector3(u.x, 0.0, u.z)
		w = face_rate(body, flat)
	var roll: float = roll_error(body)
	var alpha: float = body.max_torque.z / body.inertia.z
	w.z = signf(roll) * _profile(absf(roll), alpha, max_roll_rate)
	return w


## Angle (rad) still to go for the given Level stage.
func level_error(body: S5ShipBody, stage: S5HelmState.Level) -> float:
	var err: float = absf(roll_error(body))
	if stage == S5HelmState.Level.ROLL_AND_PITCH:
		err += absf(asin(clampf(body.forward().y, -1.0, 1.0)))
	return err


## Roll (rad, about the bow) that brings the ship's up nearest to ecliptic up.
static func roll_error(body: S5ShipBody) -> float:
	var fwd: Vector3 = body.forward()
	var want_up: Vector3 = Vector3.UP - fwd * fwd.dot(Vector3.UP)
	if want_up.length_squared() < 1e-4:
		return 0.0  # Bow straight up or down: any roll is as level as it gets.
	var u: Vector3 = body.to_local(want_up.normalized())
	return atan2(-u.x, u.y)


## Velocity (world) that flies to the stand-off and matches the item (FT-SIM-037).
func approach_velocity(body: S5ShipBody, item: S5Item) -> Vector3:
	var rel: Vector3 = item.position - body.position
	var dist: float = rel.length()
	if dist < 1e-3:
		return item.velocity
	var gap: float = dist - standoff
	var brake: float = body.max_thrust_pos.z / body.mass * approach_brake_margin
	var speed: float
	if gap > 0.0:
		# Braking curve far out, exponential settle near the stand-off.
		speed = minf(sqrt(2.0 * brake * gap), gap / approach_position_time)
		speed = minf(speed, approach_max_speed)
	else:
		speed = maxf(gap / approach_position_time, -20.0)
	return item.velocity + rel / dist * speed


## Speed for a move of `angle` to go: the braking curve, capped, linear near zero.
func _profile(angle: float, alpha: float, cap: float) -> float:
	return minf(cap, minf(sqrt(2.0 * alpha * attitude_margin * angle), angle / attitude_time))


func _dead(v: Vector3) -> Vector3:
	return Vector3(
		v.x if absf(v.x) > input_dead_zone else 0.0,
		v.y if absf(v.y) > input_dead_zone else 0.0,
		v.z if absf(v.z) > input_dead_zone else 0.0
	)
