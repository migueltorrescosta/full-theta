class_name DirectorDecision
extends RefCounted
## One logged director decision (FT-MIS-006, D35): what it did, to which ship, with what
## budget before and after, and why. The reason is an i18n key "director.reason.<x>" with
## arguments, so the end-of-run debrief shows it in the player's language (FT-MIS-010).

## RAIDER_WAVE: a last-ship-standing raider wave at the ship (#11, M4-Q7, FleetDirector).
enum Kind { PICK_ENCOUNTER, OPEN_SITE, SKIP, END_RUN, RAIDER_WAVE }

var tick: int = 0
var ship: int = -1
var kind: Kind = Kind.SKIP
var scenario_id: StringName = &""
var site: int = -1
var cost: int = 0
var budget_before: int = 0
var budget_after: int = 0
## "director.reason.<x>", for example budget_fits, pacing_gap, low_hull, site_pool, no_fit.
var reason_key: String = ""
var reason_args: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"tick": tick,
		"ship": ship,
		"kind": Kind.keys()[kind],
		"scenario_id": String(scenario_id),
		"site": site,
		"cost": cost,
		"budget_before": budget_before,
		"budget_after": budget_after,
		"reason_key": reason_key,
		"reason_args": reason_args.duplicate(true),
	}
