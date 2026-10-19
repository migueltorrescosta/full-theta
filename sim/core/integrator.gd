class_name Integrator
extends RefCounted
## 6DOF step with no drag (FT-SIM-001, FT-SIM-003, FT-ARC-007; replaces tech §3's Euler
## update), promoted from S5. Position is exact under constant force over a tick:
## x += v dt + a dt^2 / 2 (FT-SIM-038), in 64-bit per axis (D104), wrapped onto the
## site's cube (FT-SIM-035). Rotation keeps the
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
	for row: int in kin.size():
		if kin.is_alive(row):
			step(kin, row, dt)


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
