class_name Sweep
extends RefCounted
## Shape queries for collisions (FT-SIM-009): ships are spheres or capsules (a radius
## around a segment along local Z), projectiles swept spheres. Everything is relative
## to one origin, usually a ship's centre, so float32 vectors stay small (D104).
## Sweep times are fractions of the swept segment, in [0, 1]; NONE means no contact.

const NONE: float = -1.0
const _EPS: float = 1e-12


## Earliest t in [0, 1] at which the point start + motion t is within r of the origin.
static func sphere(start: Vector3, motion: Vector3, r: float) -> float:
	var c: float = start.length_squared() - r * r
	if c <= 0.0:
		return 0.0
	var a: float = motion.length_squared()
	var b: float = start.dot(motion)
	if a <= _EPS or b >= 0.0:
		return NONE
	var disc: float = b * b - a * c
	if disc < 0.0:
		return NONE
	var t: float = (-b - sqrt(disc)) / a
	return t if t <= 1.0 else NONE


## Earliest t in [0, 1] at which start + motion t is within r of the segment from
## -axis to +axis (a capsule centred on the origin). The capsule is the union of a
## finite cylinder and two end spheres, so the first entry is the earliest of the three.
static func capsule(start: Vector3, motion: Vector3, axis: Vector3, r: float) -> float:
	var len2: float = axis.length_squared()
	if len2 <= _EPS:
		return sphere(start, motion, r)
	var best: float = _cylinder(start, motion, axis, r)
	for end: Vector3 in [axis, -axis]:
		var t: float = sphere(start - end, motion, r)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## Earliest t in [0, 1] inside the cylinder of radius r around the segment -axis..axis.
static func _cylinder(start: Vector3, motion: Vector3, axis: Vector3, r: float) -> float:
	var half: float = axis.length()
	var u: Vector3 = axis / half
	var s_perp: Vector3 = start - u * start.dot(u)
	var m_perp: Vector3 = motion - u * motion.dot(u)
	var t: float = sphere(s_perp, m_perp, r)
	if t < 0.0:
		return NONE
	var along: float = (start + motion * t).dot(u)
	return t if absf(along) <= half else NONE


## Closest points between segments p1..q1 and p2..q2 (Ericson, Real-Time Collision
## Detection §5.1.9), as [on the first, on the second].
static func closest_points(
	p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3
) -> PackedVector3Array:
	var d1: Vector3 = q1 - p1
	var d2: Vector3 = q2 - p2
	var r: Vector3 = p1 - p2
	var a: float = d1.length_squared()
	var e: float = d2.length_squared()
	var f: float = d2.dot(r)
	var s: float = 0.0
	var t: float = 0.0
	if a <= _EPS and e > _EPS:
		t = clampf(f / e, 0.0, 1.0)
	elif a > _EPS:
		var c: float = d1.dot(r)
		if e <= _EPS:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2)
			var denom: float = a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > _EPS else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return PackedVector3Array([p1 + d1 * s, p2 + d2 * t])


## Time (s) until two spheres reach the given centre distance, moving at rel_vel
## (b minus a) with rel_pos (b minus a); 0 if already within reach and closing, NONE
## if they never get there.
static func time_to_reach(rel_pos: Vector3, rel_vel: Vector3, reach: float) -> float:
	var b: float = rel_pos.dot(rel_vel)
	if b >= 0.0:
		return NONE
	var c: float = rel_pos.length_squared() - reach * reach
	if c <= 0.0:
		return 0.0
	var a: float = rel_vel.length_squared()
	var disc: float = b * b - a * c
	if disc < 0.0:
		return NONE
	return (-b - sqrt(disc)) / a
