# gdlint: disable=max-public-methods
# (The position helpers are the only way at the position columns, tools/lint_arch.py.)
class_name Kinematics
extends SimTable
## Rigid-body state of every ship, one row per ship in id order (packed layout, S6).
## Positions are site-local: a site id plus an offset of three 64-bit floats (D98,
## D104); the sim never reads site origins. Each site wraps as a 3-torus of side `period`
## (FT-SIM-035, D124): offsets are kept in [-period / 2, period / 2) per axis and every
## position difference is the minimum image. Only this class reads or writes the
## position columns (tools/lint_arch.py): use relative(), relative_to_point(),
## point_at(), wrap_point(), wrap(), place() and translate(). A difference of exactly
## P/2 on an axis wraps to -P/2 either way, so relative(a, b) is not exactly
## -relative(b, a) there; harmless, as P is at least 4x the longest sensor range (D125).
## Velocities and rotation stay float32 Vector3 (D104). Local axes follow Godot: -Z is
## the bow, +X starboard, +Y up; angular velocity is in the body frame (x pitch, y yaw,
## z roll). Limits are copied from the ShipDef at spawn (FT-ARC-020). Units are SI.

## Default side of a site's wrapping cube (m, FT-SIM-035, D124).
const DEFAULT_PERIOD: float = 200000.0

## Side of every site's wrapping cube (m), one period per world (M1); SimWorld sets it.
var period: float = DEFAULT_PERIOD
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


## Places a ship at a site-local offset (m), wrapped onto the site's cube
## (FT-SIM-035). Fails an assertion on a non-finite offset.
func place(row: int, site_id: int, x: float, y: float, z: float) -> void:
	var p: PackedFloat64Array = wrap_point(x, y, z)
	if p.is_empty():
		var msg: String = "non-finite offset for ship %d: (%f, %f, %f)" % [ship_ids[row], x, y, z]
		push_error(msg)
		assert(false, msg)
		return
	site[row] = site_id
	px[row] = p[0]
	py[row] = p[1]
	pz[row] = p[2]


## Moves a ship by a displacement given per axis in 64-bit (m), wrapping across the
## site's faces (FT-SIM-035): the integrator and contact separation move ships this way.
func translate(row: int, dx: float, dy: float, dz: float) -> void:
	px[row] = _wrap(px[row] + dx, period)
	py[row] = _wrap(py[row] + dy, period)
	pz[row] = _wrap(pz[row] + dz, period)


## A site-local point (m) wrapped onto the site's cube, as [x, y, z] in 64-bit; empty
## when any coordinate is not finite (FT-SIM-035: off-cube points wrap, NaN and
## infinity are rejected).
func wrap_point(x: float, y: float, z: float) -> PackedFloat64Array:
	if not (is_finite(x) and is_finite(y) and is_finite(z)):
		return PackedFloat64Array()
	# _wrap inlined for in-cube coordinates, the common case (hot path).
	var half: float = 0.5 * period
	if not (x >= -half and x < half):
		x = _wrap(x, period)
	if not (y >= -half and y < half):
		y = _wrap(y, period)
	if not (z >= -half and z < half):
		z = _wrap(z, period)
	return PackedFloat64Array([x, y, z])


## One site-local coordinate (m) wrapped into [-period / 2, period / 2); the caller
## ensures it is finite (FT-SIM-035). Allocation-free, for hot paths.
func wrap(v: float) -> float:
	return _wrap(v, period)


## The site-local point (m, [x, y, z], wrapped) at a site-frame offset from row's centre:
## aim, target and retreat points (FT-SIM-035). Empty if the offset is not finite.
func point_at(row: int, offset: Vector3) -> PackedFloat64Array:
	return wrap_point(px[row] + offset.x, py[row] + offset.y, pz[row] + offset.z)


## Unwrapped broadphase cells overlapped by row's centre padded by pad (m) on every
## axis, for a cell size (m): out[0..2] the lowest x, y, z cell, out[3..5] the highest
## (floor((x -/+ pad) / cell)). With pad 0 both are the centre's cell, in [-n / 2, n / 2)
## for n = period / cell. Callers wrap the indexes modulo n. out must hold 6 ints.
func cell_range(row: int, cell: float, pad: float, out: PackedInt32Array) -> void:
	out[0] = floori((px[row] - pad) / cell)
	out[1] = floori((py[row] - pad) / cell)
	out[2] = floori((pz[row] - pad) / cell)
	out[3] = floori((px[row] + pad) / cell)
	out[4] = floori((py[row] + pad) / cell)
	out[5] = floori((pz[row] + pad) / cell)


## Every row's broadphase cell for a cell size (m), unwrapped, as cell_range() with
## pad 0 gives it: out[3 * row .. 3 * row + 2] = x, y, z (out is resized to 3 rows).
## One call for a whole grid build.
func cell_coords(cell: float, out: PackedInt32Array) -> void:
	var xs: PackedFloat64Array = px
	var ys: PackedFloat64Array = py
	var zs: PackedFloat64Array = pz
	out.resize(3 * xs.size())
	for row: int in xs.size():
		out[3 * row] = floori((xs[row] - 0.0) / cell)
		out[3 * row + 1] = floori((ys[row] - 0.0) / cell)
		out[3 * row + 2] = floori((zs[row] - 0.0) / cell)


## Whether row a can fly to, track or point at row b: another live ship at its site.
func can_reach(a: int, b: int) -> bool:
	return b >= 0 and b < size() and b != a and is_alive(b) and site[a] == site[b]


## Offset of row b from row a (m, float32) by minimum image, computed in 64-bit
## (FT-SIM-035). Only meaningful when both are at the same site.
func relative(a: int, b: int) -> Vector3:
	# _wrap inlined for in-cube differences, the common case (hot path).
	var half: float = 0.5 * period
	var dx: float = px[b] - px[a]
	var dy: float = py[b] - py[a]
	var dz: float = pz[b] - pz[a]
	if not (dx >= -half and dx < half):
		dx = _wrap(dx, period)
	if not (dy >= -half and dy < half):
		dy = _wrap(dy, period)
	if not (dz >= -half and dz < half):
		dz = _wrap(dz, period)
	return Vector3(dx, dy, dz)


## The ship among ids at row a's site nearest to it (distance as relative().length(),
## float32), or -1; the earlier one in ids wins a tie. One loop for target scans.
func nearest(a: int, ids: PackedInt32Array) -> int:
	var half: float = 0.5 * period
	var xs: PackedFloat64Array = px
	var ys: PackedFloat64Array = py
	var zs: PackedFloat64Array = pz
	var sites: PackedInt32Array = site
	var ax: float = xs[a]
	var ay: float = ys[a]
	var az: float = zs[a]
	var s: int = sites[a]
	var best: int = -1
	var best_dist: float = INF
	for b: int in ids:
		if sites[b] != s:
			continue
		var dx: float = xs[b] - ax
		var dy: float = ys[b] - ay
		var dz: float = zs[b] - az
		if not (dx >= -half and dx < half):
			dx = _wrap(dx, period)
		if not (dy >= -half and dy < half):
			dy = _wrap(dy, period)
		if not (dz >= -half and dz < half):
			dz = _wrap(dz, period)
		var dist: float = Vector3(dx, dy, dz).length()
		if dist < best_dist:
			best_dist = dist
			best = b
	return best


## Offset of a site-local point from row a (m, float32) by minimum image, computed in
## 64-bit; the point need not be wrapped (FT-SIM-035).
func relative_to_point(a: int, x: float, y: float, z: float) -> Vector3:
	var half: float = 0.5 * period
	var dx: float = x - px[a]
	var dy: float = y - py[a]
	var dz: float = z - pz[a]
	if not (dx >= -half and dx < half):
		dx = _wrap(dx, period)
	if not (dy >= -half and dy < half):
		dy = _wrap(dy, period)
	if not (dz >= -half and dz < half):
		dz = _wrap(dz, period)
	return Vector3(dx, dy, dz)


func is_alive(row: int) -> bool:
	return alive[row] == 1


func forward(row: int) -> Vector3:
	return rot[row] * Vector3.FORWARD


func to_local(row: int, world: Vector3) -> Vector3:
	return rot[row].inverse() * world


func to_world(row: int, local: Vector3) -> Vector3:
	return rot[row] * local


## Thrust limits of the current envelope, per local axis (N, positive numbers): toward
## +X, +Y, +Z when positive, else toward -X, -Y, -Z.
func thrust_limit(row: int, positive: bool) -> Vector3:
	return (max_thrust_pos[row] if positive else max_thrust_neg[row]) * thrust_scale[row]


func torque_limit(row: int) -> Vector3:
	return max_torque[row] * torque_scale[row]


## Clamps a local force to the current envelope, axis by axis.
func clamp_thrust(row: int, force: Vector3) -> Vector3:
	return force.clamp(-thrust_limit(row, false), thrust_limit(row, true))


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


## v wrapped into [-p / 2, p / 2) (m). Values already inside are returned unchanged, so
## wrapping never rounds an in-cube offset (D104).
static func _wrap(v: float, p: float) -> float:
	var half: float = 0.5 * p
	if v >= -half and v < half:
		return v
	var w: float = fposmod(v + half, p) - half
	# fposmod can round up to p for a tiny negative remainder.
	return w - p if w >= half else w
