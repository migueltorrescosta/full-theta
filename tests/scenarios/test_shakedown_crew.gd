extends GdUnitTestSuite
## The acting bots and scripted partner halves of a solo lesson (D303, FT-MIS-039): every
## bot station submits real commands of its own station only, the lesson still plays to its
## end, each scripted half shows on the player's partner glance card, and a seed fixes the
## whole thing.

const STATIONS: Array[StringName] = ShakedownLessons.STATIONS
const SEED: int = ShakedownLessons.SEED
## Ticks after a half starts at which its effect must show on the card.
const SETTLE: int = TrainingPartners.HALF_TICKS + 40

var _ctx: StationContext


func before_test() -> void:
	_ctx = StationFixture.context("helm")


func _rig(solo: StringName) -> ShakedownRig:
	return ShakedownLessons.rig(solo)


func _tick(rig: ShakedownRig, partners: TrainingPartners, n: int = 1) -> void:
	ShakedownLessons.tick(rig, partners, n)


# FT: FT-MIS-039
# A bot submits only commands of its own station, never the player's: across all seven
# lessons every recorded command is of the station that sent it, and none is the player's.
func test_bots_submit_only_commands_of_their_own_station() -> void:
	var total: int = 0
	var stations_seen: Dictionary[StringName, bool] = {}
	for solo: StringName in STATIONS:
		var partners: TrainingPartners = ShakedownLessons.lesson(solo)["partners"]
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
	var a: Dictionary = ShakedownLessons.lesson(&"science")
	var b: Dictionary = _replayed(&"science")
	assert_array(a["partners"].crew.sent).is_equal(b["partners"].crew.sent)
	assert_str(a["rig"].world.state_hash()).is_equal(b["rig"].world.state_hash())
	var other: TrainingCrew = TrainingCrew.new(SEED + 1)
	assert_dict(other._phase).is_not_equal(a["partners"].crew._phase)


## The lesson of `solo` played a second time (the cached one is the first).
func _replayed(solo: StringName) -> Dictionary:
	var rig: ShakedownRig = _rig(solo)
	var partners: TrainingPartners = TrainingPartners.new(SEED)
	partners.crew.record = true
	ShakedownLessons.play(rig, partners, solo)
	return {"rig": rig, "partners": partners}


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
	(
		assert_int(ShakedownLessons.play(rig, partners, solo, on))
		. override_failure_message(String(intent))
		. is_greater_equal(0)
	)
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
