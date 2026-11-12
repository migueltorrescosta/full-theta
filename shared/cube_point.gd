class_name CubePoint
extends RefCounted
## A position in the map's wrapping cube (D104, D401, FT-SIM-035): one
## PackedFloat64Array of three 64-bit floats [x, y, z] (m). Every API that passes a
## position passes one, never separate x, y, z arguments or a float32 Vector3; velocities,
## directions and offsets between points stay Vector3. Tables keep a point as three float64
## columns `<role>_x`, `<role>_y`, `<role>_z`, and hot loops read those columns directly
## (read() and the Kinematics column helpers) instead of making a point per row each tick.
##
## Packed arrays are shared by reference in GDScript: a function that keeps a point it was
## given, or changes one, copies it first (duplicate()). The helpers here never change
## their arguments. Content definitions (SiteDef.pos, HazardDef.center) are authored as
## Vector3 in whole metres, exact in float32; of() turns one into a point.

const SIZE: int = 3


## The point (x, y, z) (m); the origin with no arguments.
static func make(x: float = 0.0, y: float = 0.0, z: float = 0.0) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


## The point at a Vector3 (m): content positions and test fixtures.
static func of(v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([v.x, v.y, v.z])


## The point as a float32 Vector3: only for values already float32 on the far side (an
## event payload, drawing); positions in the sim stay 64-bit.
static func to_vector3(p: PackedFloat64Array) -> Vector3:
	return Vector3(p[0], p[1], p[2])


## Whether p is a point: three finite coordinates.
static func is_valid(p: PackedFloat64Array) -> bool:
	return p.size() == SIZE and is_finite(p[0]) and is_finite(p[1]) and is_finite(p[2])


## The point stored at row of the three columns.
static func read(
	xs: PackedFloat64Array, ys: PackedFloat64Array, zs: PackedFloat64Array, row: int
) -> PackedFloat64Array:
	return PackedFloat64Array([xs[row], ys[row], zs[row]])


## Stores p at row of the three columns.
static func write(
	xs: PackedFloat64Array,
	ys: PackedFloat64Array,
	zs: PackedFloat64Array,
	row: int,
	p: PackedFloat64Array
) -> void:
	xs[row] = p[0]
	ys[row] = p[1]
	zs[row] = p[2]


## Appends p as a new row of the three columns.
static func append(
	xs: PackedFloat64Array, ys: PackedFloat64Array, zs: PackedFloat64Array, p: PackedFloat64Array
) -> void:
	xs.append(p[0])
	ys.append(p[1])
	zs.append(p[2])


## p moved by an offset (m), not wrapped.
static func plus(p: PackedFloat64Array, offset: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([p[0] + offset.x, p[1] + offset.y, p[2] + offset.z])
