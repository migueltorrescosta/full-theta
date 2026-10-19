class_name DecoupledCommand
extends SimCommand
## Sets decoupled mode on or off (FT-SIM-005). The station's toggle sends the new state,
## so a repeated command can't flip the mode twice.

var decoupled: bool = true


func kind() -> StringName:
	return &"helm_decoupled"


func apply(world: SimWorld) -> bool:
	var helm: HelmTable = world.helm
	if helm.is_decoupled(ship_id) and not decoupled:
		# Back to assist: hold the current speed instead of lurching to the old setpoint.
		helm.throttle_setpoint[ship_id] = AssistSystem.forward_speed(world, ship_id)
	helm.decoupled[ship_id] = 1 if decoupled else 0
	return true
