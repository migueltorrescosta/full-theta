class_name Kinematics
extends SimTable
## Rigid-body state of every ship, one row per ship in id order (packed layout, S6).
## Positions are site-local: a site id plus an offset of three 64-bit floats, at most
## MAX_OFFSET per axis (FT-SIM-035, D98, D104); the sim never reads site origins.
## Velocities and rotation stay float32 Vector3 (D104). Local axes follow Godot: -Z is
## the bow, +X starboard, +Y up; angular velocity is in the body frame (x pitch, y yaw,
## z roll). Limits are copied from the ShipDef at spawn (FT-ARC-020). Units are SI.

## Largest site-local offset per axis (m, FT-SIM-035).
const MAX_OFFSET: float = 200000.0

var site: PackedInt32Array = PackedInt32Array()
var px: PackedFloat64Array = PackedFloat64Array()
var py: PackedFloat64Array = PackedFloat64Array()
var pz: PackedFloat64Array = PackedFloat64Array()
## Velocity relative to the site (m/s, site frame).
var vel: PackedVector3Array = PackedVector3Array()
var rot: Array[Quaternion] = []
## World-frame angular momentum (N m s): the integrator's rotational state (FT-ARC-007).
var ang_mom: PackedVector3Array = PackedVector3Array()
## Body-frame angular velocity (rad/s), I^-1 R^T L, derived by the integrator each tick
## for readers. Set it through set_angular_velocity() so ang_mom follows.
var ang_vel: PackedVector3Array = PackedVector3Array()
## This tick's commanded body-frame force (N) and torque (N m), set by assist; the
## integrator clamps them to the current envelope.
var force_cmd: PackedVector3Array = PackedVector3Array()
var torque_cmd: PackedVector3Array = PackedVector3Array()
## Share of the definition's thrust and torque limits available now (power, health and
## heat, FT-SIM-006); written by the power system, 1 by default.
var thrust_scale: PackedFloat64Array = PackedFloat64Array()
var torque_scale: PackedFloat64Array = PackedFloat64Array()
## Propellant left (kg) and spent so far (kg, FT-SIM-007).
var propellant: PackedFloat64Array = PackedFloat64Array()
var propellant_used: PackedFloat64Array = PackedFloat64Array()
## 1 while the ship is in play, 0 once destroyed or gone.
var alive: PackedByteArray = PackedByteArray()
# Copied from the ShipDef.
var mass: PackedFloat64Array = PackedFloat64Array()
var inertia: PackedVector3Array = PackedVector3Array()
var max_thrust_pos: PackedVector3Array = PackedVector3Array()
var max_thrust_neg: PackedVector3Array = PackedVector3Array()
var max_torque: PackedVector3Array = PackedVector3Array()
var exhaust_velocity: PackedFloat64Array = PackedFloat64Array()
var lever_arm: PackedFloat64Array = PackedFloat64Array()
var radius: PackedFloat64Array = PackedFloat64Array()
var half_length: PackedFloat64Array = PackedFloat64Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	add_key(ship_id, faction)
	site.append(0)
	px.append(0.0)
	py.append(0.0)
	pz.append(0.0)
	vel.append(Vector3.ZERO)
	rot.append(Quaternion.IDENTITY)
	ang_mom.append(Vector3.ZERO)
	ang_vel.append(Vector3.ZERO)
	force_cmd.append(Vector3.ZERO)
	torque_cmd.append(Vector3.ZERO)
	thrust_scale.append(1.0)
	torque_scale.append(1.0)
	propellant.append(def.propellant_capacity)
	propellant_used.append(0.0)
	alive.append(1)
	mass.append(def.mass)
	inertia.append(def.inertia)
	max_thrust_pos.append(def.max_thrust_pos)
	max_thrust_neg.append(def.max_thrust_neg)
	max_torque.append(def.max_torque)
	exhaust_velocity.append(def.exhaust_velocity)
	lever_arm.append(def.lever_arm)
	radius.append(def.radius)
	half_length.append(def.half_length)


## Sets a ship's body-frame angular velocity (rad/s) and the matching world-frame
## angular momentum at its current rotation; set rot first.
func set_angular_velocity(row: int, w_body: Vector3) -> void:
	ang_vel[row] = w_body
	ang_mom[row] = rot[row] * (inertia[row] * w_body)


## Places a ship at a site-local offset; fails an assertion past MAX_OFFSET.
func place(row: int, site_id: int, x: float, y: float, z: float) -> void:
	site[row] = site_id
	px[row] = x
	py[row] = y
	pz[row] = z
	check_offset(row)


## FT-SIM-035, FT-M1-020: every offset axis stays within MAX_OFFSET of its site.
## A jump (FT-SIM-034, #10) changes the site instead.
func check_offset(row: int) -> bool:
	var ok: bool = in_bounds(px[row], py[row], pz[row])
	if not ok:
		var msg: String = (
			"site-local offset past %d m: ship %d at (%f, %f, %f)"
			% [MAX_OFFSET, ship_ids[row], px[row], py[row], pz[row]]
		)
		push_error(msg)
		assert(false, msg)
	return ok


## Whether a site-local point is on the site grid: finite and within MAX_OFFSET per axis
## (FT-SIM-035).
static func in_bounds(x: float, y: float, z: float) -> bool:
	# The comparisons are false for NaN and infinity.
	return absf(x) <= MAX_OFFSET and absf(y) <= MAX_OFFSET and absf(z) <= MAX_OFFSET


## Whether row a can fly to, track or point at row b: another live ship at its site.
func can_reach(a: int, b: int) -> bool:
	return b >= 0 and b < size() and b != a and is_alive(b) and same_site(a, b)


## Bounding radius of a ship's capsule (m): radius plus half length.
func bound(row: int) -> float:
	return radius[row] + half_length[row]


## Offset of row b from row a (m, float32), computed in 64-bit. Only meaningful when
## both are at the same site; callers check same_site() first.
func relative(a: int, b: int) -> Vector3:
	return Vector3(px[b] - px[a], py[b] - py[a], pz[b] - pz[a])


## Offset of a site-local point from row a (m, float32), computed in 64-bit.
func relative_to_point(a: int, x: float, y: float, z: float) -> Vector3:
	return Vector3(x - px[a], y - py[a], z - pz[a])


func same_site(a: int, b: int) -> bool:
	return site[a] == site[b]


func is_alive(row: int) -> bool:
	return alive[row] == 1


func forward(row: int) -> Vector3:
	return rot[row] * Vector3.FORWARD


func to_local(row: int, world: Vector3) -> Vector3:
	return rot[row].inverse() * world


func to_world(row: int, local: Vector3) -> Vector3:
	return rot[row] * local


## Thrust limits of the current envelope, per local axis (N, positive numbers).
func thrust_limit_pos(row: int) -> Vector3:
	return max_thrust_pos[row] * thrust_scale[row]


func thrust_limit_neg(row: int) -> Vector3:
	return max_thrust_neg[row] * thrust_scale[row]


func torque_limit(row: int) -> Vector3:
	return max_torque[row] * torque_scale[row]


## Clamps a local force to the current envelope, axis by axis.
func clamp_thrust(row: int, force: Vector3) -> Vector3:
	return force.clamp(-thrust_limit_neg(row), thrust_limit_pos(row))


func clamp_torque(row: int, torque: Vector3) -> Vector3:
	return torque.clamp(-torque_limit(row), torque_limit(row))


func columns() -> Array:
	return (
		super()
		+ [
			["site", site],
			["px", px],
			["py", py],
			["pz", pz],
			["vel", vel],
			["rot", rot],
			["ang_mom", ang_mom],
			["ang_vel", ang_vel],
			["force_cmd", force_cmd],
			["torque_cmd", torque_cmd],
			["thrust_scale", thrust_scale],
			["torque_scale", torque_scale],
			["propellant", propellant],
			["propellant_used", propellant_used],
			["alive", alive],
			["mass", mass],
			["inertia", inertia],
			["max_thrust_pos", max_thrust_pos],
			["max_thrust_neg", max_thrust_neg],
			["max_torque", max_torque],
			["exhaust_velocity", exhaust_velocity],
			["lever_arm", lever_arm],
			["radius", radius],
			["half_length", half_length],
		]
	)
