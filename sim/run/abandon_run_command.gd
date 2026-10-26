class_name AbandonRunCommand
extends ServerCommand
## The crew abandons the run (E07, FT-MIS-016, D96): every crewed ship in play becomes
## ABANDONED, so OutcomeSystem gives each a LOSS and the run ends, and every open
## encounter ends ABANDONED. The server sends it when the crew's vote passes outside a
## pause. PROVISIONAL (Q13): co-op ends the whole run; a per-ship vote is not decided.
## Logged like every SERVER command, so a replay abandons on the same tick (FT-ARC-008).


func kind() -> StringName:
	return &"abandon_run"


## Rejects when no crewed ship is still in play.
func apply(world: SimWorld) -> bool:
	var any: bool = false
	for id: int in world.ship_count():
		if world.ai.is_enabled(id) or world.run.status[id] != RunTable.Status.IN_PLAY:
			continue
		world.run.status[id] = RunTable.Status.ABANDONED
		any = true
	if not any:
		return false
	for e: int in world.encounters.size():
		if world.encounters.is_open(e):
			EncounterSystem.finish(world, e, EncounterTable.Result.ABANDONED)
	world.emit(&"run_abandoned", -1)
	return true
