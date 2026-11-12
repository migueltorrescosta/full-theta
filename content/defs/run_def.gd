class_name RunDef
extends Resource
## One run (E07, FT-MIS-001): the map it plays on, how many
## encounters it lasts, which scenarios the director may pick, and the numbers the run
## reads (director, flee cost, the crew's ship, starting credits). RunSetup builds the
## world from it. Read-only at runtime (FT-ARC-020).

## The difficulty presets the lobby offers; a run's director budgets every one (a missing one
## would leave the director with no budget).
const PRESETS: Array[StringName] = [&"easy", &"normal", &"hard"]

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
## The share of a card's reward paid when its encounter's time runs out before the
## objective is met, a PARTIAL result (dimensionless, 0 to 1).
@export var partial_pay: float = 1.0
## Crippled (gp-09, #38 D4): a crewed ship in an active encounter whose hull fraction falls
## under crippled_hull (dimensionless, 0 to 1; 0 never), or with crippled_subsystems destroyed,
## has limp_home_time to dock anywhere: the encounter then ends PARTIAL ("limped home") and its
## accepted cards pay partial_pay.
@export var crippled_hull: float = 0.0
## Destroyed subsystems that cripple a ship (count; 0 never).
@export var crippled_subsystems: int = 0
## Time a crippled ship has to dock and limp home (s; 0 turns crippling off).
@export var limp_home_time: float = 0.0
## Co-op relaunches per ship per run (count; 0 none, D259), gp-10 (#38 D4).
@export var coop_relaunches: int = 0
## What a co-op relaunch costs, from the lost ship's purse (count, credits).
@export var relaunch_cost: int = 0
## Credits a crewed ship earns for destroying a raider, an armed AI ship of a hostile faction
## (count; gp-11, #38 D7).
@export var bounty: int = 0
## Credits a destroyed armed AI ship's wreck holds (count).
@export var salvage: int = 0
## The first crewed ship this close to a wreck collects it (m).
@export var salvage_range: float = 300.0
## How long a wreck can be collected (s).
@export var salvage_lifetime: float = 300.0
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
		for preset: StringName in PRESETS:
			if not director.budget_per_ship.has(preset):
				errors.append("director.budget_per_ship needs the %s preset" % preset)
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
	if partial_pay < 0.0 or partial_pay > 1.0:
		errors.append("partial_pay must be within 0 and 1, got %s" % partial_pay)
	if start_credits < 0:
		errors.append("start_credits must be at least 0, got %d" % start_credits)
	DefCheck.in_range(errors, "crippled_hull", crippled_hull, 0.0, 1.0)
	DefCheck.non_negative(errors, "crippled_subsystems", crippled_subsystems)
	DefCheck.non_negative(errors, "limp_home_time", limp_home_time)
	DefCheck.non_negative(errors, "coop_relaunches", coop_relaunches)
	DefCheck.non_negative(errors, "relaunch_cost", relaunch_cost)
	DefCheck.non_negative(errors, "bounty", bounty)
	DefCheck.non_negative(errors, "salvage", salvage)
	DefCheck.non_negative(errors, "salvage_range", salvage_range)
	DefCheck.non_negative(errors, "salvage_lifetime", salvage_lifetime)
	return errors
