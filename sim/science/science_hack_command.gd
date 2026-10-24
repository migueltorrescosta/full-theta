class_name ScienceHackCommand
extends SimCommand
## Science opens a node-route hack on a subsystem of a contact (FT-SCI-006). See
## ScienceSystem.start_hack.

var contact: int = -1
var subsystem_id: StringName = &""


func kind() -> StringName:
	return &"science_hack"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.start_hack(world, ship_id, contact, subsystem_id)
