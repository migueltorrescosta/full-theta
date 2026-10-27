class_name ApiEvent
extends RefCounted
## A value copy of one sim event or accepted crew command, for scenarios (FT-ARC-016,
## FT-DAT-009): the same fields as SimEvent without the vector and the arguments.

var tick: int = 0
var kind: StringName = &""
var ship_id: int = -1
var other_id: int = -1
var value: float = 0.0
var tag: StringName = &""
