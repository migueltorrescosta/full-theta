extends GdUnitTestSuite
## The acting bots and scripted partner halves of a solo lesson (D303, FT-MIS-039): every
## bot station submits real commands of its own station only, the lesson still plays to its
## end, each scripted half shows on the player's partner glance card, and a seed fixes the
## whole thing.

const STATIONS: Array[StringName] = [
	&"helm", &"weapons", &"engineering", &"science", &"relay", &"comms", &"captain"
]
const SEED: int = 11
## Ticks after a half starts at which its effect must show on the card.
const SETTLE: int = TrainingPartners.HALF_TICKS + 40

var _ctx: StationContext


func before_test() -> void:
	_ctx = StationFixture.context("helm")


func _rig(solo: StringName) -> ShakedownRig:
	var rig: ShakedownRig = ShakedownRig.new()
	rig.driver = TrainingDriver.new(ShakedownScenario.new(), rig.steps, solo)
	return rig


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


## Plays the player's side until `stop` is true (default: the lesson's end); returns whether
## it stopped that way within the guard.
func _play(
	rig: ShakedownRig, partners: TrainingPartners, solo: StringName, stop: Callable = Callable()
) -> bool:
	_tick(rig, partners, 2)
	for guard: int in 4000:
		if stop.is_valid():
			if stop.call():
				return true
		elif not rig.said("shakedown.all_done").is_empty():
			return true
		var step: TrainingStepDef = rig.driver.current(solo)
		if step != null:
			if step.kind == TrainingStepDef.Kind.COMMAND:
				rig.world.submit(rig.command_for(step.command))
				_tick(rig, partners, 2)
			else:
				_press(rig, partners, solo)
		elif not rig.driver.active_pairs().is_empty():
			if stop.is_valid() and not _wants_press(rig, stop):
				_tick(rig, partners, 30)
			else:
				_press(rig, partners, solo)
		else:
			_tick(rig, partners, 30)
	return false


func _wants_press(_rig: ShakedownRig, _stop: Callable) -> bool:
	return true


func _lesson(solo: StringName) -> Array:
	var rig: ShakedownRig = _rig(solo)
	var partners: TrainingPartners = TrainingPartners.new(SEED)
	partners.crew.record = true
	var done: bool = _play(rig, partners, solo)
	return [rig, partners, done]


# FT: FT-MIS-039
# Every station played alone reaches the end of its whole track and every pair step that names
# it, with the bots acting for the other six.
func test_every_station_completes_its_whole_lesson_with_acting_bots() -> void:
	for solo: StringName in STATIONS:
		var lesson: Array = _lesson(solo)
		var rig: ShakedownRig = lesson[0]
		assert_bool(lesson[2]).override_failure_message(String(solo)).is_true()
		assert_bool(rig.driver.finished(solo)).is_true()


# FT: FT-MIS-039
# A bot submits only commands of its own station, never the player's: across all seven
# lessons every recorded command is of the station that sent it, and none is the player's.
func test_bots_submit_only_commands_of_their_own_station() -> void:
	var total: int = 0
	var stations_seen: Dictionary[StringName, bool] = {}
	for solo: StringName in STATIONS:
		var partners: TrainingPartners = _lesson(solo)[1]
		for row: Array in partners.crew.sent:
			total += 1
			stations_seen[row[1]] = true
			assert_str(String(row[1])).override_failure_message(String(solo)).is_not_equal(
				String(solo)
			)
			assert_str(StationViews.station_of_command(row[2])).is_equal(String(row[1]))
	assert_int(total).is_greater(20)
	# Every crew station but Comms acts in a plain lesson (nobody hails it).
	for station: String in StationViews.CREW:
		if station != "comms":
			(
				assert_bool(stations_seen.has(StringName(station)))
				. override_failure_message(station)
				. is_true()
			)


# FT: FT-MIS-039
# Comms answers a hail that comes in, and only when it is not the player's station.
func test_the_comms_bot_answers_a_hail() -> void:
	for solo: StringName in [&"helm", &"comms"]:
		var rig: ShakedownRig = _rig(solo)
		var partners: TrainingPartners = TrainingPartners.new(SEED)
		_tick(rig, partners, 2)
		var hail: PostCardCommand = StoryFixture.card(StoryTable.Kind.HAIL, &"conv.trader_bluff")
		hail.ship_id = 0
		rig.world.submit(hail)
		_tick(rig, partners, 2 * TrainingCrew.LOOK_TICKS + 4)
		var state: int = rig.world.story.state[0]
		var answered: bool = state == StoryTable.State.ACCEPTED
		assert_bool(answered).override_failure_message(String(solo)).is_equal(solo != &"comms")


# FT: FT-MIS-039
# A bot refuses a command of another station, and any command at the player's.
func test_send_refuses_a_foreign_or_the_players_station() -> void:
	var rig: ShakedownRig = _rig(&"weapons")
	var partners: TrainingPartners = TrainingPartners.new(SEED)
	_tick(rig, partners, 2)
	var crew: TrainingCrew = partners.crew
	assert_bool(crew.send(rig.world, 0, &"helm", FireCommand.new())).is_false()
	assert_bool(crew.send(rig.world, 0, &"weapons", FireCommand.new())).is_false()
	assert_bool(crew.send(rig.world, 0, &"helm", AllStopCommand.new())).is_true()


# FT: FT-MIS-039
# The same seed gives the same commands and the same world; the seed moves the bots' phases.
func test_a_seed_fixes_the_bots_commands_and_the_world() -> void:
	var a: Array = _lesson(&"science")
	var b: Array = _lesson(&"science")
	assert_array(a[1].crew.sent).is_equal(b[1].crew.sent)
	assert_str(a[0].world.state_hash()).is_equal(b[0].world.state_hash())
	var other: TrainingCrew = TrainingCrew.new(SEED + 1)
	assert_dict(other._phase).is_not_equal(a[1].crew._phase)


# --- partner halves ---


func _pair(steps: TrainingStepsDef, intent: StringName) -> TrainingStepDef:
	for s: TrainingStepDef in steps.pairs():
		if s.intent == intent:
			return s
	return null


## The client's view of the world, as the server sends it: the blocks the glance cards read.
func _read(rig: ShakedownRig, readout: String) -> String:
	for kind: int in [
		StationViews.Section.HELM,
		StationViews.Section.ENGINEERING,
		StationViews.Section.SCIENCE,
		StationViews.Section.RELAY,
		StationViews.Section.MOUNTS,
		StationViews.Section.COMMS
	]:
		_ctx.view.blocks[kind] = NetBlock.decode(
			StationViews.BLOCKS[kind], StationViews.block_bytes(kind, rig.world, 0)
		)
	return PartnerGlance.readout(_ctx, readout)


## Plays `solo` to the start of the pair step `intent`; returns the rig and partners.
func _to_pair(solo: StringName, intent: StringName) -> Array:
	var rig: ShakedownRig = _rig(solo)
	var partners: TrainingPartners = TrainingPartners.new(SEED)
	var on: Callable = func() -> bool:
		return rig.driver.active_pairs().any(
			func(s: TrainingStepDef) -> bool: return s.intent == intent
		)
	assert_bool(_play(rig, partners, solo, on)).override_failure_message(String(intent)).is_true()
	return [rig, partners]


# FT: FT-MIS-039
# For every scripted half: at the player's station the partner's glance card carries the
# read-out, and the read-out changes once the partner has done its half; the step then ends on
# the partner's Next as before.
func test_each_scripted_half_changes_the_partner_glance_card() -> void:
	assert_int(TrainingPartners.HALVES.size()).is_greater_equal(6)
	var steps: TrainingStepsDef = ShakedownRig.new().steps
	for key: String in TrainingPartners.HALVES:
		var intent: StringName = StringName(key.get_slice("|", 0))
		var partner: StringName = StringName(key.get_slice("|", 1))
		var step: TrainingStepDef = _pair(steps, intent)
		var solo: StringName = step.station if step.partner == partner else step.partner
		var readout: String = TrainingPartners.HALVES[key][1]
		(
			assert_array(PartnerGlance.card_of(String(partner), String(solo))[0])
			. override_failure_message(key)
			. contains([readout])
		)
		var at: Array = _to_pair(solo, intent)
		var rig: ShakedownRig = at[0]
		var partners: TrainingPartners = at[1]
		var before: String = _read(rig, readout)
		_tick(rig, partners, SETTLE)
		var after: String = _read(rig, readout)
		assert_str(after).override_failure_message("%s: %s" % [key, before]).is_not_equal(before)
		# The step still ends on the partner's Next, after the player's.
		var flag: StringName = TrainingDriver.next_flag(partner)
		_tick(rig, partners, TrainingPartners.press_ticks(step, partner))
		assert_int(rig.world.story_flags.get_flag(flag)).override_failure_message(key).is_greater(0)
