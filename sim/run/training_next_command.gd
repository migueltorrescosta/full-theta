class_name TrainingNextCommand
extends SimCommand
## A station presses Next in the Shakedown (FT-MIS-039, D235): the player has done a step
## on a control that sends no sim command (chase camera, zoom, menu, panel switch) and
## moves on. Accepted only while the world's run is a training run, so no other run sees
## it. It sets the story flag train.<station>.next to the number of presses, which the
## training driver reads through the Scenario API; being a crew command it is logged, so
## a run replays. Every crew station and the Captain seat may send it (StationViews).

## The station pressing Next (a StationViews crew id or captain).
var station: StringName = &""


func kind() -> StringName:
	return &"training_next"


## The flag the presses of `station` are counted in.
static func flag_name(station_id: StringName) -> StringName:
	return StringName("train.%s.next" % station_id)


func apply(world: SimWorld) -> bool:
	if world.run_def == null or not world.run_def.training or station == &"":
		return false
	var flag: StringName = flag_name(station)
	world.story_flags.set_flag(flag, world.story_flags.get_flag(flag) + 1)
	return true
