class_name MountTable
extends SimTable
## Weapon mount state, one row per mount in the ShipDef's order, keyed by ship id and
## faction (FT-ARC-012) plus the mount's index in ShipDef.mounts (T032, FT-SIM-011).
## The definition's MountDef and WeaponDef stay read-only; state starts from them.

## Index of the mount in ShipDef.mounts.
var mount_index: PackedInt32Array = PackedInt32Array()
## Current barrel direction, ship frame (unit vector); starts at MountDef.forward.
var barrel: PackedVector3Array = PackedVector3Array()
## 1 once an aim point has been set (AimMountCommand); until then the barrel rests.
var aim_set: PackedByteArray = PackedByteArray()
## Aim point, 64-bit offsets (m, D104), held in world space while the ship
## turns (FT-WPN-009).
var aim_x: PackedFloat64Array = PackedFloat64Array()
var aim_y: PackedFloat64Array = PackedFloat64Array()
var aim_z: PackedFloat64Array = PackedFloat64Array()
## Time until the weapon can fire again (s).
var cooldown: PackedFloat64Array = PackedFloat64Array()
## Rounds left; -1 means unlimited.
var ammo: PackedInt32Array = PackedInt32Array()
## Weapon temperature above ambient (K).
var heat: PackedFloat64Array = PackedFloat64Array()
## 1 when a FireCommand asked for a shot this tick.
var fire_requested: PackedByteArray = PackedByteArray()
## Selected ammunition type: 0 is MountDef.weapon, i is alt_weapons[i - 1] (FT-WPN-006).
var ammo_type: PackedInt32Array = PackedInt32Array()
## Rounds of each ammunition type, by type index. The selected type's entry is stale:
## `ammo` is its count while it is selected (SetAmmoTypeCommand swaps them).
var type_ammo: Array[PackedInt32Array] = []
## 1 while an overheated mount is locked: set when a shot of a beam takes heat to its
## limit, cleared when heat falls to WeaponDef.overheat_release of it (P6).
var locked: PackedByteArray = PackedByteArray()
## Guided shot requested with fire_requested: the tracked contact to follow (ship id) or
## -1 (FT-WPN-008).
var guide_target: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	for m: int in def.mounts.size():
		var mount: MountDef = def.mounts[m]
		add_key(ship_id, faction)
		mount_index.append(m)
		barrel.append(mount.forward)
		aim_set.append(0)
		aim_x.append(0.0)
		aim_y.append(0.0)
		aim_z.append(0.0)
		cooldown.append(0.0)
		ammo.append(mount.weapon.ammo_capacity)
		heat.append(0.0)
		fire_requested.append(0)
		ammo_type.append(0)
		var stock: PackedInt32Array = PackedInt32Array()
		for w: WeaponDef in mount.ammo_types():
			stock.append(w.ammo_capacity)
		type_ammo.append(stock)
		locked.append(0)
		guide_target.append(-1)


## Row of the ship's mount, or -1 if the ship has no such mount.
func row_for(ship_id: int, index: int) -> int:
	var first: int = row_of(ship_id)
	if first < 0 or index < 0:
		return -1
	var r: int = first + index
	if r >= size() or ship_ids[r] != ship_id:
		return -1
	return r


func columns() -> Array:
	return (
		super()
		+ [
			["mount_index", mount_index],
			["barrel", barrel],
			["aim_set", aim_set],
			["aim_x", aim_x],
			["aim_y", aim_y],
			["aim_z", aim_z],
			["cooldown", cooldown],
			["ammo", ammo],
			["heat", heat],
			["fire_requested", fire_requested],
			["ammo_type", ammo_type],
			["type_ammo", type_ammo],
			["locked", locked],
			["guide_target", guide_target],
		]
	)
