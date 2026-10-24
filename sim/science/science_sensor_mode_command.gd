class_name ScienceSensorModeCommand
extends SimCommand
## Science switches the sensors between passive and active (FT-SCI-003).

var active: bool = false


func kind() -> StringName:
	return &"science_sensor_mode"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.set_mode(world, ship_id, active)
