class_name ScienceSelectCommand
extends SimCommand
## Science selects a contact for the noise preview (-1 clears).

var contact: int = -1


func kind() -> StringName:
	return &"science_select"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.select(world, ship_id, contact)
