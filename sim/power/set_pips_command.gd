class_name SetPipsCommand
extends SimCommand
## Engineering sets the pips of a subsystem kind, overcharge included, within the reactor
## cap (FT-ENG-002, FT-SIM-026); rejected over the cap or the per-subsystem maximum.

## SubsystemDef.Kind of the subsystem (its first of that kind).
var subsystem_kind: int = SubsystemDef.Kind.ENGINES
var pips: int = 0


func kind() -> StringName:
	return &"set_pips"


## A rejection carries PowerSystem's reason (reject_reason), which the server sends back.
func apply(world: SimWorld) -> bool:
	reject_reason = PowerSystem.pips_refusal(world, ship_id, subsystem_kind, pips)
	return reject_reason == &"" and PowerSystem.set_pips(world, ship_id, subsystem_kind, pips)
