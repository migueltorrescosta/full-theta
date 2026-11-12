class_name RunModifierDef
extends Resource
## One run modifier (#38 D7, gp-11): the lobby rolls one at random for each game and the
## host may reroll it in the Game setup sheet (GameRules.modifier_id); the run setup applies
## its numbers. Files live in content/runs/modifiers/. Read-only at runtime (FT-ARC-020).

@export var id: StringName = &""
## i18n keys of its name and its one-line description, shown in the Game setup sheet.
@export var name_key: StringName = &""
@export var detail_key: StringName = &""
## Multipliers on the run's numbers, 1 leaving one alone. The encounters' enemy strength
## (dimensionless; the director reads it, ScenarioApi.modifier_strength).
@export var strength: float = 1.0
## RunDef.bounty's multiplier (dimensionless).
@export var bounty: float = 1.0
## RunDef.salvage's multiplier (dimensionless).
@export var salvage: float = 1.0
## Every market price and repair's multiplier (dimensionless; RunSetup scales the markets).
@export var prices: float = 1.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if name_key == &"":
		errors.append("name_key is empty")
	DefCheck.positive(errors, "strength", strength)
	DefCheck.non_negative(errors, "bounty", bounty)
	DefCheck.non_negative(errors, "salvage", salvage)
	DefCheck.positive(errors, "prices", prices)
	return errors
