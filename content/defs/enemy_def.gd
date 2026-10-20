class_name EnemyDef
extends Resource
## An enemy: a ship plus M1 AI behaviour (attack, keep range, retreat; FT-SIM-027).
## Units are SI (FT-SIM-033, FT-DAT-013).

## Unique among enemies (dimensionless id).
@export var id: StringName = &""
## Name shown to players.
@export var display_name: String = ""
## The ship it flies (required).
@export var ship: ShipDef
## Closest range the AI keeps to its target (m).
@export var engage_range_min: float = 0.0
## Farthest range the AI fires from (m).
@export var engage_range_max: float = 0.0
## Hull fraction below which the AI retreats (dimensionless, in (0, 1)).
@export var retreat_hull_fraction: float = 0.0
## Half-angle off the bow within which the AI fires (rad, in (0, pi]).
@export var fire_cone: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.required(errors, "ship", ship)
	DefCheck.positive(errors, "engage_range_min", engage_range_min)
	if not engage_range_max > engage_range_min:
		errors.append(
			(
				"engage_range_max: must be > engage_range_min (%s), got %s"
				% [engage_range_min, engage_range_max]
			)
		)
	if not (retreat_hull_fraction > 0.0 and retreat_hull_fraction < 1.0):
		errors.append("retreat_hull_fraction: must be in (0, 1), got %s" % retreat_hull_fraction)
	DefCheck.in_range_open_low(errors, "fire_cone", fire_cone, 0.0, PI)
	return errors
