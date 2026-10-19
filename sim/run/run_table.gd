class_name RunTable
extends SimTable
## Run state (T036, FT-MIS-017): one row per ship keyed by ship id and faction
## (FT-ARC-012), holding whether the ship is still in the encounter and, for crewed
## ships, the encounter's outcome for it. It lives in SimWorld like every other table,
## so the sim owns it, the state hash covers it and the run reset rebuilds it with the
## world (M1Encounter). Only OutcomeSystem writes here.

## IN_PLAY: in the encounter. DESTROYED: hull reached 0. RETREATED: an AI ship in
## RETREAT mode that no ship of a hostile faction detects any more (OutcomeSystem).
enum Status { IN_PLAY, DESTROYED, RETREATED }
## The encounter's outcome for a crewed ship (D30: per-ship elimination); AI ships
## stay NONE.
enum Outcome { NONE, WIN, LOSS }

## Event tags for each Outcome, in Outcome order.
const OUTCOME_NAMES: Array[StringName] = [&"none", &"win", &"loss"]

## Status of the ship.
var status: PackedByteArray = PackedByteArray()
## Tick on which status last changed, or -1 while it is the spawn value.
var status_tick: PackedInt32Array = PackedInt32Array()
## Outcome for the ship's crew; set once, never changed after.
var outcome: PackedByteArray = PackedByteArray()
## Tick on which the outcome was set, or -1.
var outcome_tick: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	status.append(Status.IN_PLAY)
	status_tick.append(-1)
	outcome.append(Outcome.NONE)
	outcome_tick.append(-1)


func columns() -> Array:
	return (
		super()
		+ [
			["status", status],
			["status_tick", status_tick],
			["outcome", outcome],
			["outcome_tick", outcome_tick],
		]
	)
