class_name Integrator
extends RefCounted
## 6DOF step with no drag (FT-SIM-001, FT-SIM-003, FT-ARC-007; research/tech §3),
## promoted from S5. Position is exact under constant force over a tick:
## x += v dt + a dt^2 / 2 (FT-SIM-038), in 64-bit per axis (D104). Rotation uses
## Euler's equations for a diagonal inertia and the exact exponential update, then
## renormalises the quaternion.


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
	kin.px[row] += v0.x * dt + a.x * half_dt2
	kin.py[row] += v0.y * dt + a.y * half_dt2
	kin.pz[row] += v0.z * dt + a.z * half_dt2
	kin.vel[row] = v0 + a * dt
	kin.check_offset(row)

	# Angular: Euler's equations for a diagonal inertia tensor, body frame.
	var w: Vector3 = kin.ang_vel[row]
	var inertia: Vector3 = kin.inertia[row]
	w += (tq - w.cross(w * inertia)) / inertia * dt
	kin.ang_vel[row] = w
	var rate: float = w.length()
	if rate > 1e-9:
		# Exact rotation about the body-frame axis over dt; tiny float32 rates are
		# skipped rather than normalised badly.
		kin.rot[row] = (kin.rot[row] * Quaternion(w / rate, rate * dt)).normalized()
	return used
