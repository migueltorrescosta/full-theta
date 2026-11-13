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


## A decision at `tick` about `ship`, from the fields in `f` (scenario_id, site, cost,
## budget_before, budget_after, args) and its reason "director.reason.<f.reason>" (R04-11: the
## Director's log and FleetDirector's raider waves share it).
static func make(
	tick_value: int, ship_id: int, kind_value: Kind, f: Dictionary
) -> DirectorDecision:
	var d: DirectorDecision = DirectorDecision.new()
	d.tick = tick_value
	d.ship = ship_id
	d.kind = kind_value
	d.scenario_id = f.get("scenario_id", &"")
	d.site = f.get("site", -1)
	d.cost = f.get("cost", 0)
	d.budget_before = f.get("budget_before", 0)
	d.budget_after = f.get("budget_after", 0)
	d.reason_key = "director.reason.%s" % f["reason"]
	d.reason_args = f.get("args", {})
	return d


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
