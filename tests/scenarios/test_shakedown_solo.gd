extends GdUnitTestSuite
## Solo station lessons (D303, FT-MIS-039): one station plays its whole Shakedown track alone,
## every other track counts as done, and the scripted partner (TrainingPartners) presses Next
## for its half of each pair step, so the lesson reaches its end by itself.

const STATIONS: Array[StringName] = ShakedownLessons.STATIONS


func _rig(solo: StringName) -> ShakedownRig:
	return ShakedownLessons.rig(solo)


func _tick(rig: ShakedownRig, partners: TrainingPartners, n: int = 1) -> void:
	ShakedownLessons.tick(rig, partners, n)


func _press(rig: ShakedownRig, partners: TrainingPartners, station: StringName) -> void:
	ShakedownLessons.press(rig, partners, station)


## The pair steps that name the station.
func _pairs_of(rig: ShakedownRig, station: StringName) -> Array[TrainingStepDef]:
	return rig.steps.pairs().filter(
		func(p: TrainingStepDef) -> bool: return p.station == station or p.partner == station
	)


# FT: FT-MIS-039
func test_every_station_plays_its_whole_track_alone_to_the_end() -> void:
	for solo: StringName in STATIONS:
		var lesson: Dictionary = ShakedownLessons.lesson(solo)
		var rig: ShakedownRig = lesson["rig"]
		assert_int(lesson["took"]).override_failure_message(String(solo)).is_greater(0)
		assert_bool(rig.driver.finished(solo)).is_true()
		# Its own track was said step by step, and every pair step that names it was said.
		assert_array(rig.said("shakedown.%s.track_done" % solo)).is_not_empty()
		for p: TrainingStepDef in _pairs_of(rig, solo):
			assert_array(rig.said(p.line)).override_failure_message(p.line).is_not_empty()


# FT: FT-MIS-039
func test_other_stations_are_silent_and_pairs_without_the_station_never_start() -> void:
	var lesson: Dictionary = ShakedownLessons.lesson(&"helm")
	var rig: ShakedownRig = lesson["rig"]
	assert_int(lesson["took"]).is_greater(0)
	for other: StringName in STATIONS:
		if other != &"helm":
			var said: Array[SimEvent] = rig.world.events.filter(
				func(e: SimEvent) -> bool: return String(e.tag).begins_with("shakedown.%s." % other)
			)
			assert_array(said).override_failure_message(String(other)).is_empty()
	for p: TrainingStepDef in rig.steps.pairs():
		if p.station != &"helm" and p.partner != &"helm":
			assert_array(rig.said(p.line)).override_failure_message(p.line).is_empty()


# FT: FT-MIS-039
func test_the_partner_presses_next_after_the_delay_and_only_once() -> void:
	var rig: ShakedownRig = _rig(&"weapons")
	var partners: TrainingPartners = TrainingPartners.new()
	_tick(rig, partners, 2)
	# Finish the weapons track without ticking the partners, then wait for the first pair.
	var guard: int = 0
	while rig.driver.current(&"weapons") != null and guard < 1000:
		var step: TrainingStepDef = rig.driver.current(&"weapons")
		if step.kind == TrainingStepDef.Kind.COMMAND:
			rig.world.submit(rig.command_for(step.command))
			_tick(rig, partners, 2)
		else:
			_press(rig, partners, &"weapons")
		guard += 1
	_tick(rig, partners, 2)
	var pairs: Array[TrainingStepDef] = rig.driver.active_pairs()
	assert_int(pairs.size()).is_equal(1)
	var first: TrainingStepDef = pairs[0]
	var partner: StringName = first.partner if first.station == &"weapons" else first.station
	var flag: StringName = TrainingNextCommand.flag_name(partner)
	assert_int(rig.world.story_flags.get_flag(flag)).is_equal(0)
	_tick(rig, partners, TrainingPartners.press_ticks(first, partner) + 4)
	assert_int(rig.world.story_flags.get_flag(flag)).is_equal(1)
	_tick(rig, partners, 600)
	assert_int(rig.world.story_flags.get_flag(flag)).is_equal(1)


# FT: FT-MIS-039
func test_the_crew_drill_is_unchanged() -> void:
	var rig: ShakedownRig = _rig(&"")
	var partners: TrainingPartners = TrainingPartners.new()
	_tick(rig, partners, 5)
	assert_str(String(rig.driver.solo_station())).is_empty()
	for station: StringName in STATIONS:
		assert_bool(rig.driver.finished(station)).is_false()
	assert_array(rig.driver.active_pairs()).is_empty()
	# No partner presses in the drill.
	_tick(rig, partners, 600)
	assert_int(rig.world.story_flags.get_flag(TrainingNextCommand.flag_name(&"helm"))).is_equal(0)
