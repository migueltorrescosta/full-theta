class_name ComfortCamera
extends RefCounted
## Camera roll and field of view for the turret, cockpit and main screen (FT-WPN-009,
## FT-STN-017, D124). The camera's up is the normal of a plane, projected square to the
## view direction. By default that plane is the ship's deck plane. With comfort on, it is
## the plane picked in Settings: the deck plane, the selected target's deck plane (from
## its NEAR orientation, else the own deck), or the player's cosmetic reference plane.
## The cosmetic plane is never spoken or used by rules. Comfort also narrows the field
## of view when reduced FOV is set.

## The reduced field of view, as a share of the camera's normal one (PROVISIONAL).
const REDUCED_FOV: float = 0.75


## The up of the locked plane (world). `target_rot` is the selected target's orientation,
## or null when unknown.
static func plane_up(
	settings: ClientSettings, ship_rot: Quaternion, target_rot: Variant
) -> Vector3:
	var deck: Vector3 = ship_rot * Vector3.UP
	if not settings.comfort:
		return deck
	match settings.roll_lock:
		"target":
			return (target_rot as Quaternion) * Vector3.UP if target_rot is Quaternion else deck
		"reference":
			return settings.reference_plane * Vector3.UP
	return deck


## The selected contact's orientation from NEAR, for the "target" lock; null (our deck)
## for marks, points or a contact without NEAR.
static func target_rot(ctx: StationContext) -> Variant:
	var sel: Dictionary = ctx.crew.selection
	if sel.get("kind", "") != "contact" or not ctx.view.near.has(int(sel["id"])):
		return null
	return NetCodec.unpack_quat(int(ctx.view.near[int(sel["id"])][0]))


## The field of view (degrees) for a camera whose normal one is `normal_deg`.
static func fov_deg(settings: ClientSettings, normal_deg: float) -> float:
	return normal_deg * REDUCED_FOV if settings.comfort and settings.reduced_fov else normal_deg


## A camera basis looking along `forward` (world, unit) with its up as close to `up` as
## possible; `fallback_up` serves when the two are nearly parallel.
static func look(forward: Vector3, up: Vector3, fallback_up: Vector3) -> Basis:
	var u: Vector3 = up - forward * forward.dot(up)
	if u.length_squared() < 1e-6:
		u = fallback_up - forward * forward.dot(fallback_up)
	if u.length_squared() < 1e-6:
		u = forward.cross(Vector3.RIGHT if absf(forward.x) < 0.9 else Vector3.FORWARD)
	u = u.normalized()
	return Basis(forward.cross(u).normalized(), u, -forward)
