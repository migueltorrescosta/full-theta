class_name BeginEncounterCommand
extends ServerCommand
## Opens an encounter for crewed ships (E07, FT-MIS-025, D231): the Scenario API's
## begin_encounter(). The row starts PENDING and turns ACTIVE when a ship arrives at the
## site or the arrival timeout passes (EncounterSystem). One encounter is open per ship at
## a time, so it is rejected when any of its ships is in another. Emits &"encounter_open"
## (ship_id the first ship, value the encounter id, tag the scenario id). The site is
## revealed to the ships' factions.

var scenario_id: StringName = &""
var site: int = -1
var ships: PackedInt32Array = PackedInt32Array()
var cost: int = 0


func kind() -> StringName:
	return &"begin_encounter"


## Rejects an unknown scenario or site, an empty ship list, and a ship that is not a live
## crewed ship in play, has no bit in the mask, or is already in an open encounter.
func apply(world: SimWorld) -> bool:
	var scenario: int = world.scenario_ids.find(String(scenario_id))
	if scenario < 0 or ships.is_empty() or cost < 0:
		return false
	if site < -1 or site >= world.sites.size():
		return false
	var mask: int = 0
	for s: int in ships:
		if s < 0 or s >= mini(world.ship_count(), EncounterTable.MAX_SHIP_BITS):
			return false
		if world.ai.is_enabled(s) or not world.kin.is_alive(s):
			return false
		if world.run.status[s] != RunTable.Status.IN_PLAY or world.run.encounter[s] >= 0:
			return false
		mask |= 1 << s
	var id: int = world.encounters.add_encounter(
		ships[0], world.faction_of(ships[0]), scenario, site, mask, cost, world.tick
	)
	for s: int in ships:
		world.run.encounter[s] = id
		# The crew must be able to see, select and jump to the site it is sent to (strand E).
		world.sites.reveal(site, world.faction_of(s))
	world.emit(&"encounter_open", ships[0], -1, id, Vector3.ZERO, scenario_id)
	return true
