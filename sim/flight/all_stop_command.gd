class_name AllStopCommand
extends SimCommand
## Latches all-stop (FT-SIM-036, FT-HLM-014): assist brings velocity relative to the
## site and rotation to zero through real thrust, and the throttle setpoint to 0. It ends
## at rest or on manual input (AssistSystem).


func kind() -> StringName:
	return &"helm_all_stop"


func apply(world: SimWorld) -> bool:
	world.helm.all_stop[ship_id] = 1
	world.helm.throttle_setpoint[ship_id] = 0.0
	world.helm.level[ship_id] = HelmTable.Level.OFF
	return true
