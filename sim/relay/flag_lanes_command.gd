class_name FlagLanesCommand
extends SimCommand
## Relay switches lane flagging on or off (FT-RLY-011, P8, D37): while it is on, Weapons
## is warned before a shot along a lane that crosses a friendly (ProbeSystem).

var on: bool = true


func kind() -> StringName:
	return &"flag_lanes"


func apply(world: SimWorld) -> bool:
	world.relay.lanes_flagged[ship_id] = 1 if on else 0
	world.relay.lane_warned[ship_id] = -1
	return true
