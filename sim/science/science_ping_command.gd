class_name SciencePingCommand
extends SimCommand
## Science fires an active ping (noise drops for a while). See ScienceSystem.ping.


func kind() -> StringName:
	return &"science_ping"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.ping(world, ship_id)
