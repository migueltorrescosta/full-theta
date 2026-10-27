class_name CloseRunCommand
extends ServerCommand
## The director closes a crewed ship's run (Q4, owner 2026-10-26): it has played enough
## encounters and nothing more fits its budget, or the most the run allows. The ship wins
## once it is in no encounter (EncounterSystem.run_complete, read by OutcomeSystem). Rejects
## a ship that is not a crewed ship in play, one already closed, and one that has been
## through fewer than RunDef.min_encounters. Emits &"run_closed" (ship_id the ship, value
## the encounters it went through). Logged like every SERVER command (FT-ARC-008).

## The crewed ship whose run closes.
var ship: int = -1


func kind() -> StringName:
	return &"close_run"


func apply(world: SimWorld) -> bool:
	if world.run_def == null or ship < 0 or ship >= world.ship_count():
		return false
	if world.ai.is_enabled(ship) or world.run.status[ship] != RunTable.Status.IN_PLAY:
		return false
	if world.run.closed[ship] == 1:
		return false
	if world.run.encounters_done[ship] < world.run_def.min_encounters:
		return false
	world.run.closed[ship] = 1
	world.emit(&"run_closed", ship, -1, world.run.encounters_done[ship])
	return true
