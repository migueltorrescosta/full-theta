class_name RunModifierDef
extends Resource
## One run modifier (#38 D7, gp-11): the lobby rolls one at random for each game and the
## host may reroll it in the Game setup sheet (GameRules.modifier_id); the run setup applies
## its numbers. Files live in content/runs/modifiers/. Read-only at runtime (FT-ARC-020).

@export var id: StringName = &""
## i18n keys of its name and its one-line description, shown in the Game setup sheet.
@export var name_key: StringName = &""
@export var detail_key: StringName = &""


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if name_key == &"":
		errors.append("name_key is empty")
	return errors
