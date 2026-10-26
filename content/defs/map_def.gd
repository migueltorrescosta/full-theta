class_name MapDef
extends Resource
## STUB until strand B merges (#10): B's content/defs/map_def.gd replaces this file (merge: take B's). Holds
## only the fields strand A reads (contracts.md section 2). Take strand B's file on merge.

@export var id: StringName = &""
@export var period_m: float = 400000.0
@export var known_at_start: Array[StringName] = []
@export var spawnable: Array[StringName] = []
