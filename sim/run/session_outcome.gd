class_name SessionOutcome
extends RefCounted
## Who won a multi-ship session and why (#11, FT-MIS-013, FT-MIS-014, FT-MIS-031 to
## FT-MIS-034, owner M4-Q1, M4-Q2, M4-Q6, M4-Q7): a value OutcomeSystem.session_outcome()
## derives from the world each time it is asked, and the server reads it to end the session,
## fill the scoreboard and send `session_over`. Pure value.

## Why the session ended. NONE: still running. OBJECTIVE: the co-op fleet run's final
## objective is complete (COOP). ALL_LOST: every crewed ship is out of play and none won.
## FIRST_TO_FINISH: a ship (RACE) or a team (TEAMS) completed the final objective first.
## LAST_STANDING: one ship (LAST_STANDING) or one team (TEAMS) is left in play.
## HOLDOUT_OVER: the finite side has run out of ships and lives (HOLDOUT).
enum Reason { NONE, OBJECTIVE, ALL_LOST, FIRST_TO_FINISH, LAST_STANDING, HOLDOUT_OVER }

## Wire names, in Reason order.
const REASON_NAMES: Array[String] = [
	"none", "objective", "all_lost", "first_to_finish", "last_standing", "holdout_over"
]
## Sim events the M4 rules emit (SimEvent.kind). &"eliminated": a crewed ship left play
## (ship_id the ship, tag &"destroyed" | &"abandoned" | &"forfeit", value the relaunches left,
## -1 for unlimited). &"relaunched": RelaunchShipCommand put it back (value the relaunches
## left). &"session_over": the first tick session_outcome() is over (value the Reason).
const EVENT_ELIMINATED: StringName = &"eliminated"
const EVENT_RELAUNCHED: StringName = &"relaunched"
const EVENT_SESSION_OVER: StringName = &"session_over"

var reason: Reason = Reason.NONE
## The winning ships, ascending; empty with no winner (ALL_LOST, and HOLDOUT, which scores
## time rather than naming a winner).
var winners: PackedInt32Array = PackedInt32Array()
## The winning team in TEAMS and HOLDOUT, else -1.
var team: int = -1
## Ticks the finite side lasted (HOLDOUT, its score), else 0.
var held_ticks: int = 0


func over() -> bool:
	return reason != Reason.NONE


func to_dict() -> Dictionary:
	return {
		"reason": REASON_NAMES[reason],
		"winners": Array(winners),
		"team": team,
		"held_ticks": held_ticks,
	}
