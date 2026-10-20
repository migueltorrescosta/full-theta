class_name FireCommand
extends SimCommand
## Asks a mount for one shot this tick; WeaponSystem fires it or emits &"fire_blocked"
## with the reason (FT-SIM-011, FT-SIM-012).

var mount_index: int = 0


func kind() -> StringName:
	return &"fire"


func apply(world: SimWorld) -> bool:
	var row: int = world.mounts.row_for(ship_id, mount_index)
	if row < 0:
		return false
	world.mounts.fire_requested[row] = 1
	return true
