extends GdUnitTestSuite
## Skip (D1, R25-1): a station stuck on a command step it cannot do on its device (a
## controller player on a radial-only Helm action) moves past it with an explicit Skip;
## Next still does nothing on a command step.


func _skip(rig: ShakedownRig, station: StringName) -> void:
	var cmd: TrainingNextCommand = TrainingNextCommand.new()
	cmd.ship_id = 0
	cmd.station = station
	cmd.skip = true
	rig.world.submit(cmd)
	rig.tick(2)


# FT: FT-MIS-039
func test_skip_moves_a_station_past_a_command_step_and_next_does_not() -> void:
	var rig: ShakedownRig = ShakedownRig.new()
	rig.tick(2)
	var first: TrainingStepDef = rig.driver.current(&"helm")
	assert_int(first.kind).is_equal(TrainingStepDef.Kind.COMMAND)
	rig.press_next(&"helm")
	assert_object(rig.driver.current(&"helm")).is_same(first)
	_skip(rig, &"helm")
	var second: TrainingStepDef = rig.driver.current(&"helm")
	assert_object(second).is_not_same(first)
	assert_int(rig.steps.track(&"helm").find(second)).is_equal(1)
	# The next step is said to the station, and another station's track is untouched.
	assert_array(rig.said(second.line)).is_not_empty()
	assert_int(rig.steps.track(&"weapons").find(rig.driver.current(&"weapons"))).is_equal(0)


# FT: FT-MIS-039
func test_one_skip_skips_one_step() -> void:
	var rig: ShakedownRig = ShakedownRig.new()
	rig.tick(2)
	_skip(rig, &"helm")
	_skip(rig, &"helm")
	assert_int(rig.steps.track(&"helm").find(rig.driver.current(&"helm"))).is_equal(2)
	rig.tick(30)
	assert_int(rig.steps.track(&"helm").find(rig.driver.current(&"helm"))).is_equal(2)


# FT: FT-MIS-039
func test_a_skip_is_a_crew_command_that_replays() -> void:
	var cmd: TrainingNextCommand = TrainingNextCommand.new()
	cmd.station = &"helm"
	cmd.skip = true
	var round: SimCommand = SimCommands.from_dict(cmd.to_dict())
	assert_object(round).is_instanceof(TrainingNextCommand)
	assert_bool((round as TrainingNextCommand).skip).is_true()
	assert_str(String(TrainingNextCommand.skip_flag_name(&"helm"))).is_equal("train.helm.skip")
	assert_str(String(TrainingDriver.skip_flag(&"helm"))).is_equal("train.helm.skip")
