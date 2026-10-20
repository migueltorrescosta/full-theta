class_name PowerDef
extends Resource
## Reactor and power pips (FT-SIM-006, FT-SIM-026). Units are SI (FT-SIM-033,
## FT-DAT-013).

## Total pips the reactor supplies to all subsystems (count). A boost may exceed it for
## boost_duration.
@export var reactor_pips: int = 0
## Most pips one subsystem may take, overcharge included (count).
@export var max_pips_per_subsystem: int = 0
## Reactor electrical output at full load (W). Each subsystem's share is its pips over
## reactor_pips; the weapons share charges the weapons energy store.
@export var reactor_output: float = 0.0
## Thrust envelope against power (dimensionless): (pips / nominal pips, envelope scale)
## points, x strictly ascending from 0, linear in between and clamped past the ends;
## must contain (1, 1) so nominal pips give the full nominal envelope (FT-SIM-006).
@export var envelope_curve: PackedVector2Array = PackedVector2Array()
## Envelope derating against heat (dimensionless): (heat / fault_heat_threshold, factor)
## points, x strictly ascending from 0, factors in [0, 1], linear in between.
@export var heat_derate: PackedVector2Array = PackedVector2Array()
## Length of a boost: engines and thrusters run at max_pips_per_subsystem (s, P1).
@export var boost_duration: float = 0.0
## Weapons energy store capacity, drawn per shot (J, FT-SIM-012).
@export var weapons_capacity: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.positive(errors, "reactor_pips", reactor_pips)
	DefCheck.positive(errors, "max_pips_per_subsystem", max_pips_per_subsystem)
	DefCheck.positive(errors, "reactor_output", reactor_output)
	DefCheck.curve(errors, "envelope_curve", envelope_curve, INF)
	if not envelope_curve.has(Vector2(1, 1)):
		errors.append("envelope_curve: must contain the point (1, 1)")
	DefCheck.curve(errors, "heat_derate", heat_derate, 1.0)
	DefCheck.positive(errors, "boost_duration", boost_duration)
	DefCheck.non_negative(errors, "weapons_capacity", weapons_capacity)
	return errors
