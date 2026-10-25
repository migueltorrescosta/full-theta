class_name ProjectileTable
extends SimTable
## Live projectiles, one row each, keyed by the shooter's ship id and faction
## (FT-ARC-012). Positions are site-local 64-bit offsets like ships' (D104), wrapped
## onto the site's cube (FT-SIM-035); only this class and Kinematics read them
## (tools/lint_arch.py). Velocity is float32 in the site frame. Packed columns keep 500
## projectiles cheap (S6). Rows are appended when a shot is fired and removed when the
## projectile hits or expires, so a ship has no rows at spawn.

var site: PackedInt32Array = PackedInt32Array()
var px: PackedFloat64Array = PackedFloat64Array()
var py: PackedFloat64Array = PackedFloat64Array()
var pz: PackedFloat64Array = PackedFloat64Array()
## Velocity relative to the site (m/s).
var vel: PackedVector3Array = PackedVector3Array()
## Swept-sphere radius (m, FT-SIM-009).
var radius: PackedFloat64Array = PackedFloat64Array()
## Damage energy delivered on a hit (J).
var energy: PackedFloat64Array = PackedFloat64Array()
## Ticks left before the projectile expires.
var ttl: PackedInt32Array = PackedInt32Array()
## Damage type of the hit (FT-SIM-022).
var damage_type: Array[StringName] = []
## Guided ordnance (FT-SIM-013, FT-WPN-008): turn rate (rad/s; 0 flies straight), the
## tracked contact followed (ship id or -1), and a site-local point steered at when
## guide_point is 1. GuidanceSystem steers these each tick.
var turn_rate: PackedFloat64Array = PackedFloat64Array()
var guide_target: PackedInt32Array = PackedInt32Array()
var guide_point: PackedByteArray = PackedByteArray()
var guide_x: PackedFloat64Array = PackedFloat64Array()
var guide_y: PackedFloat64Array = PackedFloat64Array()
var guide_z: PackedFloat64Array = PackedFloat64Array()


## Appends a projectile and returns its row.
func spawn(
	shooter: int,
	faction: int,
	site_id: int,
	x: float,
	y: float,
	z: float,
	velocity: Vector3,
	radius_m: float,
	energy_j: float,
	ttl_ticks: int
) -> int:
	add_key(shooter, faction)
	site.append(site_id)
	px.append(x)
	py.append(y)
	pz.append(z)
	vel.append(velocity)
	radius.append(radius_m)
	energy.append(energy_j)
	ttl.append(ttl_ticks)
	damage_type.append(&"kinetic")
	turn_rate.append(0.0)
	guide_target.append(-1)
	guide_point.append(0)
	guide_x.append(0.0)
	guide_y.append(0.0)
	guide_z.append(0.0)
	return size() - 1


## Gives projectile k its damage type and, when turn_rate_rad is positive, guidance at
## the contact (target >= 0) and/or the site-local point (has_point).
func set_payload(
	k: int,
	type: StringName,
	turn_rate_rad: float = 0.0,
	target: int = -1,
	has_point: bool = false,
	x: float = 0.0,
	y: float = 0.0,
	z: float = 0.0
) -> void:
	damage_type[k] = type
	turn_rate[k] = turn_rate_rad
	guide_target[k] = target
	guide_point[k] = 1 if has_point else 0
	guide_x[k] = x
	guide_y[k] = y
	guide_z[k] = z


## From projectile k to ship s (m, minimum image; the same site).
func offset_to_ship(k: int, kin: Kinematics, s: int) -> Vector3:
	return -kin.relative_to_point(s, px[k], py[k], pz[k])


## From projectile k to its guide point (m, minimum image).
func offset_to_guide_point(k: int, kin: Kinematics) -> Vector3:
	var half: float = 0.5 * kin.period
	var dx: float = guide_x[k] - px[k]
	var dy: float = guide_y[k] - py[k]
	var dz: float = guide_z[k] - pz[k]
	return Vector3(
		dx if dx >= -half and dx < half else kin.wrap(dx),
		dy if dy >= -half and dy < half else kin.wrap(dy),
		dz if dz >= -half and dz < half else kin.wrap(dz)
	)


## Moves projectile k by its velocity for dt (s), wrapping across the site's faces
## (FT-SIM-035).
func advance(k: int, kin: Kinematics, dt: float) -> void:
	var v: Vector3 = vel[k]
	# kin.wrap only off the cube (it returns in-cube values unchanged).
	var half: float = 0.5 * kin.period
	var x: float = px[k] + v.x * dt
	var y: float = py[k] + v.y * dt
	var z: float = pz[k] + v.z * dt
	px[k] = x if x >= -half and x < half else kin.wrap(x)
	py[k] = y if y >= -half and y < half else kin.wrap(y)
	pz[k] = z if z >= -half and z < half else kin.wrap(z)


## Projectile k's position relative to ship s, both taken dt (s) before the ship's
## current position (the ship moving at its current velocity): the start of a tick's
## sweep (m, site frame), by minimum image so shots across a seam hit (FT-SIM-035).
func relative_start(k: int, kin: Kinematics, s: int, dt: float) -> Vector3:
	var vs: Vector3 = kin.vel[s]
	return kin.relative_to_point(s, px[k] + vs.x * dt, py[k] + vs.y * dt, pz[k] + vs.z * dt)


## Writes into out (6 ints) the unwrapped broadphase cells (lo x, y, z, hi x, y, z)
## covering projectile k's path over dt (s) from its current position, padded by reach
## (m), for a cell size (m).
func cell_box(k: int, dt: float, reach: float, cell: float, out: PackedInt32Array) -> void:
	var v: Vector3 = vel[k]
	var ex: float = px[k] + v.x * dt
	var ey: float = py[k] + v.y * dt
	var ez: float = pz[k] + v.z * dt
	out[0] = floori((minf(px[k], ex) - reach) / cell)
	out[1] = floori((minf(py[k], ey) - reach) / cell)
	out[2] = floori((minf(pz[k], ez) - reach) / cell)
	out[3] = floori((maxf(px[k], ex) + reach) / cell)
	out[4] = floori((maxf(py[k], ey) + reach) / cell)
	out[5] = floori((maxf(pz[k], ez) + reach) / cell)


## Removes the given rows (ascending row numbers); the rest keep their order.
func remove_rows(rows: PackedInt32Array) -> void:
	for i: int in range(rows.size() - 1, -1, -1):
		var r: int = rows[i]
		ship_ids.remove_at(r)
		factions.remove_at(r)
		site.remove_at(r)
		px.remove_at(r)
		py.remove_at(r)
		pz.remove_at(r)
		vel.remove_at(r)
		radius.remove_at(r)
		energy.remove_at(r)
		ttl.remove_at(r)
		damage_type.remove_at(r)
		turn_rate.remove_at(r)
		guide_target.remove_at(r)
		guide_point.remove_at(r)
		guide_x.remove_at(r)
		guide_y.remove_at(r)
		guide_z.remove_at(r)


## A ship's run reset drops its projectiles (FT-MIS-017); add_ship adds none.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	remove_rows(rows_of(ship_id))


func columns() -> Array:
	return (
		super()
		+ [
			["site", site],
			["px", px],
			["py", py],
			["pz", pz],
			["vel", vel],
			["radius", radius],
			["energy", energy],
			["ttl", ttl],
			["damage_type", damage_type],
			["turn_rate", turn_rate],
			["guide_target", guide_target],
			["guide_point", guide_point],
			["guide_x", guide_x],
			["guide_y", guide_y],
			["guide_z", guide_z],
		]
	)
