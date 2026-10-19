class_name LevelCommand
extends SimCommand
## One Level press (FT-HLM-007, D97): the first press rolls the ship's up as close to
## ecliptic up as the heading allows; a second press, or a press when already rolled
## level, also pitches onto the ecliptic. Rotation input cancels it (AssistSystem).


func kind() -> StringName:
	return &"helm_level"


func apply(world: SimWorld) -> bool:
	var helm: HelmTable = world.helm
	var rolled: bool = absf(AssistSystem.roll_error(world.kin, ship_id)) < AssistSystem.ROLLED_LEVEL
	var stage: int = helm.level[ship_id]
	if stage == HelmTable.Level.ROLL or (stage == HelmTable.Level.OFF and rolled):
		helm.level[ship_id] = HelmTable.Level.ROLL_AND_PITCH
	else:
		helm.level[ship_id] = HelmTable.Level.ROLL
	return true
