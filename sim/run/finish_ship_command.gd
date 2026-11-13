class_name FinishShipCommand
extends ServerCommand
## The director closes a crewed ship's run (Q4, owner 2026-10-26): it has played enough
## encounters and nothing more fits its budget, or the most the run allows. The ship wins
## once it is in no encounter (EncounterSystem.run_complete, read by OutcomeSystem). Rejects
## a ship that is not a crewed ship in play, one already closed, and one that has been
## through fewer than RunDef.min_encounters. With `survived` (the finale out of tries, w-a89)
## the ship survives rather than wins. Emits &"run_closed" (ship_id the ship, value the
## encounters it went through, tag &"survived" or &""). Logged like every SERVER command
## (FT-ARC-008).

## The crewed ship whose run closes.
var ship: int = -1
## The run closes with the finale out of tries: the ship survives rather than wins.
var survived: bool = false


func kind() -> StringName:
	return &"finish_ship"


func apply(world: SimWorld) -> bool:
	if world.run_def == null or not world.has_ship(ship):
		return false
	if not world.is_crew_in_play(ship):
		return false
	if world.ships.closed[ship] != 0:
		return false
	if world.ships.encounters_done[ship] < world.run_def.min_encounters:
		return false
	world.ships.closed[ship] = 2 if survived else 1
	var tag: StringName = &"survived" if survived else &""
	world.emit(&"run_closed", ship, -1, world.ships.encounters_done[ship], Vector3.ZERO, tag)
	return true
