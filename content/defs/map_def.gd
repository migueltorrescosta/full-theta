class_name MapDef
extends Resource
## STUB until strand B merges (#10): B's content/defs/map_def.gd replaces this file (on
## merge take B's). Holds only the fields strand A reads (contracts.md section 2).

@export var id: StringName = &""
## Side of the wrapping cube (m, D229).
@export var period_m: float = 400000.0
@export var known_at_start: Array[StringName] = []
@export var spawnable: Array[StringName] = []
