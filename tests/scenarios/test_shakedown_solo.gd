extends GdUnitTestSuite
## Solo station lessons (D303, FT-MIS-039): one station plays its whole Shakedown track alone,
## every other track counts as done, and the scripted partner (TrainingPartners) presses Next
## for its half of each pair step, so the lesson reaches its end by itself.

const STATIONS: Array[StringName] = [
	&"helm", &"weapons", &"engineering", &"science", &"relay", &"comms", &"captain"
]


func _rig(solo: StringName) -> ShakedownRig:
	var rig: ShakedownRig = ShakedownRig.new()
	rig.driver = TrainingDriver.new(ShakedownScenario.new(), rig.steps, solo)
	return rig


## Steps n ticks with the partners ahead of the driver, as the server does.
func _tick(rig: ShakedownRig, partners: TrainingPartners, n: int = 1) -> void:
	for i: int in n:
		rig.host.advance(
			SimWorld.DT * 1.001,
			func(api: ScenarioApi) -> void:
				partners.act(rig.world, rig.driver)
				rig.driver.before_tick(api)
		)


func _press(rig: ShakedownRig, partners: TrainingPartners, station: StringName) -> void:
	var cmd: TrainingNextCommand = TrainingNextCommand.new()
	cmd.ship_id = 0
	cmd.station = station
	rig.world.submit(cmd)
	_tick(rig, partners, 2)


## Plays the lesson as a player does: each step of the track, then Next in every pair step,
## until the driver says all_done. Returns the ticks it took (-1: it never ended).
func _play(rig: ShakedownRig, partners: TrainingPartners, solo: StringName) -> int:
	var start: int = rig.world.tick
	_tick(rig, partners, 2)
	for guard: int in 4000:
		if not rig.said("shakedown.all_done").is_empty():
			return rig.world.tick - start
		var step: TrainingStepDef = rig.driver.current(solo)
		if step != null:
			if step.kind == TrainingStepDef.Kind.COMMAND:
				rig.world.submit(rig.command_for(step.command))
				_tick(rig, partners, 2)
			else:
				_press(rig, partners, solo)
		elif not rig.driver.active_pairs().is_empty():
			_press(rig, partners, solo)
		else:
			_tick(rig, partners, 30)
	return -1


## The pair steps that name the station.
func _pairs_of(rig: ShakedownRig, station: StringName) -> Array[TrainingStepDef]:
	return rig.steps.pairs().filter(
		func(p: TrainingStepDef) -> bool: return p.station == station or p.partner == station
	)


# FT: FT-MIS-039
func test_every_station_plays_its_whole_track_alone_to_the_end() -> void:
	for solo: StringName in STATIONS:
		var rig: ShakedownRig = _rig(solo)
		var partners: TrainingPartners = TrainingPartners.new()
		var took: int = _play(rig, partners, solo)
		assert_int(took).override_failure_message(String(solo)).is_greater(0)
		assert_bool(rig.driver.finished(solo)).is_true()
		# Its own track was said step by step, and every pair step that names it was said.
		assert_array(rig.said("shakedown.%s.track_done" % solo)).is_not_empty()
		for p: TrainingStepDef in _pairs_of(rig, solo):
			assert_array(rig.said(p.line)).override_failure_message(p.line).is_not_empty()


# FT: FT-MIS-039
func test_other_stations_are_silent_and_pairs_without_the_station_never_start() -> void:
	var rig: ShakedownRig = _rig(&"helm")
	var partners: TrainingPartners = TrainingPartners.new()
	assert_int(_play(rig, partners, &"helm")).is_greater(0)
	for other: StringName in STATIONS:
		if other != &"helm":
			var said: Array[SimEvent] = rig.world.events.filter(
				func(e: SimEvent) -> bool:
					return String(e.tag).begins_with("shakedown.%s." % other)
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
	var flag: StringName = TrainingDriver.next_flag(partner)
	assert_int(rig.world.story_flags.get_flag(flag)).is_equal(0)
	_tick(rig, partners, TrainingPartners.DELAY_TICKS + 4)
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
	assert_int(rig.world.story_flags.get_flag(TrainingDriver.next_flag(&"helm"))).is_equal(0)
