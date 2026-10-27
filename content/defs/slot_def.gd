class_name SlotDef
extends Resource
## A group of identical module slots a ship has (FT-DAT-014, D86): `count` slots that take
## modules of `slot_type`. Read-only at runtime (FT-ARC-020).

## What fits: a ModuleDef.slot_type (for example &"engine", &"utility").
@export var slot_type: StringName = &""
## Slots of that type (count).
@export var count: int = 0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "slot_type", slot_type)
	DefCheck.in_range(errors, "count", count, 1, 8)
	return errors
