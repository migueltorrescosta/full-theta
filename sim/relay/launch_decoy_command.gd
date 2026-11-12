class_name LaunchDecoyCommand
extends SimCommand
## Relay launches a decoy (gp-13): one probe from stock that draws the hostile NPC AI
## near it for ShipDef.decoy_time. See ProbeSystem.launch_decoy.


func kind() -> StringName:
	return &"launch_decoy"


func apply(world: SimWorld) -> bool:
	return ProbeSystem.launch_decoy(world, ship_id)
