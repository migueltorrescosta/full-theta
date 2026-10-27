class_name RunDef
extends Resource
## One run of the campaign (E07, FT-MIS-001, FT-MIS-002): the map it plays on, how many
## encounters it lasts, which scenarios the director may pick, and the numbers the run
## reads (director, flee cost, the crew's ship, starting credits). RunSetup builds the
## world from it. Read-only at runtime (FT-ARC-020).

@export var id: StringName = &""
## The one wrapping cube with its named sites (D229). Set once the map exists.
@export var map: MapDef
## The director picks between this many and this many encounters per ship (count, FT-MIS-001,
## Q4 owner 2026-10-26): it closes the run once the budget has no fit, or the most is reached,
## after at least the fewest. The run is won when the director closes it.
@export var min_encounters: int = 4
## The most encounters a ship goes through (count).
@export var max_encounters: int = 6
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
	if min_encounters < 1:
		errors.append("min_encounters must be at least 1, got %d" % min_encounters)
	if max_encounters < min_encounters:
		errors.append(
			(
				"max_encounters must be at least min_encounters (%d), got %d"
				% [min_encounters, max_encounters]
			)
		)
	var seen: Dictionary[String, bool] = {}
	for s: String in scenarios:
		if seen.has(s):
			errors.append("scenario %s listed twice" % s)
		seen[s] = true
	if DefCheck.required(errors, "director", director) and not training:
		# Every scenario costs at least 1, so a budget below the fewest encounters can't
		# reach them (Q14).
		for preset: StringName in director.budget_per_ship:
			if director.budget_per_ship[preset] < min_encounters:
				errors.append(
					(
						"director.budget_per_ship[%s] must be at least min_encounters (%d)"
						% [preset, min_encounters]
					)
				)
	DefCheck.required(errors, "flee_cost", flee_cost)
	DefCheck.required(errors, "player_ship", player_ship)
	if start_credits < 0:
		errors.append("start_credits must be at least 0, got %d" % start_credits)
	return errors
