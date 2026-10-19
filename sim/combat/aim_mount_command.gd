class_name AimMountCommand
extends SimCommand
## Sets a mount's aim point, a site-local 64-bit point (m, D104) the barrel slews
## toward and holds while the ship turns (FT-WPN-009, FT-SIM-011).

var mount_index: int = 0
var aim_x: float = 0.0
var aim_y: float = 0.0
var aim_z: float = 0.0


func kind() -> StringName:
	return &"aim_mount"


func apply(world: SimWorld) -> bool:
	var row: int = world.mounts.row_for(ship_id, mount_index)
	if row < 0:
		return false
	world.mounts.aim_set[row] = 1
	world.mounts.aim_x[row] = aim_x
	world.mounts.aim_y[row] = aim_y
	world.mounts.aim_z[row] = aim_z
	return true
