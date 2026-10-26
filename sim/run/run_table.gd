class_name RunTable
extends SimTable
## Run state (T036, FT-MIS-017): one row per ship keyed by ship id and faction
## (FT-ARC-012), holding whether the ship is still in the encounter and, for crewed
## ships, the encounter's outcome for it. It lives in SimWorld like every other table,
## so the sim owns it, the state hash covers it and the run reset rebuilds it with the
## world (M1Encounter). OutcomeSystem writes here, and AbandonShipCommand sets ABANDONED.

## IN_PLAY: in the encounter. DESTROYED: hull reached 0. RETREATED: an AI ship in
## RETREAT mode that no ship of a hostile faction detects any more (OutcomeSystem).
## ABANDONED: its crew or the host abandoned it during a pause (AbandonShipCommand).
enum Status { IN_PLAY, DESTROYED, RETREATED, ABANDONED }
## The encounter's outcome for a crewed ship (D30: per-ship elimination); AI ships
## stay NONE.
enum Outcome { NONE, WIN, LOSS }

## Event tags for each Outcome, in Outcome order.
const OUTCOME_NAMES: Array[StringName] = [&"none", &"win", &"loss"]

## Status of the ship.
var status: PackedByteArray = PackedByteArray()
## Outcome for the ship's crew; set once, never changed after.
var outcome: PackedByteArray = PackedByteArray()
# --- strand A ---
## Encounters the ship has been through (finished, fled or lost), and the id of the one
## it is in (PENDING or ACTIVE), or -1. Fled encounters are also counted in fled_count
## (E07, FT-MIS-010, FT-MIS-025).
var encounters_done: PackedInt32Array = PackedInt32Array()
var encounter: PackedInt32Array = PackedInt32Array()
var fled_count: PackedInt32Array = PackedInt32Array()
# --- end strand A ---


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	status.append(Status.IN_PLAY)
	outcome.append(Outcome.NONE)
	encounters_done.append(0)  # strand A
	encounter.append(-1)
	fled_count.append(0)


func columns() -> Array:
	return (
		super()
		+ [
			["status", status],
			["outcome", outcome],
			["encounters_done", encounters_done],  # strand A
			["encounter", encounter],
			["fled_count", fled_count],
		]
	)
