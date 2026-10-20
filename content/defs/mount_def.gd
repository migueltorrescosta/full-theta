class_name MountDef
extends Resource
## A weapon mount on the hull (FT-SIM-011, FT-SIM-012). Units are SI (FT-SIM-033,
## FT-DAT-013).

## Unique within the ship (dimensionless id).
@export var id: StringName = &""
## Mount position in the ship frame (m; -Z is the bow).
@export var position: Vector3 = Vector3.ZERO
## Rest direction in the ship frame (dimensionless unit vector).
@export var forward: Vector3 = Vector3.ZERO
## Half-angle of the firing cone around forward (rad, in (0, pi]).
@export var arc_half_angle: float = 0.0
## Maximum traverse rate (rad/s); 0 means a fixed mount.
@export var traverse_rate: float = 0.0
## Weapon fitted to the mount (required).
@export var weapon: WeaponDef
## Id of the ship subsystem whose condition gates firing (FT-SIM-012); must name one
## of the ship's subsystems (checked by ShipDef.validate).
@export var subsystem_id: StringName = &""


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.unit_vector(errors, "forward", forward)
	DefCheck.in_range_open_low(errors, "arc_half_angle", arc_half_angle, 0.0, PI)
	DefCheck.non_negative(errors, "traverse_rate", traverse_rate)
	DefCheck.required(errors, "weapon", weapon)
	DefCheck.id(errors, "subsystem_id", subsystem_id)
	return errors
