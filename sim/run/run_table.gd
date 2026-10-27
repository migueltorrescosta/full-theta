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
## Encounters the ship has been through (finished, fled or lost), and the id of the one
## it is in (PENDING or ACTIVE), or -1. Fled encounters are also counted in fled_count
## (E07, FT-MIS-010, FT-MIS-025).
var encounters_done: PackedInt32Array = PackedInt32Array()
var encounter: PackedInt32Array = PackedInt32Array()
var fled_count: PackedInt32Array = PackedInt32Array()
## 1 once the director has closed the ship's run (CloseRunCommand); it then wins when it is in
## no encounter (EncounterSystem.run_complete, Q4).
var closed: PackedByteArray = PackedByteArray()
## Session counters of a multi-ship session (#11, M4-Q2, M4-Q9): times the ship has
## relaunched (RelaunchShipCommand) and crewed ships of another side it destroyed (PvP kills,
## OutcomeSystem). A ship reset keeps both.
var relaunches: PackedInt32Array = PackedInt32Array()
var kills: PackedInt32Array = PackedInt32Array()
## Tick the crewed ship's outcome was set: its run complete (WIN) or it left play (LOSS); -1
## while it plays. The scoreboard's finish time, a race's first finisher and a holdout's score.
var finish_tick: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	status.append(Status.IN_PLAY)
	outcome.append(Outcome.NONE)
	encounters_done.append(0)
	encounter.append(-1)
	fled_count.append(0)
	closed.append(0)
	relaunches.append(0)
	kills.append(0)
	finish_tick.append(-1)


func columns() -> Array:
	return (
		super()
		+ [
			["status", status],
			["outcome", outcome],
			["encounters_done", encounters_done],
			["encounter", encounter],
			["fled_count", fled_count],
			["closed", closed],
			["relaunches", relaunches],
			["kills", kills],
			["finish_tick", finish_tick],
		]
	)


## A ship reset (a relaunch or a training reset, FT-MIS-011, FT-MIS-017) restores the ship's
## run progress but keeps its session counters, relaunches and kills.
func reset_ship(ship_id: int, def: ShipDef) -> void:
	var row: int = row_of(ship_id)
	if row < 0:
		return
	var relaunched: int = relaunches[row]
	var killed: int = kills[row]
	super(ship_id, def)
	relaunches[row] = relaunched
	kills[row] = killed
