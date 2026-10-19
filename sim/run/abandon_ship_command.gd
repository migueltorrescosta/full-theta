class_name AbandonShipCommand
extends SimCommand
## Takes a crewed ship out of play when its crew or the host abandon it during a
## universe pause (FT-NET-041, D96, D128): its RunTable status becomes ABANDONED, and
## OutcomeSystem gives it a LOSS like a destroyed ship (per-ship elimination, D30), which
## in M1 ends the encounter as a loss. The server sends it, not a crew (source SERVER),
## and it is logged so a replay abandons the ship on the same tick (FT-ARC-008).


func _init() -> void:
	source = Source.SERVER


func kind() -> StringName:
	return &"abandon_ship"


## Rejects a ship that is no longer in play (destroyed, retreated or already abandoned).
func apply(world: SimWorld) -> bool:
	if world.run.status[ship_id] != RunTable.Status.IN_PLAY:
		return false
	world.run.status[ship_id] = RunTable.Status.ABANDONED
	return true
