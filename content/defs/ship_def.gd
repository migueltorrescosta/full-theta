class_name ShipDef
extends Resource
## A ship: rigid body, thrust envelope, propellant, hull and fittings (FT-SIM-002,
## FT-SIM-007). Godot axes: -Z is the bow, +Y up, +X starboard. Units are SI
## (FT-SIM-033, FT-DAT-013); hull damage is energy (J), so collisions and weapons share
## a unit. Read-only at runtime: mutable state is copied from it (FT-ARC-020).
## Every definition class defaults its numbers to zero, so a field left out of a .tres
## fails validation instead of silently taking a code default.

## Unique among ships (dimensionless id).
@export var id: StringName = &""
## Name shown to players.
@export var display_name: String = ""
## Dry mass plus full propellant (kg).
@export var mass: float = 0.0
## Diagonal inertia tensor (kg m^2): x pitch, y yaw, z roll.
@export var inertia: Vector3 = Vector3.ZERO
## Maximum thrust along each positive local axis (N): x starboard, y up, z aft (so z
## is retro thrust).
@export var max_thrust_pos: Vector3 = Vector3.ZERO
## Maximum thrust along each negative local axis (N, given as magnitudes): x port,
## y down, z forward (so z is the main drive).
@export var max_thrust_neg: Vector3 = Vector3.ZERO
## Maximum torque about each local axis, either sign (N m): x pitch, y yaw, z roll.
@export var max_torque: Vector3 = Vector3.ZERO
## Propellant carried when full (kg).
@export var propellant_capacity: float = 0.0
## Effective exhaust velocity (m/s): propellant used = impulse / exhaust_velocity.
@export var exhaust_velocity: float = 0.0
## Lever arm that turns torque into the thruster force it costs propellant for (m).
@export var lever_arm: float = 0.0
## Collision capsule radius (m).
@export var radius: float = 0.0
## Collision capsule half-length of the segment along local Z (m); 0 means a sphere.
@export var half_length: float = 0.0
## Hull strength when undamaged (J).
@export var hull_max: float = 0.0
## Spare parts carried for repairs (count, FT-SIM-024).
@export var spare_parts: int = 0
## Repair crews Engineering can dispatch (count, FT-SIM-024; at most 31, one bit each).
@export var repair_crews: int = 0
## Share of a hit's energy past the shields that the subsystem nearest the impact also
## takes, on top of the hull taking all of it (dimensionless, 0..1, FT-SIM-020).
@export var subsystem_damage_share: float = 0.0
## Subsystems (at least one; ids unique within the ship).
@export var subsystems: Array[SubsystemDef] = []
## Weapon mounts (may be empty; ids unique within the ship).
@export var mounts: Array[MountDef] = []
## Flight assist tuning (required).
@export var assist: AssistDef
## Reactor and pips (required).
@export var power: PowerDef
## Shield generator (required).
@export var shields: ShieldDef
## Range at which this ship detects other ships with undamaged sensors (m); scaled by the
## sensors subsystem's effectiveness (FT-ARC-013).
@export var sensor_range: float = 0.0
## Range within which a detected ship's allegiance becomes known to this ship's faction
## (m); scaled like sensor_range, at most sensor_range (FT-SPA-001).
@export var identify_range: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.positive(errors, "mass", mass)
	DefCheck.positive_vector(errors, "inertia", inertia)
	DefCheck.positive_vector(errors, "max_thrust_pos", max_thrust_pos)
	DefCheck.positive_vector(errors, "max_thrust_neg", max_thrust_neg)
	DefCheck.positive_vector(errors, "max_torque", max_torque)
	DefCheck.non_negative(errors, "propellant_capacity", propellant_capacity)
	DefCheck.positive(errors, "exhaust_velocity", exhaust_velocity)
	DefCheck.positive(errors, "lever_arm", lever_arm)
	DefCheck.positive(errors, "radius", radius)
	DefCheck.non_negative(errors, "half_length", half_length)
	DefCheck.positive(errors, "hull_max", hull_max)
	DefCheck.non_negative(errors, "spare_parts", spare_parts)
	DefCheck.in_range(errors, "repair_crews", repair_crews, 0, 31)
	DefCheck.in_range(errors, "subsystem_damage_share", subsystem_damage_share, 0.0, 1.0)
	DefCheck.positive(errors, "sensor_range", sensor_range)
	DefCheck.in_range(errors, "identify_range", identify_range, 0.0, maxf(sensor_range, 0.0))
	DefCheck.required(errors, "assist", assist)
	DefCheck.required(errors, "shields", shields)
	if DefCheck.required(errors, "power", power):
		_validate_pips(errors)
	var ids: Dictionary[StringName, bool] = _validate_subsystems(errors)
	_validate_mounts(errors, ids)
	return errors


## Returns the set of subsystem ids.
func _validate_subsystems(errors: Array[String]) -> Dictionary[StringName, bool]:
	var ids: Dictionary[StringName, bool] = {}
	if subsystems.is_empty():
		errors.append("subsystems: needs at least one subsystem")
	for i: int in subsystems.size():
		var s: SubsystemDef = subsystems[i]
		if not DefCheck.required(errors, "subsystems[%d]" % i, s):
			continue
		if ids.has(s.id):
			errors.append("subsystems[%d].id: duplicate id %s" % [i, s.id])
		if s.id == &"hull":
			errors.append("subsystems[%d].id: hull is reserved for the hull" % i)
		ids[s.id] = true
	return ids


func _validate_mounts(errors: Array[String], subsystem_ids: Dictionary[StringName, bool]) -> void:
	var ids: Dictionary[StringName, bool] = {}
	for i: int in mounts.size():
		var m: MountDef = mounts[i]
		if not DefCheck.required(errors, "mounts[%d]" % i, m):
			continue
		if ids.has(m.id):
			errors.append("mounts[%d].id: duplicate id %s" % [i, m.id])
		ids[m.id] = true
		if not subsystem_ids.has(m.subsystem_id):
			errors.append("mounts[%d].subsystem_id: no subsystem with id %s" % [i, m.subsystem_id])


func _validate_pips(errors: Array[String]) -> void:
	var total: int = 0
	for i: int in subsystems.size():
		var s: SubsystemDef = subsystems[i]
		if s == null:
			continue
		total += s.nominal_pips
		if s.nominal_pips > power.max_pips_per_subsystem:
			errors.append(
				(
					"subsystems[%d].nominal_pips: exceeds power.max_pips_per_subsystem (%d)"
					% [i, power.max_pips_per_subsystem]
				)
			)
	if total > power.reactor_pips:
		errors.append(
			(
				"subsystems: nominal pips total %d exceeds power.reactor_pips (%d)"
				% [total, power.reactor_pips]
			)
		)
