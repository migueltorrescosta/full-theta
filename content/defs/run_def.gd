class_name RunDef
extends Resource
## One run of the campaign (E07, FT-MIS-001, FT-MIS-002): the map it plays on, how many
## encounters it lasts, which scenarios the director may pick, and the numbers the run
## reads (director, flee cost, the crew's ship, starting credits). RunSetup builds the
## world from it. Read-only at runtime (FT-ARC-020).

@export var id: StringName = &""
## The one wrapping cube with its named sites (D229). Set once the map exists.
@export var map: MapDef
## The run ends in a win after this many encounters (count, FT-MIS-001).
@export var encounters: int = 5
## Scenario ids the director may pick.
@export var scenarios: PackedStringArray = PackedStringArray()
@export var director: DirectorDef
@export var flee_cost: FleeCostDef
@export var player_ship: ShipDef
## Credits each crewed ship starts with (count).
@export var start_credits: int = 0
## A training run (the Shakedown, FT-MIS-039): a crewed ship at hull 0 is reset at the yard
## instead of eliminated. A rule of the training world, not a stat change (FT-SIM-029).
@export var training: bool = false


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if encounters < 1:
		errors.append("encounters must be at least 1, got %d" % encounters)
	var seen: Dictionary[String, bool] = {}
	for s: String in scenarios:
		if seen.has(s):
			errors.append("scenario %s listed twice" % s)
		seen[s] = true
	DefCheck.required(errors, "director", director)
	DefCheck.required(errors, "flee_cost", flee_cost)
	DefCheck.required(errors, "player_ship", player_ship)
	if start_credits < 0:
		errors.append("start_credits must be at least 0, got %d" % start_credits)
	return errors
