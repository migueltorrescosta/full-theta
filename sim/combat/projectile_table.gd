class_name ProjectileTable
extends SimTable
## Live projectiles, one row each, keyed by the shooter's ship id and faction
## (FT-ARC-012). Positions are 64-bit offsets in the cube like ships' (D104), wrapped
## onto it (FT-SIM-035); only this class and Kinematics read them
## (tools/lint_arch.py). Velocity is float32 in the world frame. Packed columns keep 500
## projectiles cheap (S6). Rows are appended when a shot is fired and removed when the
## projectile hits or expires, so a ship has no rows at spawn.

var pos_x: PackedFloat64Array = PackedFloat64Array()
var pos_y: PackedFloat64Array = PackedFloat64Array()
var pos_z: PackedFloat64Array = PackedFloat64Array()
## Velocity (m/s).
var vel: PackedVector3Array = PackedVector3Array()
## Swept-sphere radius (m, FT-SIM-009).
var radius: PackedFloat64Array = PackedFloat64Array()
## Damage energy delivered on a hit (J).
var energy: PackedFloat64Array = PackedFloat64Array()
## Ticks left before the projectile expires.
var ttl: PackedInt32Array = PackedInt32Array()
## Damage type of the hit (FT-SIM-022).
var damage_type: Array[StringName] = []
## Guided ordnance (FT-SIM-013, FT-WPN-008): turn rate (rad/s; 0 flies straight) and the
## tracked contact followed (ship id or -1). GuidanceSystem steers these each tick.
var turn_rate: PackedFloat64Array = PackedFloat64Array()
var guide_target: PackedInt32Array = PackedInt32Array()
## Share of the turn rate left at track quality 0 (WeaponDef.track_floor, D214).
var track_floor: PackedFloat64Array = PackedFloat64Array()


## Appends a projectile at a point (m, wrapped) and returns its row.
func spawn(
	shooter: int,
	faction: int,
	at: PackedFloat64Array,
	velocity: Vector3,
	body_radius: float,
	shot_energy: float,
	ttl_ticks: int
) -> int:
	add_key(shooter, faction)
	CubePoint.append(pos_x, pos_y, pos_z, at)
	vel.append(velocity)
	radius.append(body_radius)
	energy.append(shot_energy)
	ttl.append(ttl_ticks)
	damage_type.append(&"kinetic")
	turn_rate.append(0.0)
	guide_target.append(-1)
	track_floor.append(1.0)
	return size() - 1


## Gives projectile k its damage type and, when guide_rate is positive, guidance at
## the contact (target >= 0).
func set_payload(
	k: int, type: StringName, guide_rate: float = 0.0, target: int = -1, floor_share: float = 1.0
) -> void:
	damage_type[k] = type
	turn_rate[k] = guide_rate
	guide_target[k] = target
	track_floor[k] = floor_share


## From projectile k to ship s (m, minimum image; wrapped).
func offset_to_ship(k: int, kin: Kinematics, s: int) -> Vector3:
	return -kin.relative_to_column(s, pos_x, pos_y, pos_z, k)


## Moves projectile k by its velocity for dt (s), wrapping across the cube's faces
## (FT-SIM-035).
func advance(k: int, kin: Kinematics, dt: float) -> void:
	var v: Vector3 = vel[k]
	# kin.wrap only off the cube (it returns in-cube values unchanged).
	var half: float = 0.5 * kin.period
	var x: float = pos_x[k] + v.x * dt
	var y: float = pos_y[k] + v.y * dt
	var z: float = pos_z[k] + v.z * dt
	pos_x[k] = x if x >= -half and x < half else kin.wrap(x)
	pos_y[k] = y if y >= -half and y < half else kin.wrap(y)
	pos_z[k] = z if z >= -half and z < half else kin.wrap(z)


## Projectile k's position relative to ship s, both taken dt (s) before the ship's
## current position (the ship moving at its current velocity): the start of a tick's
## sweep (m, world frame), by minimum image so shots across a seam hit (FT-SIM-035).
func relative_start(k: int, kin: Kinematics, s: int, dt: float) -> Vector3:
	var vs: Vector3 = kin.vel[s]
	var half: float = 0.5 * kin.period
	var dx: float = pos_x[k] + vs.x * dt - kin.pos_x[s]
	var dy: float = pos_y[k] + vs.y * dt - kin.pos_y[s]
	var dz: float = pos_z[k] + vs.z * dt - kin.pos_z[s]
	if not (dx >= -half and dx < half):
		dx = kin.wrap(dx)
	if not (dy >= -half and dy < half):
		dy = kin.wrap(dy)
	if not (dz >= -half and dz < half):
		dz = kin.wrap(dz)
	return Vector3(dx, dy, dz)


## Writes into out (6 ints) the unwrapped broadphase cells (lo x, y, z, hi x, y, z)
## covering projectile k's path over dt (s) from its current position, padded by reach
## (m), for a cell size (m).
func cell_box(k: int, dt: float, reach: float, cell: float, out: PackedInt32Array) -> void:
	var v: Vector3 = vel[k]
	var ex: float = pos_x[k] + v.x * dt
	var ey: float = pos_y[k] + v.y * dt
	var ez: float = pos_z[k] + v.z * dt
	out[0] = floori((minf(pos_x[k], ex) - reach) / cell)
	out[1] = floori((minf(pos_y[k], ey) - reach) / cell)
	out[2] = floori((minf(pos_z[k], ez) - reach) / cell)
	out[3] = floori((maxf(pos_x[k], ex) + reach) / cell)
	out[4] = floori((maxf(pos_y[k], ey) + reach) / cell)
	out[5] = floori((maxf(pos_z[k], ez) + reach) / cell)


## A ship's run reset drops its projectiles (FT-MIS-017); add_ship adds none.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	remove_rows(rows_of(ship_id))
