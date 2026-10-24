class_name ScienceHackMoveCommand
extends SimCommand
## Science moves the hack route to an adjacent node (FT-SCI-011). See ScienceSystem.hack_move.

var node: int = -1


func kind() -> StringName:
	return &"science_hack_move"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.hack_move(world, ship_id, node)
