class_name HazardDef
extends Resource
## A hazard of the sim (D208, FT-RLY-004, P4, P11): a static zone that damages and drags
## the ships inside it, or a moving front (a plane or an expanding sphere shell) that hits
## each ship it crosses once. Read-only at runtime (FT-ARC-020); HazardSystem plays it.
## Units are SI (FT-DAT-013).

## ZONE: a sphere at rest. FRONT: a surface moving at `speed` from `start_s`.
enum Kind { ZONE, FRONT }
## A front's surface: PLANE travels along `direction` with `center` on it at the start;
## SPHERE is a shell around `center` whose radius grows from `radius` at `speed`.
enum Shape { SPHERE, PLANE }

## Unique among hazards (dimensionless id).
@export var id: StringName = &""
@export var kind: Kind = Kind.ZONE
@export var shape: Shape = Shape.SPHERE
## Point (m): a zone's or sphere's centre, a plane front's point at the start.
@export var center: Vector3 = Vector3.ZERO
## A zone's radius, a sphere front's radius at the start (m).
@export var radius: float = 0.0
## A plane front's direction of travel (dimensionless unit vector).
@export var direction: Vector3 = Vector3(0.0, 0.0, 1.0)
## A front's speed (m/s).
@export var speed: float = 0.0
## A front sets off at this time (s since the run started) ...
@export var start_s: float = 0.0
## ... and fades this long after (s); 0 never fades.
@export var duration_s: float = 0.0
## A zone's damage to each ship inside, per second (J/s).
@export var damage_w: float = 0.0
## A front's damage to each ship it crosses, once (J).
@export var hit_j: float = 0.0
## A zone's drag: the share of the ship's velocity it removes per second (1/s).
@export var drag: float = 0.0
## The subsystems the damage goes to, by id (it goes to the hull when empty).
@export var targets: Array[StringName] = []
## How close the own sensors must be to the hazard's surface to know of it (m); a probe's
## bubble (ShipDef.probe_range) shows it from further.
@export var detect_range: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.non_negative(errors, "detect_range", detect_range)
	DefCheck.non_negative(errors, "damage_w", damage_w)
	DefCheck.non_negative(errors, "hit_j", hit_j)
	DefCheck.non_negative(errors, "drag", drag)
	DefCheck.non_negative(errors, "start_s", start_s)
	DefCheck.non_negative(errors, "duration_s", duration_s)
	DefCheck.non_negative(errors, "speed", speed)
	if kind == Kind.ZONE:
		DefCheck.positive(errors, "radius", radius)
	elif shape == Shape.PLANE:
		DefCheck.positive(errors, "speed", speed)
		DefCheck.unit_vector(errors, "direction", direction)
	else:
		DefCheck.positive(errors, "speed", speed)
		DefCheck.non_negative(errors, "radius", radius)
	return errors


## Whether the hazard is a front.
func is_front() -> bool:
	return kind == Kind.FRONT
