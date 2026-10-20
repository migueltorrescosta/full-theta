class_name RecallRepairCommand
extends SimCommand
## Engineering calls a repair crew back from its job (FT-SIM-024); parts already used
## stay used. See DamageSystem.recall.

## Crew number, 0..ShipDef.repair_crews-1.
var crew: int = 0


func kind() -> StringName:
	return &"recall_repair"


func apply(world: SimWorld) -> bool:
	return DamageSystem.recall(world, ship_id, crew)
