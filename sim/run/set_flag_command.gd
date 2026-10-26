class_name SetFlagCommand
extends ServerCommand
## Sets a named story flag (E07, FT-PAIR-003): scenarios and the director write flags, the
## API reads them. The flag lives in EncounterTable until the STORY flag table lands
## (strand C); 0 means unset.

var flag_name: StringName = &""
var value: int = 0


func kind() -> StringName:
	return &"set_flag"


func apply(world: SimWorld) -> bool:
	if flag_name == &"":
		return false
	world.encounters.set_flag(flag_name, value)
	return true
