class_name ScienceScanSubmitCommand
extends SimCommand
## Science submits the wireframe angles (rad about x, y, z) of the open scan (FT-SCI-011). See
## ScienceSystem.submit_scan.

var ax: float = 0.0
var ay: float = 0.0
var az: float = 0.0


func kind() -> StringName:
	return &"science_scan_submit"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.submit_scan(world, ship_id, Vector3(ax, ay, az))
