class_name MapDef
extends Resource
## STUB until strand B merges (#10): B's content/defs/map_def.gd replaces this file. Holds
## only the fields strand A reads (contracts.md section 2). Delete with tests/stubs/.

@export var id: StringName = &""
@export var period_m: float = 400000.0
@export var known_at_start: Array[StringName] = []
@export var spawnable: Array[StringName] = []
