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
## Damage a heat fault does to the subsystem when heat passes the threshold (J,
## FT-SIM-026).
@export var heat_fault_damage: float = 0.0
## Whether this subsystem is a weak point: hits aimed at it once a scan has revealed
## it damage it directly (FT-SIM-023, FT-SCI-003).
@export var weak_point: bool = false
## Share of a hit's energy past the shields that a revealed weak point takes, in place
## of the ship's subsystem_damage_share (dimensionless, 0..1; FT-SIM-023). Only read
## when weak_point is set.
@export var weak_point_share: float = 0.0
## Causes a fault on this subsystem may have (ids; FT-SIM-025). Engineering picks one;
## the right pick repairs at full rate. Empty: the subsystem has no unknown-cause fault.
@export var fault_causes: Array[StringName] = []
## Repair speed of a fault whose cause is unknown or guessed wrong, as a share of
## repair_rate (dimensionless, in (0, 1]; FT-SIM-025). PROVISIONAL default.
@export var fault_brute_force_factor: float = 0.25
## Damage taken while hardened, as a multiple (dimensionless, in (0, 1]; FT-ENG-008).
## PROVISIONAL default.
@export var harden_factor: float = 0.5
## How long a hardening lasts (s). PROVISIONAL default.
@export var harden_duration: float = 30.0
## Spare parts hardening consumes (count). PROVISIONAL default.
@export var harden_parts: int = 1


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.positive(errors, "health_max", health_max)
	DefCheck.curve(errors, "effectiveness", effectiveness, 1.0, 1.0)
	DefCheck.non_negative(errors, "repair_rate", repair_rate)
	DefCheck.non_negative(errors, "parts_per_repair", parts_per_repair)
	DefCheck.non_negative(errors, "nominal_pips", nominal_pips)
	DefCheck.non_negative(errors, "heat_per_overcharge_pip", heat_per_overcharge_pip)
	DefCheck.non_negative(errors, "heat_dissipation", heat_dissipation)
	DefCheck.positive(errors, "fault_heat_threshold", fault_heat_threshold)
	DefCheck.non_negative(errors, "heat_fault_damage", heat_fault_damage)
	if weak_point:
		DefCheck.in_range_open_low(errors, "weak_point_share", weak_point_share, 0.0, 1.0)
	DefCheck.in_range_open_low(
		errors, "fault_brute_force_factor", fault_brute_force_factor, 0.0, 1.0
	)
	DefCheck.in_range_open_low(errors, "harden_factor", harden_factor, 0.0, 1.0)
	DefCheck.positive(errors, "harden_duration", harden_duration)
	DefCheck.non_negative(errors, "harden_parts", harden_parts)
	return errors
