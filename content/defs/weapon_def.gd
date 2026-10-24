class_name WeaponDef
extends Resource
## A projectile weapon (FT-SIM-012, FT-SIM-013). Units are SI (FT-SIM-033, FT-DAT-013).

## Unique among weapons (dimensionless id).
@export var id: StringName = &""
## Name shown to players.
@export var display_name: String = ""
## Muzzle speed relative to the firing ship (m/s).
@export var projectile_speed: float = 0.0
## Swept-sphere collision radius of a projectile (m, FT-SIM-009).
@export var projectile_radius: float = 0.0
## Distance after which a projectile expires (m).
@export var max_range: float = 0.0
## Minimum time between shots (s).
@export var cooldown: float = 0.0
## Damage per hit (J), the same unit as hull and subsystem health.
@export var damage: float = 0.0
## Rounds carried (count); -1 means unlimited.
@export var ammo_capacity: int = 0
## Reactor energy drawn per shot (J).
@export var energy_per_shot: float = 0.0
## Temperature rise of the weapon per shot (K, FT-SIM-012).
@export var heat_per_shot: float = 0.0
## Cooling rate constant: weapon heat decays as dT/dt = -heat_dissipation * T (1/s).
@export var heat_dissipation: float = 0.0
## The weapon won't fire while its heat is at or above this (K, FT-SIM-012).
@export var heat_limit: float = 0.0
## Damage type, matched against the target's resistances (FT-SIM-022; M2 #9 strand C
## defines the set and its effect).
@export var damage_type: StringName = &"kinetic"


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.positive(errors, "projectile_speed", projectile_speed)
	DefCheck.positive(errors, "projectile_radius", projectile_radius)
	DefCheck.positive(errors, "max_range", max_range)
	DefCheck.positive(errors, "cooldown", cooldown)
	DefCheck.positive(errors, "damage", damage)
	if ammo_capacity < -1:
		errors.append("ammo_capacity: must be >= 0 or -1 (unlimited), got %d" % ammo_capacity)
	DefCheck.non_negative(errors, "energy_per_shot", energy_per_shot)
	DefCheck.non_negative(errors, "heat_per_shot", heat_per_shot)
	DefCheck.non_negative(errors, "heat_dissipation", heat_dissipation)
	DefCheck.positive(errors, "heat_limit", heat_limit)
	return errors
