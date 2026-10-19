class_name PowerTable
extends SimTable
## Boost and weapons energy, one row per ship in id order (T030, FT-SIM-006). Per-subsystem
## power state (pips, heat, fault_armed) lives on the subsystem rows of DamageTable.

## Ticks of boost left; 0 when not boosting (P1).
var boost_ticks: PackedInt32Array = PackedInt32Array()
## Energy in the weapons store (J), drawn per shot.
var weapon_energy: PackedFloat64Array = PackedFloat64Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	add_key(ship_id, faction)
	boost_ticks.append(0)
	weapon_energy.append(def.power.weapons_capacity)


func columns() -> Array:
	return (
		super()
		+ [
			["boost_ticks", boost_ticks],
			["weapon_energy", weapon_energy],
		]
	)
