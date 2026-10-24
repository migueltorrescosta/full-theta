class_name HardenCommand
extends SimCommand
## Engineering pre-hardens a subsystem (FT-ENG-008, P11). See DamageSystem.harden.

var subsystem_id: StringName = &""


func kind() -> StringName:
	return &"harden"


func apply(world: SimWorld) -> bool:
	return DamageSystem.harden(world, ship_id, subsystem_id)
