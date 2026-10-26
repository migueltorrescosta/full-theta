class_name Gunnery
extends RefCounted
## Shared pieces of the Weapons-side pair scenarios (P2, P6, P7, Hack alpha): ship
## variants with several mounts, damage accounting and the scripted gunner. The gunner
## submits the commands a Weapons station sends (aim, fire, ammunition); it reads only
## what a gunner sees: the target's position, its own mounts' cooldown, heat and arc,
## and the weapons energy store. Definitions are read-only (FT-ARC-020), so variants are
## copies.

## Barrel is on the aim when within this angle of it (rad, about 1 degree).
const ON_AIM: float = 0.02
## Aim again every this many ticks.
const AIM_EVERY: int = 3
## Cooldown below this counts as ready (s).
const READY: float = 1e-9


## The M1 corvette with `count` copies of its bow mount (all at the bow, same arc), each
## with `alt_weapons` as further ammunition types.
static func gunship(count: int, alt_weapons: Array[WeaponDef] = []) -> ShipDef:
	var ship: ShipDef = TestDefs.corvette().duplicate()
	var mounts: Array[MountDef] = []
	for i: int in count:
		var m: MountDef = TestDefs.corvette().mounts[0].duplicate()
		m.id = StringName("m%d" % i)
		m.alt_weapons = alt_weapons
		mounts.append(m)
	ship.mounts = mounts
	return ship


## The M1 raider as a copy with the given shield strength (J) and no other change.
static func raider_with_shields(max_strength: float) -> ShipDef:
	var ship: ShipDef = TestDefs.raider().duplicate()
	var shields: ShieldDef = ship.shields.duplicate()
	shields.max_strength = max_strength
	ship.shields = shields
	return ship


## Hull and subsystem health the ship has lost (J).
static func lost(w: SimWorld, ship: int) -> float:
	var def: ShipDef = w.defs[ship]
	var h: int = w.damage.hull_row(ship)
	var total: float = def.hull_max - w.damage.health[h]
	for i: int in def.subsystems.size():
		total += def.subsystems[i].health_max - w.damage.health[h + 1 + i]
	return total


## Site-local position of a point of the ship given in its own frame (m).
static func site_point(w: SimWorld, ship: int, local: Vector3) -> Vector3:
	var at: Vector3 = w.kin.to_world(ship, local)
	return Vector3(w.kin.px[ship] + at.x, w.kin.py[ship] + at.y, w.kin.pz[ship] + at.z)


## The gunner's tick: aims every mount at `point` (a position, m; the lead
## point for a moving target) every AIM_EVERY ticks and fires each mount that is ready,
## has the aim inside its arc and the barrel on it, and has the energy for a shot.
static func gun(w: SimWorld, ship: int, point: Vector3) -> void:
	var rel: Vector3 = w.kin.relative_to_point(ship, point.x, point.y, point.z)
	var mounts: MountTable = w.mounts
	var def: ShipDef = w.defs[ship]
	for m: int in def.mounts.size():
		var row: int = mounts.row_for(ship, m)
		var mount: MountDef = def.mounts[m]
		if w.tick % AIM_EVERY == 0:
			var aim: AimMountCommand = AimMountCommand.new()
			aim.ship_id = ship
			aim.mount_index = m
			aim.aim_x = point.x
			aim.aim_y = point.y
			aim.aim_z = point.z
			w.submit(aim)
		var dir: Vector3 = (w.kin.to_local(ship, rel) - mount.position).normalized()
		var weapon: WeaponDef = WeaponSystem.weapon_of(w, row)
		var ready: bool = (
			mounts.cooldown[row] <= READY
			and mounts.locked[row] == 0
			and mounts.ammo[row] != 0
			and mounts.heat[row] < weapon.heat_limit
			and WeaponSystem.in_arc(mount, dir)
			and mounts.barrel[row].angle_to(dir) < ON_AIM
			and w.power.weapon_energy[ship] >= weapon.energy_per_shot
		)
		if ready:
			var fire: FireCommand = FireCommand.new()
			fire.ship_id = ship
			fire.mount_index = m
			w.submit(fire)
