class_name WreckTable
extends SimTable
## Wrecks of destroyed AI ships (gp-11, #38 D7): one row per wreck, keyed by the destroyed
## ship and its faction, added by SalvageSystem and never removed. A wreck holds
## RunDef.salvage credits (times the run modifier) for the first crewed ship that comes
## within RunDef.salvage_range of it before it is gone (RunDef.salvage_lifetime).

## Where the wreck lies (a CubePoint's three coordinates, m).
var x: PackedFloat64Array = PackedFloat64Array()
var y: PackedFloat64Array = PackedFloat64Array()
var z: PackedFloat64Array = PackedFloat64Array()
## Credits it holds, the last tick it can be collected and the ship that collected it (-1).
var value: PackedInt32Array = PackedInt32Array()
var until_tick: PackedInt32Array = PackedInt32Array()
var taken_by: PackedInt32Array = PackedInt32Array()


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Adds a wreck of `ship` at `at` holding `credits` until `until`; returns its row.
func add_wreck(ship: int, faction: int, at: PackedFloat64Array, credits: int, until: int) -> int:
	var row: int = add_key(ship, faction)
	x.append(at[0])
	y.append(at[1])
	z.append(at[2])
	value.append(credits)
	until_tick.append(until)
	taken_by.append(-1)
	return row


## Wrecks are run history, like encounters: a ship reset leaves them alone.
func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass
