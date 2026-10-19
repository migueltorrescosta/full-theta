class_name ShieldDef
extends Resource
## Shield generator (FT-SIM-018, FT-SIM-019, FT-SIM-031). Units are SI (FT-SIM-033,
## FT-DAT-013).

## Energy the shield absorbs when full (J).
@export var max_strength: float = 0.0
## Recharge rate at nominal power (J/s).
@export var regen_rate: float = 0.0
## Loosest focus tightness Engineering can set (dimensionless).
@export var tightness_min: float = 0.0
## Tightest focus tightness Engineering can set (dimensionless).
@export var tightness_max: float = 0.0
## Strength fraction that raises Engineering's low-shield alert (dimensionless,
## FT-SIM-031 sets 0.4).
@export var low_alert_fraction: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.positive(errors, "max_strength", max_strength)
	DefCheck.non_negative(errors, "regen_rate", regen_rate)
	DefCheck.non_negative(errors, "tightness_min", tightness_min)
	if not tightness_max > tightness_min:
		errors.append(
			"tightness_max: must be > tightness_min (%s), got %s" % [tightness_min, tightness_max]
		)
	DefCheck.in_range_open_low(errors, "low_alert_fraction", low_alert_fraction, 0.0, 1.0)
	return errors
