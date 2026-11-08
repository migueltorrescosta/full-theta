class_name WeaponsAim
extends RefCounted
## Weapons' aim and fire state (R13-7): each mount's aim point, which points still need
## sending and when each mount may fire next, keyed by mount index. The aim is a point, like
## the sim's (`aim_mount`, FT-WPN-009): it holds in world space while the ship turns. Input
## stops at the arc edge (FT-SIM-011); the lead direction comes from Lead (FT-SIM-014).
## Reads the panel's ship, view and mount rows; draws nothing.

## Aim points go out at most this often (ms), when they moved more than AIM_SEND_M (m).
const AIM_SEND_MS: int = 50
const AIM_SEND_M: float = 1.0

## Mount index -> aim point (m); a mount without one rests on its barrel.
var aims: Dictionary = {}
## Mount index -> the aim point last sent (m).
var sent: Dictionary = {}
## Mount index -> true while its aim point still needs sending.
var dirty: Dictionary = {}
## Mount index -> the earliest time (ms) it may fire again.
var next_fire: Dictionary = {}
var _next_aim_ms: int = 0
var _p: WeaponsPanel


func _init(panel: WeaponsPanel) -> void:
	_p = panel


## The position of mount i (m).
func mount_position(i: int) -> Vector3:
	return (
		_p.ctx.interp.own_position() + _p.ctx.interp.own_rotation() * _p.ship_def.mounts[i].position
	)


## Where mount i aims (world unit vector from the mount): its aim point, else its barrel.
func aim_dir(i: int) -> Vector3:
	var rot: Quaternion = _p.ctx.interp.own_rotation()
	if aims.has(i):
		var to: Vector3 = _p.ctx.interp.offset_to(aims[i]) - rot * _p.ship_def.mounts[i].position
		if to.length_squared() > 1e-6:
			return to.normalized()
	return rot * barrel(i)


## Mount i's barrel in the ship frame (the MOUNTS block; its rest direction before data).
func barrel(i: int) -> Vector3:
	var b: Variant = _p.mount_row(i).get("barrel")
	return (b as Vector3).normalized() if b is Vector3 else _p.ship_def.mounts[i].forward


## Aims mount i along `dir` (world unit vector): a point at the weapon's range.
func set_aim_dir(i: int, dir: Vector3) -> void:
	var p: Vector3 = mount_position(i) + dir * _p.weapon_of(i).max_range
	aims[i] = p
	if not sent.has(i) or (sent[i] as Vector3).distance_to(p) > AIM_SEND_M:
		dirty[i] = true


## The aim direction from mount i (world unit) that leads `contact`, or null when it is
## unknown or out of reach (Lead.intercept_time, FT-SIM-014).
func lead_dir(i: int, contact: int) -> Variant:
	var ctx: StationContext = _p.ctx
	if contact not in ctx.interp.contact_ids():
		return null
	var rot: Quaternion = ctx.interp.own_rotation()
	var rel: Vector3 = (
		ctx.interp.offset_to(ctx.interp.contact_position(contact))
		- rot * _p.ship_def.mounts[i].position
	)
	var model: Dictionary = ctx.view.contacts.get("model", {})
	var vel: Vector3i = model[contact][1] if model.has(contact) else Vector3i.ZERO
	var own: Vector3i = ctx.view.kin.get("vel", Vector3i.ZERO)
	var rel_vel: Vector3 = Vector3(vel - own) / NetCodec.VEL_Q
	var speed: float = _p.weapon_of(i).projectile_speed
	if speed <= 0.0:
		# A beam arrives at once: aim straight at the contact.
		return rel.normalized() if rel.length_squared() > 1e-6 else null
	var t: float = Lead.intercept_time(rel, rel_vel, speed)
	if t < 0.0:
		return null
	var aim: Vector3 = Lead.aim_point(rel, rel_vel, t)
	return aim.normalized() if aim.length_squared() > 1e-6 else null


## True when a world direction from mount i lies in its arc (FT-SIM-011).
func in_arc(i: int, dir: Vector3) -> bool:
	var m: MountDef = _p.ship_def.mounts[i]
	return m.forward.angle_to(_p.ctx.interp.own_rotation().inverse() * dir) <= m.arc_half_angle


## Aims mount i along `dir` (world), stopped at the arc edge: input stops there; a held aim
## the ship turns out of arc stays (FT-WPN-009).
func aim_within_arc(i: int, dir: Vector3) -> void:
	var m: MountDef = _p.ship_def.mounts[i]
	var rot: Quaternion = _p.ctx.interp.own_rotation()
	var local: Vector3 = rot.inverse() * dir
	if m.forward.angle_to(local) > m.arc_half_angle:
		dir = rot * turn_toward(m.forward, local, m.arc_half_angle)
	set_aim_dir(i, dir.normalized())


## Sends the aim points that moved, at most every AIM_SEND_MS unless `force`.
func flush(now: int, force: bool) -> void:
	if dirty.is_empty() or (now < _next_aim_ms and not force):
		return
	for i: int in dirty:
		var p: Vector3 = aims[i]
		_p.ctx.intents.command(
			{"kind": "aim_mount", "mount_index": i, "aim_x": p.x, "aim_y": p.y, "aim_z": p.z}
		)
		sent[i] = p
	dirty.clear()
	_next_aim_ms = now + AIM_SEND_MS


## `from` turned toward `to` by at most `max_angle` (rad); `to` itself when nearer.
static func turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle: float = from.angle_to(to)
	if angle <= max_angle:
		return to
	var axis: Vector3 = from.cross(to)
	if axis.length_squared() < 1e-12:
		axis = from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_angle).normalized()
