class_name HelpTable
extends SimTable
## Comms' calls for help (gp-14, CallHelp), one row per ship keyed by ship id and faction
## (FT-ARC-012): for a crewed ship the encounter it last called in and the seconds until
## its patrol arrives; for a patrol ship the encounter it helps in.

## Encounter id the ship last called for help in, or -1 (once per encounter).
var called: PackedInt32Array = PackedInt32Array()
## Seconds until the called patrol arrives; 0 when none is on its way.
var left: PackedFloat64Array = PackedFloat64Array()
## For a patrol ship, the encounter it helps in (it leaves when that ends), else -1.
var patrol_for: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	called.append(-1)
	left.append(0.0)
	patrol_for.append(-1)


## A relaunch drops a patrol on its way; the call stays spent for that encounter.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	left[ship_id] = 0.0
