class_name ScienceSelfScanCommand
extends SimCommand
## Science scans its own ship to name hidden fault causes (FT-SCI-009). See
## ScienceSystem.start_self_scan.


func kind() -> StringName:
	return &"science_self_scan"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.start_self_scan(world, ship_id)
