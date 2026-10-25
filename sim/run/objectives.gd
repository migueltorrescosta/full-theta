class_name Objectives
extends RefCounted
## The objectives a ship's crew is working on, for the main screen's status view
## (FT-MSC-006, D60). M2 has no missions yet (#10), so the one objective is the
## encounter's own outcome, the way OutcomeSystem decides it: every ship of a hostile
## faction out of play. Missions (#10) add their rows here; clients read only this
## list, so the status view needs no change.

## Objective kinds (u8 on the wire).
enum Kind { NONE, DESTROY_HOSTILES }

## At most this many rows (the status view lists a handful).
const MAX_ROWS: int = 8


## The ship's open objectives: [{"kind": Kind, "left": int}] with `left` the number of
## things still to do (hostile ships in play). Empty once the ship has an outcome.
static func of_ship(world: SimWorld, ship: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world.run.outcome[ship] != RunTable.Outcome.NONE:
		return out
	var faction: int = world.faction_of(ship)
	var left: int = 0
	for o: int in world.ship_count():
		if world.run.status[o] != RunTable.Status.IN_PLAY:
			continue
		if world.relation(faction, world.kin.factions[o]) == SimWorld.Relation.HOSTILE:
			left += 1
	if left > 0:
		out.append({"kind": Kind.DESTROY_HOSTILES, "left": mini(left, 65535)})
	return out
