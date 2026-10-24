class_name SetAmmoTypeCommand
extends SimCommand
## Switches a mount to another ammunition type (FT-WPN-006): 0 is MountDef.weapon, i is
## alt_weapons[i - 1]. Each type keeps its own rounds; heat, cooldown and an overheat
## lock stay with the mount. Rejects an unknown mount or type.

var mount_index: int = 0
var ammo_type: int = 0


func kind() -> StringName:
	return &"set_ammo_type"


func apply(world: SimWorld) -> bool:
	var row: int = world.mounts.row_for(ship_id, mount_index)
	if row < 0:
		return false
	var m: MountTable = world.mounts
	var stock: PackedInt32Array = m.type_ammo[row]
	if ammo_type < 0 or ammo_type >= stock.size():
		return false
	if ammo_type != m.ammo_type[row]:
		stock[m.ammo_type[row]] = m.ammo[row]
		m.ammo[row] = stock[ammo_type]
		m.type_ammo[row] = stock
		m.ammo_type[row] = ammo_type
	return true
