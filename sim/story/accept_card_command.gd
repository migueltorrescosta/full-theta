class_name AcceptCardCommand
extends SimCommand
## Comms accepts a card alone, with no co-sign (FT-COM-003, D57, FT-PAIR-011).

var card: int = -1


func kind() -> StringName:
	return &"comms_accept"


func apply(world: SimWorld) -> bool:
	return Story.accept(world, ship_id, card)
