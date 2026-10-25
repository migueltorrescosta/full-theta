class_name PickFaultCauseCommand
extends SimCommand
## Engineering names the cause of a subsystem's fault (FT-ENG-006, FT-SIM-025, P10); the
## right cause repairs at full rate. See DamageSystem.pick_fault_cause.

var subsystem_id: StringName = &""
var cause: StringName = &""


func kind() -> StringName:
	return &"pick_fault_cause"


func apply(world: SimWorld) -> bool:
	return DamageSystem.pick_fault_cause(world, ship_id, subsystem_id, cause)
