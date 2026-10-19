class_name PowerTable
extends SimTable
## Power pips, heat and weapons energy, one row per ship in id order (T030, FT-SIM-006,
## FT-SIM-026). Per-subsystem values are packed arrays in ShipDef.subsystems order.

## Pips Engineering set per subsystem (count); their sum stays within
## PowerDef.reactor_pips (FT-ENG-002). A boost overrides engines and thrusters.
var pips: Array[PackedInt32Array] = []
## Heat per subsystem: temperature rise above nominal (K, FT-SIM-026).
var heat: Array[PackedFloat64Array] = []
## Per subsystem, 1 while a heat fault may fire; 0 after one fired, until the heat falls
## back below PowerSystem.FAULT_REARM of the threshold.
var fault_armed: Array[PackedByteArray] = []
## Ticks of boost left; 0 when not boosting (P1).
var boost_ticks: PackedInt32Array = PackedInt32Array()
## Energy in the weapons store (J), drawn per shot.
var weapon_energy: PackedFloat64Array = PackedFloat64Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	add_key(ship_id, faction)
	var p: PackedInt32Array = PackedInt32Array()
	var h: PackedFloat64Array = PackedFloat64Array()
	var armed: PackedByteArray = PackedByteArray()
	for s: SubsystemDef in def.subsystems:
		p.append(s.nominal_pips)
		h.append(0.0)
		armed.append(1)
	pips.append(p)
	heat.append(h)
	fault_armed.append(armed)
	boost_ticks.append(0)
	weapon_energy.append(def.power.weapons_capacity)


func columns() -> Array:
	return (
		super()
		+ [
			["pips", pips],
			["heat", heat],
			["fault_armed", fault_armed],
			["boost_ticks", boost_ticks],
			["weapon_energy", weapon_energy],
		]
	)
