class_name AimMountCommand
extends SimCommand
## Sets a mount's aim point, a 64-bit point (m, D104) the barrel slews
## toward and holds while the ship turns (FT-WPN-009, FT-SIM-011). A point off the
## cube is wrapped onto it; a non-finite one is rejected (FT-SIM-035, D124).

var mount_index: int = 0
var aim_x: float = 0.0
var aim_y: float = 0.0
var aim_z: float = 0.0


func kind() -> StringName:
	return &"aim_mount"


func apply(world: SimWorld) -> bool:
	var row: int = world.mounts.row_for(ship_id, mount_index)
	var p: PackedFloat64Array = world.kin.wrap_point(aim_x, aim_y, aim_z)
	if row < 0 or p.is_empty():
		return false
	world.mounts.aim_set[row] = 1
	world.mounts.aim_x[row] = p[0]
	world.mounts.aim_y[row] = p[1]
	world.mounts.aim_z[row] = p[2]
	return true
