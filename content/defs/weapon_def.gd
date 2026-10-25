class_name WeaponDef
extends Resource
## A weapon: projectile gun, energy beam, missile or torpedo (FT-SIM-012, FT-SIM-013).
## Units are SI (FT-SIM-033, FT-DAT-013).

## What the weapon launches. PROJECTILE flies straight; BEAM hits the first ship along
## the barrel at once (no projectile_speed) and overheats the mount (P6); MISSILE and
## TORPEDO are guided ordnance that steer at turn_rate toward a tracked contact or a
## point (FT-WPN-008, P8).
enum Kind { PROJECTILE, BEAM, MISSILE, TORPEDO }

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
## Damage type, matched against the target's ShipDef.resistances: the hit's energy is
## multiplied by the resistance of its type, 1 when the target lists none (FT-SIM-022).
## The set of types is open; M2's content uses kinetic, thermal and explosive.
@export var damage_type: StringName = &"kinetic"
## What the weapon launches (enum Kind, dimensionless).
@export var kind: Kind = Kind.PROJECTILE
## Guided ordnance only: how fast the velocity direction can turn (rad/s).
@export var turn_rate: float = 0.0
## Beams only: once heat reaches heat_limit after a shot the mount locks until its heat
## has fallen to this share of heat_limit (dimensionless, in (0, 1]; P6). 0 means no
## lock: the weapon just waits for heat to fall below heat_limit.
@export var overheat_release: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if kind != Kind.BEAM:
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
	if is_guided():
		DefCheck.positive(errors, "turn_rate", turn_rate)
	if kind == Kind.BEAM:
		DefCheck.in_range_open_low(errors, "overheat_release", overheat_release, 0.0, 1.0)
	return errors


## Missiles and torpedoes.
func is_guided() -> bool:
	return kind == Kind.MISSILE or kind == Kind.TORPEDO
