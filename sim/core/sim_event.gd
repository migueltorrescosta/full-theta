class_name SimEvent
extends RefCounted
## A tick-stamped simulation event (FT-SIM-030), keyed by the ship it concerns and that
## ship's faction (FT-ARC-012). `kind` names the event (for example &"hit",
## &"fault", &"shield_low", &"proximity", &"outcome"); the other fields are optional.

var tick: int = 0
var kind: StringName = &""
var ship_id: int = -1
var faction: int = -1
## Another ship, projectile or subsystem the event involves, or -1.
var other_id: int = -1
var value: float = 0.0
## A point or direction, in the ship's frame unless the event says otherwise.
var vector: Vector3 = Vector3.ZERO
var tag: StringName = &""
## A value copy of the arguments of a spoken line (&"say"); not hashed.
var args: Dictionary = {}


func _to_string() -> String:
	return (
		"%d %s ship %d/%d other %d %s %s %s"
		% [tick, kind, ship_id, faction, other_id, value, vector, tag]
	)
