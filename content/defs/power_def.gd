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
	_validate_curve(errors, "envelope_curve", envelope_curve, INF)
	if not envelope_curve.has(Vector2(1, 1)):
		errors.append("envelope_curve: must contain the point (1, 1)")
	_validate_curve(errors, "heat_derate", heat_derate, 1.0)
	DefCheck.positive(errors, "boost_duration", boost_duration)
	DefCheck.non_negative(errors, "weapons_capacity", weapons_capacity)
	return errors


static func _validate_curve(
	errors: Array[String], field: String, curve: PackedVector2Array, y_max: float
) -> void:
	var n: int = curve.size()
	if n < 2:
		errors.append("%s: needs at least 2 points, got %d" % [field, n])
		return
	if curve[0].x != 0.0:
		errors.append("%s: x must start at 0" % field)
	for i: int in n:
		var p: Vector2 = curve[i]
		if i > 0 and not p.x > curve[i - 1].x:
			errors.append("%s: x must be strictly ascending at point %d" % [field, i])
		if not (p.y >= 0.0 and p.y <= y_max):
			errors.append("%s: y must be in [0, %s] at point %d" % [field, y_max, i])
