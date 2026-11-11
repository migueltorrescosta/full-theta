class_name MountArc
extends RefCounted
## A mount's firing arc (FT-SIM-011), shared by the sim (WeaponSystem) and the Weapons
## station (FT-ARC-021), so both apply one rule: a direction is in the arc when its angle
## to the rest direction is at most the arc's half angle. Pure: names nothing outside
## shared/. The Vector3 functions take ship-frame unit vectors; the *_angle ones take one
## angle (rad) measured from the rest direction.


## True when `dir` lies within `half_angle` (rad) of the rest direction `forward`.
static func in_arc(forward: Vector3, half_angle: float, dir: Vector3) -> bool:
	return forward.angle_to(dir) <= half_angle


## `dir` itself when in the arc, else the nearest direction on its edge.
static func clamp_to_arc(forward: Vector3, half_angle: float, dir: Vector3) -> Vector3:
	if in_arc(forward, half_angle, dir):
		return dir
	return turn_toward(forward, dir, half_angle)


## `from` turned toward `to` by at most `max_angle` (rad); `to` itself when nearer. When
## the two are opposite, it turns about an axis square to `from`.
static func turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle: float = from.angle_to(to)
	if angle <= max_angle:
		return to
	var axis: Vector3 = from.cross(to)
	if axis.length_squared() < 1e-12:
		axis = from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_angle).normalized()


## True when an angle (rad) from the rest direction lies within `half_angle`.
static func in_arc_angle(half_angle: float, angle: float) -> bool:
	return absf(angle_difference(0.0, angle)) <= half_angle


## The angle (rad, in [-PI, PI]) itself when in the arc, else the nearer edge.
static func clamp_angle(half_angle: float, angle: float) -> float:
	return clampf(angle_difference(0.0, angle), -half_angle, half_angle)


## Angle `from` turned toward `to` (rad) the short way by at most `max_angle`.
static func turn_toward_angle(from: float, to: float, max_angle: float) -> float:
	var d: float = angle_difference(from, to)
	if absf(d) <= max_angle:
		return to
	return from + signf(d) * max_angle
