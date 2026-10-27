class_name ModuleTable
extends SimTable
## Fitted slot modules (FT-MIS-035, FT-DAT-014, D86): one row per slot of a ship, in
## ShipDef.slots order (a group of `count` slots gives `count` rows), holding the fitted
## module as an index into SimWorld.module_defs (-1 empty). Fitting a module is a state
## change here; ModuleSystem.refit derives the ship's effective definition from it.

var slot_type: Array[StringName] = []
## Index into SimWorld.module_defs, or -1 for an empty slot.
var module_ix: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	for group: SlotDef in def.slots:
		for i: int in group.count:
			add_key(ship_id, faction)
			slot_type.append(group.slot_type)
			module_ix.append(-1)


## Row of the ship's slot number `slot` (0-based across its groups), or -1.
func slot_row(ship_id: int, slot: int) -> int:
	var first: int = row_of(ship_id)
	if first < 0 or slot < 0:
		return -1
	var r: int = first + slot
	return r if r < size() and ship_ids[r] == ship_id else -1


func columns() -> Array:
	return super() + [["slot_type", slot_type], ["module_ix", module_ix]]
