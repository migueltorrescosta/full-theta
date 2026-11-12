class_name SensorSweepCommand
extends SimCommand
## Science fires a sensor sweep (noise drops for a while). See ScienceSystem.sweep.


func kind() -> StringName:
	return &"sensor_sweep"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.sweep(world, ship_id)
