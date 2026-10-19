class_name PowerDef
extends Resource
## Reactor and power pips (FT-SIM-006, FT-SIM-026). Units are SI (FT-SIM-033,
## FT-DAT-013).

## Total pips the reactor supplies to all subsystems (count).
@export var reactor_pips: int = 0
## Most pips one subsystem may take, overcharge included (count).
@export var max_pips_per_subsystem: int = 0
## Reactor electrical output at full load (W).
@export var reactor_output: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.positive(errors, "reactor_pips", reactor_pips)
	DefCheck.positive(errors, "max_pips_per_subsystem", max_pips_per_subsystem)
	DefCheck.positive(errors, "reactor_output", reactor_output)
	return errors
