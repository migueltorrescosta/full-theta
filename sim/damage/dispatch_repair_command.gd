class_name DispatchRepairCommand
extends SimCommand
## Engineering sends a repair crew to a subsystem (FT-SIM-024, FT-ENG-004); the job
## takes the subsystem's parts_per_repair from stock. See DamageSystem.dispatch.

## Crew number, 0..ShipDef.repair_crews-1.
var crew: int = 0
var subsystem_id: StringName = &""


func kind() -> StringName:
	return &"dispatch_repair"


func apply(world: SimWorld) -> bool:
	return DamageSystem.dispatch(world, ship_id, crew, subsystem_id)
