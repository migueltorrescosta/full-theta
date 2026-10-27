class_name EndEncounterCommand
extends ServerCommand
## Ends an open encounter with a result (E07, FT-MIS-025): the Scenario API's
## end_encounter(), sent when a scenario reports it finished.

var encounter: int = -1
## An EncounterTable.Result of WON, LOST, FLED or ABANDONED.
var result: int = EncounterTable.Result.WON


func kind() -> StringName:
	return &"end_encounter"


## Rejects an encounter that is not open and a result that is not an ending.
func apply(world: SimWorld) -> bool:
	if not world.encounters.is_open(encounter):
		return false
	if result < EncounterTable.Result.WON or result > EncounterTable.Result.ABANDONED:
		return false
	EncounterSystem.finish(world, encounter, result as EncounterTable.Result)
	return true
