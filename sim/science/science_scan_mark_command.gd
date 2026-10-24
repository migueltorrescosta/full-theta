class_name ScienceMarkCommand
extends SimCommand
## Science places the scan-position mark for a contact (FT-SCI-010, P3). See
## ScienceSystem.place_mark.

var contact: int = -1


func kind() -> StringName:
	return &"science_scan_mark"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.place_mark(world, ship_id, contact)
