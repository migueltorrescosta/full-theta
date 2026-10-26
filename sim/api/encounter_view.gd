class_name EncounterView
extends RefCounted
## A value copy of one encounter (FT-ARC-016, FT-DAT-009, FT-MIS-025).

var id: int = -1
var scenario_id: StringName = &""
var site: int = -1
var ships: PackedInt32Array = PackedInt32Array()
## Scenario.Result value (the same numbers as EncounterTable.Result).
var result: int = 0
var start_tick: int = -1
var end_tick: int = -1
var cost: int = 0
