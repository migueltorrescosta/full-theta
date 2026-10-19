class_name SetShieldFocusCommand
extends SimCommand
## Helm sets the shield focus direction: a face, a ring sector or tracking a ship
## (FT-SIM-018, FT-HLM-008 to 010, D16, D48).

## Focus direction (unit vector, ship frame; -Z is the bow).
var direction: Vector3 = Vector3.FORWARD
## Ship to keep the focus on, or -1 for the fixed direction.
var track_id: int = -1


func kind() -> StringName:
	return &"set_shield_focus"


func apply(world: SimWorld) -> bool:
	return ShieldSystem.set_focus(world, ship_id, direction, track_id)
