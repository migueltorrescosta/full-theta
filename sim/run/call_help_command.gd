class_name CallHelpCommand
extends SimCommand
## Comms calls for help (gp-14): once per encounter, a civil patrol arrives after the run's
## CallHelpDef.delay. See CallHelp.


func kind() -> StringName:
	return &"comms_call_help"


func apply(world: SimWorld) -> bool:
	return CallHelp.call_help(world, ship_id)
