class_name DamageSystem
extends RefCounted
## Hull and subsystem damage, repair crews (T033). Stub until its task lands.


static func step(_world: SimWorld) -> void:
	pass


## Applies the energy that passed the shields to the hull and nearest subsystem.
static func apply_hit(_world: SimWorld, _hit: SimHit, _energy: float) -> void:
	pass


## Effectiveness of the ship's subsystem, 0..1, from its health and the definition's
## curve (FT-SIM-021); 1 when the ship has no such subsystem.
static func effectiveness(_world: SimWorld, _ship_id: int, _subsystem_id: StringName) -> float:
	return 1.0


## Hull left as a share of hull_max, 0..1.
static func hull_fraction(_world: SimWorld, _ship_id: int) -> float:
	return 1.0


## Damages one subsystem directly (heat faults, FT-SIM-026); cause names the source.
static func damage_subsystem(
	_world: SimWorld, _ship_id: int, _subsystem_id: StringName, _energy: float, _cause: StringName
) -> void:
	pass
