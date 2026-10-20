class_name S5Integrator
extends RefCounted
## 6DOF step with no drag (FT-SIM-001, FT-SIM-003, research/tech §3.2): position is
## exact under constant force over a tick (FT-SIM-038). Pure: no Node, SceneTree, I/O
## or loading.


## Advances the body by dt under a local force and body-frame torque, both clamped to
## the ship's envelope, and spends propellant in proportion to impulse (FT-SIM-007).
## Returns the propellant used (kg).
static func step(body: S5ShipBody, force_local: Vector3, torque: Vector3, dt: float) -> float:
	var f: Vector3 = body.clamp_thrust(force_local)
	var tq: Vector3 = body.clamp_torque(torque)
	var effort: float = absf(f.x) + absf(f.y) + absf(f.z)
	effort += (absf(tq.x) + absf(tq.y) + absf(tq.z)) / body.lever_arm
	var used: float = effort * dt / body.exhaust_velocity
	if used > body.propellant:
		# Out of propellant: scale the burn to what is left.
		var k: float = body.propellant / used
		f *= k
		tq *= k
		used = body.propellant
	body.propellant -= used

	# Linear: exact for constant force over the tick, x += v0 dt + a dt^2 / 2.
	var v0: Vector3 = body.velocity
	var a: Vector3 = body.to_world(f) / body.mass
	body.position += v0 * dt + 0.5 * a * dt * dt
	body.velocity = v0 + a * dt

	# Angular: Euler's equations for a diagonal inertia tensor, body frame.
	var w: Vector3 = body.angular_velocity
	var w_dot: Vector3 = (tq - w.cross(w * body.inertia)) / body.inertia
	w += w_dot * dt
	body.angular_velocity = w
	var rate: float = w.length()
	if rate > 1e-9:
		# Exact rotation over dt about the body-frame axis, then renormalise. Vector3 is
		# float32, so tiny rates are skipped rather than normalised badly.
		var spin: Quaternion = Quaternion(w.normalized(), rate * dt)
		body.orientation = (body.orientation * spin).normalized()
	return used
