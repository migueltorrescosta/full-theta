class_name Integrator
extends RefCounted
## 6DOF step with no drag (FT-SIM-001, FT-SIM-003, FT-ARC-007; replaces tech §3's Euler
## update), promoted from S5. Position is exact under constant force over a tick:
## x += v dt + a dt^2 / 2 (FT-SIM-038), in 64-bit per axis (D104), wrapped onto the
## cube (FT-SIM-035). Rotation keeps the
## world-frame angular momentum L as its state: the torque adds R tau dt, and with no
## torque L is not touched at all. The attitude then follows the free rigid body by the
## symmetric splitting of its energy into the three principal axes (pitch/2, yaw/2,
## roll, yaw/2, pitch/2), each an exact rotation since its body-frame momentum component
## is constant over it. That keeps |L| exactly and the energy within O(dt^2) with no
## drift (FT-ARC-007), where explicit Euler on Euler's equations gains energy every tick.

## Sub-steps of the splitting: body axis and share of dt.
const SPLIT_AXES: Array[Vector3] = [
	Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3.UP, Vector3.RIGHT
]
const SPLIT_SHARES: Array[float] = [0.5, 0.5, 1.0, 0.5, 0.5]


## Integrates every live ship by dt under its commanded force and torque.
static func step_all(kin: Kinematics, dt: float) -> void:
	# step() inlined, with the columns read and written through locals (packed arrays
	# are shared by reference, so the writes land in kin). Same arithmetic, same order.
	var alive: PackedByteArray = kin.alive
	var force_cmd: PackedVector3Array = kin.force_cmd
	var torque_cmd: PackedVector3Array = kin.torque_cmd
	var lever_arm: PackedFloat64Array = kin.lever_arm
	var exhaust_velocity: PackedFloat64Array = kin.exhaust_velocity
	var propellant: PackedFloat64Array = kin.propellant
	var propellant_used: PackedFloat64Array = kin.propellant_used
	var vel: PackedVector3Array = kin.vel
	var rot: Array[Quaternion] = kin.rot
	var ang_mom: PackedVector3Array = kin.ang_mom
	var ang_vel: PackedVector3Array = kin.ang_vel
	var inertias: PackedVector3Array = kin.inertia
	var mass: PackedFloat64Array = kin.mass
	var thrust_scale: PackedFloat64Array = kin.thrust_scale
	var torque_scale: PackedFloat64Array = kin.torque_scale
	var max_thrust_pos: PackedVector3Array = kin.max_thrust_pos
	var max_thrust_neg: PackedVector3Array = kin.max_thrust_neg
	var max_torque: PackedVector3Array = kin.max_torque
	var half_dt2: float = 0.5 * dt * dt
	for row: int in alive.size():
		if alive[row] != 1:
			continue
		# Kinematics.clamp_thrust and clamp_torque.
		var t_pos: Vector3 = max_thrust_pos[row] * thrust_scale[row]
		var t_neg: Vector3 = max_thrust_neg[row] * thrust_scale[row]
		var f: Vector3 = force_cmd[row].clamp(-t_neg, t_pos)
		var tq_lim: Vector3 = max_torque[row] * torque_scale[row]
		var tq: Vector3 = torque_cmd[row].clamp(-tq_lim, tq_lim)
		var effort: float = absf(f.x) + absf(f.y) + absf(f.z)
		effort += (absf(tq.x) + absf(tq.y) + absf(tq.z)) / lever_arm[row]
		var used: float = effort * dt / exhaust_velocity[row]
		if used > propellant[row]:
			# Out of propellant: scale the burn to what is left.
			var k: float = propellant[row] / used if used > 0.0 else 0.0
			f *= k
			tq *= k
			used = propellant[row]
		propellant[row] -= used
		propellant_used[row] += used

		# Linear: x += v0 dt + a dt^2 / 2, exact for constant force over the tick.
		var v0: Vector3 = vel[row]
		var q: Quaternion = rot[row]
		var a: Vector3 = (q * f) / mass[row]
		kin.translate(
			row, v0.x * dt + a.x * half_dt2, v0.y * dt + a.y * half_dt2, v0.z * dt + a.z * half_dt2
		)
		vel[row] = v0 + a * dt

		# Angular: kick the world-frame momentum, then the free flow by splitting.
		var mom: Vector3 = ang_mom[row] + q * tq * dt
		ang_mom[row] = mom
		var inertia: Vector3 = inertias[row]
		var m: Vector3 = mom * q
		for i: int in SPLIT_AXES.size():
			var axis: Vector3 = SPLIT_AXES[i]
			var r: Quaternion = Quaternion(
				axis, m.dot(axis) / inertia.dot(axis) * SPLIT_SHARES[i] * dt
			)
			q = q * r
			m = m * r
		q = q.normalized()
		rot[row] = q
		ang_vel[row] = m / inertia


## Integrates one ship; force and torque are clamped to the current envelope and
## propellant is spent in proportion to impulse (FT-SIM-007). Returns the propellant
## used this tick (kg).
static func step(kin: Kinematics, row: int, dt: float) -> float:
	var f: Vector3 = kin.clamp_thrust(row, kin.force_cmd[row])
	var tq: Vector3 = kin.clamp_torque(row, kin.torque_cmd[row])
	var effort: float = absf(f.x) + absf(f.y) + absf(f.z)
	effort += (absf(tq.x) + absf(tq.y) + absf(tq.z)) / kin.lever_arm[row]
	var used: float = effort * dt / kin.exhaust_velocity[row]
	if used > kin.propellant[row]:
		# Out of propellant: scale the burn to what is left.
		var k: float = kin.propellant[row] / used if used > 0.0 else 0.0
		f *= k
		tq *= k
		used = kin.propellant[row]
	kin.propellant[row] -= used
	kin.propellant_used[row] += used

	# Linear: x += v0 dt + a dt^2 / 2, exact for constant force over the tick.
	var v0: Vector3 = kin.vel[row]
	var a: Vector3 = (kin.rot[row] * f) / kin.mass[row]
	var half_dt2: float = 0.5 * dt * dt
	kin.translate(
		row, v0.x * dt + a.x * half_dt2, v0.y * dt + a.y * half_dt2, v0.z * dt + a.z * half_dt2
	)
	kin.vel[row] = v0 + a * dt

	# Angular: kick the world-frame momentum, then the free flow by splitting.
	var q: Quaternion = kin.rot[row]
	var mom: Vector3 = kin.ang_mom[row] + q * tq * dt
	kin.ang_mom[row] = mom
	var inertia: Vector3 = kin.inertia[row]
	# Body-frame momentum, carried through the sub-rotations: turning the body by r turns
	# m by r^-1 (Vector3 * Quaternion), which leaves its component along the axis as is.
	var m: Vector3 = mom * q
	for i: int in SPLIT_AXES.size():
		var axis: Vector3 = SPLIT_AXES[i]
		var r: Quaternion = Quaternion(axis, m.dot(axis) / inertia.dot(axis) * SPLIT_SHARES[i] * dt)
		q = q * r
		m = m * r
	q = q.normalized()
	kin.rot[row] = q
	kin.ang_vel[row] = m / inertia
	return used
