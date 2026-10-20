class_name SimCommand
extends RefCounted
## A typed command for one ship (FT-ARC-005, FT-ARC-008). Stations and the enemy AI
## emit the same command classes (FT-SIM-027). Commands queue on the World and apply
## at the start of the next tick, in submission order; the World stamps the tick.
## Subclasses keep their parameters in plain typed script variables, which to_dict()
## and SimCommands.from_dict() round-trip for the command log (FT-ARC-008).

## CREW: a station; AI: the enemy AI (regenerated on replay, not logged); SERVER: the
## run itself, e.g. a per-ship reset (logged like CREW).
enum Source { CREW, AI, SERVER }

var ship_id: int = -1
## Tick the command was applied on; -1 until applied.
var tick: int = -1
var source: Source = Source.CREW
## Whether apply() accepted it; set when applied. The log keeps rejected crew commands
## too, so a replay re-emits their rejection events (e.g. &"repair_no_parts").
var accepted: bool = false


## Stable name used in the command log; subclasses override.
func kind() -> StringName:
	return &""


## Applies the command; returns false to reject it (crew commands are logged either way,
## with the result in `accepted`).
func apply(_world: SimWorld) -> bool:
	return false


## Whether it applies to a destroyed ship; the World drops other commands for one.
func applies_to_destroyed() -> bool:
	return false


func to_dict() -> Dictionary:
	var d: Dictionary = {"kind": kind()}
	for p: Dictionary in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["name"] != "source":
			d[p["name"]] = get(p["name"])
	return d


func set_from_dict(d: Dictionary) -> void:
	for k: Variant in d:
		if k != "kind":
			set(k, d[k])
