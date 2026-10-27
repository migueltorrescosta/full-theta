class_name UndockCommand
extends SimCommand
## Lets a docked ship go (FT-HLM-013): it stays at the dock point, at rest, under Helm's
## control again. Rejected when not docked. Emits &"undocked" (value: the site id).


func kind() -> StringName:
	return &"helm_undock"


func apply(world: SimWorld) -> bool:
	var site: int = world.helm.docked_site[ship_id]
	if site < 0:
		return false
	world.helm.docked_site[ship_id] = -1
	world.emit(&"undocked", ship_id, -1, float(site))
	return true
