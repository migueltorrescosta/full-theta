class_name Lead
extends RefCounted
## First-order lead intercept (FT-SIM-014, D25), shared by the sim and the Weapons
## reticle (FT-ARC-021): the shot leaves the shooter with the shooter's velocity plus
## the muzzle speed along the aim, and the target keeps its current velocity. Pure:
## names nothing outside shared/.
##
## With r the target's position relative to the shooter, v its velocity relative to
## the shooter and s the muzzle speed, the shot meets the target at the smallest t > 0
## with |r + v t| = s t, so (v.v - s^2) t^2 + 2 (r.v) t + r.r = 0; the aim point,
## relative to the shooter, is r + v t.

## Returned by intercept_time when no shot can reach the target.
const NONE: float = -1.0
## Below this |v.v - s^2| (m^2/s^2) the quadratic is treated as linear.
const _LINEAR_EPS: float = 1e-9


## Time to intercept (s), or NONE when the target can't be reached. rel_pos and
## rel_vel are target minus shooter (m, m/s); speed is the muzzle speed (m/s).
static func intercept_time(rel_pos: Vector3, rel_vel: Vector3, speed: float) -> float:
	# Components as 64-bit floats: Vector3 dot products are float32.
	var rx: float = rel_pos.x
	var ry: float = rel_pos.y
	var rz: float = rel_pos.z
	var vx: float = rel_vel.x
	var vy: float = rel_vel.y
	var vz: float = rel_vel.z
	var a: float = vx * vx + vy * vy + vz * vz - speed * speed
	var b: float = rx * vx + ry * vy + rz * vz
	var c: float = rx * rx + ry * ry + rz * rz
	if c == 0.0:
		return 0.0
	var t: float = NONE
	if absf(a) < _LINEAR_EPS:
		# Target recedes at exactly the muzzle speed: 2 b t + c = 0.
		if b < 0.0:
			t = -c / (2.0 * b)
	else:
		var disc: float = b * b - a * c
		if disc >= 0.0:
			var root: float = sqrt(disc)
			var t1: float = (-b - root) / a
			var t2: float = (-b + root) / a
			var lo: float = minf(t1, t2)
			var hi: float = maxf(t1, t2)
			t = lo if lo > 0.0 else (hi if hi > 0.0 else NONE)
	return t


## Aim point relative to the shooter (m) for an intercept time from intercept_time().
static func aim_point(rel_pos: Vector3, rel_vel: Vector3, time: float) -> Vector3:
	return rel_pos + rel_vel * time


## Unit aim direction for the intercept, or Vector3.ZERO when there is no solution.
static func aim_direction(rel_pos: Vector3, rel_vel: Vector3, speed: float) -> Vector3:
	var t: float = intercept_time(rel_pos, rel_vel, speed)
	if t < 0.0:
		return Vector3.ZERO
	return aim_point(rel_pos, rel_vel, t).normalized()
