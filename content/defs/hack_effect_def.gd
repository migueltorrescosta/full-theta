class_name HackEffectDef
extends Resource
## What a successful hack does to the chosen subsystem, by subsystem kind (FT-SCI-008, P7):
## its effectiveness is multiplied by `factor` for `window_s` seconds. The window is at
## least MIN_WINDOW_S so a spoken relay to Weapons fits (FT-PAIR-023).

## Shortest hack window (s).
const MIN_WINDOW_S: float = 8.0

## Unique within the science definition (dimensionless id).
@export var id: StringName = &""
## The kind of subsystem this effect applies to (enum SubsystemDef.Kind).
@export var subsystem_kind: SubsystemDef.Kind = SubsystemDef.Kind.ENGINES
## Effectiveness multiplier while the window is open (dimensionless, 0 = knocked out).
@export var factor: float = 0.0
## Length of the window (s), at least MIN_WINDOW_S.
@export var window_s: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.in_range(errors, "factor", factor, 0.0, 1.0)
	if not window_s >= MIN_WINDOW_S:
		errors.append("window_s: must be >= %s, got %s" % [MIN_WINDOW_S, window_s])
	return errors
