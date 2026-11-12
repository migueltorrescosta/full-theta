class_name AiTable
extends SimTable
## NPC AI state (T035, FT-SIM-027), one row per ship keyed by ship id and faction
## (FT-ARC-012). Rows start disabled; SimWorld.spawn_npc enables a row and copies the
## NpcDef's behaviour numbers into it (FT-ARC-020: copies, never the definition).
## NpcAi reads the parameters and writes mode and target; nothing else writes here.

## What the AI is doing: HOLD (no hostile contact), ATTACK (closing on a contact beyond
## the engage band), KEEP_RANGE (inside the band or too close: holds the band) and
## RETREAT (hull below the threshold: runs from the threat).
enum Mode { HOLD, ATTACK, KEEP_RANGE, RETREAT }

## Event tags for each Mode, in Mode order.
const MODE_NAMES: Array[StringName] = [&"hold", &"attack", &"keep_range", &"retreat"]

## 1 when the AI flies this ship.
var enabled: PackedByteArray = PackedByteArray()
## NpcDef.engage_range_min (m).
var engage_range_min: PackedFloat64Array = PackedFloat64Array()
## NpcDef.engage_range_max (m).
var engage_range_max: PackedFloat64Array = PackedFloat64Array()
## NpcDef.retreat_hull_fraction (dimensionless).
var retreat_hull_fraction: PackedFloat64Array = PackedFloat64Array()
## NpcDef.fire_cone (rad).
var fire_cone: PackedFloat64Array = PackedFloat64Array()
## Current Mode.
var mode: PackedByteArray = PackedByteArray()
## Ship id of the current target (a detected hostile contact), or -1.
var target: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	enabled.append(0)
	engage_range_min.append(0.0)
	engage_range_max.append(0.0)
	retreat_hull_fraction.append(0.0)
	fire_cone.append(0.0)
	mode.append(Mode.HOLD)
	target.append(-1)


## Hands the ship to the AI with the NPC's behaviour numbers.
func enable(ship_id: int, npc: NpcDef) -> void:
	enabled[ship_id] = 1
	engage_range_min[ship_id] = npc.engage_range_min
	engage_range_max[ship_id] = npc.engage_range_max
	retreat_hull_fraction[ship_id] = npc.retreat_hull_fraction
	fire_cone[ship_id] = npc.fire_cone


func is_enabled(ship_id: int) -> bool:
	return enabled[ship_id] == 1


## The run reset (FT-MIS-017) keeps the ship under AI control with its behaviour
## numbers, which came from the NpcDef rather than the ShipDef, and clears the rest.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	mode[ship_id] = Mode.HOLD
	target[ship_id] = -1
