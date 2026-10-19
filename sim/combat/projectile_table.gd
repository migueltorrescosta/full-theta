class_name ProjectileTable
extends SimTable
## Live projectiles, one row each, keyed by the shooter's ship id and faction
## (FT-ARC-012). Positions are site-local 64-bit offsets like ships' (D104); velocity
## is float32 in the site frame. Packed columns keep 500 projectiles cheap (S6). Rows
## are appended when a shot is fired and removed when the projectile hits or expires,
## so a ship has no rows at spawn.

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


## A ship's run reset drops its projectiles (FT-GEN-002); add_ship adds none.
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
