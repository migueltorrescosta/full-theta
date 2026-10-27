class_name EconomyTable
extends SimTable
## Credits per ship (FT-MIS-018, D34). One row per ship, so the row is the ship id.
## Ammunition, propellant, spare parts and probes stay in the tables that spend them
## (MountTable, Kinematics, DamageTable, RelayTable); Economy.of_ship reads them all.
## A run reset (FT-MIS-011) sets the credits back to 0.

var credits: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	credits.append(0)


func columns() -> Array:
	return super() + [["credits", credits]]
