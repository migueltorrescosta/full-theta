class_name ScienceCancelCommand
extends SimCommand
## Science closes its open scan, hack or own-ship scan. See ScienceSystem.cancel.


func kind() -> StringName:
	return &"science_cancel"


func apply(world: SimWorld) -> bool:
	return ScienceSystem.cancel(world, ship_id)
