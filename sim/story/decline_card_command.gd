class_name DeclineCardCommand
extends SimCommand
## Comms declines a card alone (FT-COM-003, D57, FT-PAIR-011).

var card: int = -1


func kind() -> StringName:
	return &"comms_decline"


func apply(world: SimWorld) -> bool:
	return Story.decline(world, ship_id, card)
