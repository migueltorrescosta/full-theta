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
	var p: PackedFloat64Array = world.kin.wrap_point(CubePoint.make(aim_x, aim_y, aim_z))
	if row < 0 or p.is_empty():
		return false
	var m: MountTable = world.mounts
	m.aim_set[row] = 1
	CubePoint.write(m.aim_x, m.aim_y, m.aim_z, row, p)
	return true
