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
	return size() - 1


## Moves projectile k by its velocity for dt (s), wrapping across the site's faces
## (FT-SIM-035).
func advance(k: int, kin: Kinematics, dt: float) -> void:
	var v: Vector3 = vel[k]
	var p: PackedFloat64Array = kin.wrap_point(px[k] + v.x * dt, py[k] + v.y * dt, pz[k] + v.z * dt)
	px[k] = p[0]
	py[k] = p[1]
	pz[k] = p[2]


## Projectile k's position relative to ship s, both taken dt (s) before the ship's
## current position (the ship moving at its current velocity): the start of a tick's
## sweep (m, site frame), by minimum image so shots across a seam hit (FT-SIM-035).
func relative_start(k: int, kin: Kinematics, s: int, dt: float) -> Vector3:
	var vs: Vector3 = kin.vel[s]
	return kin.relative_to_point(s, px[k] + vs.x * dt, py[k] + vs.y * dt, pz[k] + vs.z * dt)


## Unwrapped broadphase cells (lo x, y, z, hi x, y, z) covering projectile k's path over
## dt (s) from its current position, padded by reach (m), for a cell size (m).
func cell_box(k: int, dt: float, reach: float, cell: float) -> PackedInt32Array:
	var v: Vector3 = vel[k]
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(6)
	var start: PackedFloat64Array = PackedFloat64Array([px[k], py[k], pz[k]])
	for a: int in 3:
		var end: float = start[a] + v[a] * dt
		out[a] = floori((minf(start[a], end) - reach) / cell)
		out[a + 3] = floori((maxf(start[a], end) + reach) / cell)
	return out


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
		]
	)
