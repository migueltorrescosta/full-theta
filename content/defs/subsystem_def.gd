class_name SubsystemDef
extends Resource
## A ship subsystem: health, damage curve, repair and power/heat (FT-SIM-020, FT-SIM-021,
## FT-SIM-024, FT-SIM-026). Units are SI (FT-SIM-033, FT-DAT-013). Heat is a temperature
## rise above the subsystem's nominal operating temperature, in kelvin.

enum Kind { ENGINES, THRUSTERS, WEAPONS, SHIELDS, SENSORS, REACTOR }

## Unique within the ship (dimensionless id).
@export var id: StringName = &""
## What the subsystem drives (enum Kind, dimensionless).
@export var kind: Kind = Kind.ENGINES
## Position in the ship frame (m; Godot axes, -Z is the bow). Hull hits damage the
## nearest subsystem (FT-SIM-020).
@export var position: Vector3 = Vector3.ZERO
## Health when undamaged (J: damage is energy, like hull).
@export var health_max: float = 0.0
## Effectiveness against health (dimensionless): (health fraction, effectiveness) points,
## both in [0, 1], x strictly ascending from 0 to 1, linear in between
## (FT-SIM-021).
@export var effectiveness: PackedVector2Array = PackedVector2Array()
## Health restored per assigned repair crew (J/s per crew).
@export var repair_rate: float = 0.0
## Spare parts one repair consumes (count, FT-SIM-024).
@export var parts_per_repair: int = 0
## Power pips at nominal load (count); pips above this overcharge (FT-SIM-026).
@export var nominal_pips: int = 0
## Heating rate per overcharged pip (K/s).
@export var heat_per_overcharge_pip: float = 0.0
## Cooling rate constant: heat decays as dT/dt = -heat_dissipation * T (1/s).
@export var heat_dissipation: float = 0.0
## Heat above which the subsystem faults (K, FT-SIM-026).
@export var fault_heat_threshold: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.positive(errors, "health_max", health_max)
	_validate_curve(errors)
	DefCheck.non_negative(errors, "repair_rate", repair_rate)
	DefCheck.non_negative(errors, "parts_per_repair", parts_per_repair)
	DefCheck.non_negative(errors, "nominal_pips", nominal_pips)
	DefCheck.non_negative(errors, "heat_per_overcharge_pip", heat_per_overcharge_pip)
	DefCheck.non_negative(errors, "heat_dissipation", heat_dissipation)
	DefCheck.positive(errors, "fault_heat_threshold", fault_heat_threshold)
	return errors


func _validate_curve(errors: Array[String]) -> void:
	var n: int = effectiveness.size()
	if n < 2:
		errors.append("effectiveness: needs at least 2 points, got %d" % n)
		return
	if effectiveness[0].x != 0.0 or effectiveness[n - 1].x != 1.0:
		errors.append("effectiveness: x must run from 0 to 1")
	for i: int in n:
		var p: Vector2 = effectiveness[i]
		if i > 0 and not p.x > effectiveness[i - 1].x:
			errors.append("effectiveness: x must be strictly ascending at point %d" % i)
		if not (p.y >= 0.0 and p.y <= 1.0):
			errors.append("effectiveness: y must be in [0, 1] at point %d" % i)
