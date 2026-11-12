class_name CallHelpDef
extends Resource
## Comms' call for help (gp-14): once per encounter, during a hostile encounter, a ship may
## call a civil patrol. It costs a reputation draw with the patrol's faction at the call;
## `count` patrol ships arrive `delay` later `distance` off the calling ship's starboard
## side, fight its hostiles and leave when the encounter ends. Read-only at runtime
## (FT-ARC-020).

@export var id: StringName = &""
## The patrol ship (required).
@export var npc: NpcDef
## The patrol's faction (dimensionless id, Factions.CIVIL); the call makes it friendly to the
## caller.
@export var faction: int = 3
## Patrol ships that arrive (count).
@export var count: int = 1
## Seconds from the call to the patrol's arrival (s).
@export var delay: float = 60.0
## How far from the calling ship the patrol arrives (m).
@export var distance: float = 1500.0
## How far apart patrol ships arrive, in a line out from the first (m).
@export var spacing: float = 100.0
## RepDistDef id of the reputation draw with the patrol's faction (FT-MIS-019).
@export var rep_dist: StringName = &""


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.required(errors, "npc", npc)
	if faction < 0:
		errors.append("faction must be at least 0, got %d" % faction)
	if count < 1:
		errors.append("count must be at least 1, got %d" % count)
	DefCheck.positive(errors, "delay", delay)
	DefCheck.positive(errors, "distance", distance)
	DefCheck.positive(errors, "spacing", spacing)
	return errors
