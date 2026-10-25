class_name ScienceScanCommand
extends SimCommand
## Science opens a silhouette-alignment scan of a contact (FT-SCI-004). See
## ScienceSystem.start_scan.

var contact: int = -1


func kind() -> StringName:
	return &"science_scan"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.start_scan(world, ship_id, contact)
