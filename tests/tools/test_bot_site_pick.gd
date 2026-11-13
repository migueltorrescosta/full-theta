extends GdUnitTestSuite
## The bot Captain's site pick (E2, w-bzx; FT-TST-022): by the fleet's lowest hull it takes the
## best pay, the best pay less risk or the lowest risk; once per gap, comms_time after
## the list appears, as a SetFlagCommand on the faction's pick flag; never with one offer. The
## batch reads the picks back from the director's log.


func _offer(scenario: StringName, risk: int, reward: int) -> Dictionary:
	return {"site": 1, "name_key": String(scenario), "risk": risk, "reward": reward}


func _offers() -> Array[Dictionary]:
	return [
		_offer(&"enemy_wave", 2, 1),
		_offer(&"rescue", 1, 2),
		_offer(&"debris_leg", 0, 0),
		_offer(&"rescue", 2, 2),
	]


# FT: FT-TST-022
func test_the_pick_follows_the_hull_band() -> void:
	var p: BotProfiles.Profile = BotProfiles.average()
	var list: Array[Dictionary] = _offers()
	# Bold: pay 2 twice, the lower risk wins.
	assert_int(BotCrew.choose(list, 1.0, p)).is_equal(1)
	assert_int(BotCrew.choose(list, 0.75, p)).is_equal(1)
	# Careful: pay less risk is 1 for the rescue at risk 1 (and 0 for the debris leg).
	assert_int(BotCrew.choose(list, 0.6, p)).is_equal(1)
	# Low: the lowest risk.
	assert_int(BotCrew.choose(list, 0.3, p)).is_equal(2)


# FT: FT-TST-022
func test_ties_go_to_the_lower_index() -> void:
	var p: BotProfiles.Profile = BotProfiles.average()
	var same: Array[Dictionary] = [_offer(&"rescue", 1, 2), _offer(&"rescue", 1, 2)]
	for hull: float in [1.0, 0.6, 0.3]:
		assert_int(BotCrew.choose(same, hull, p)).is_equal(0)
	# Careful: wave (1 - 2 = -1) and debris (0 - 0 = 0) and rescue (2 - 2 = 0): the debris leg,
	# at the lower risk.
	var careful: Array[Dictionary] = [
		_offer(&"enemy_wave", 2, 1), _offer(&"rescue", 2, 2), _offer(&"debris_leg", 0, 0)
	]
	assert_int(BotCrew.choose(careful, 0.6, p)).is_equal(2)
	# Low: equal risk, the better pay.
	var low: Array[Dictionary] = [_offer(&"debris_leg", 1, 0), _offer(&"rescue", 1, 2)]
	assert_int(BotCrew.choose(low, 0.3, p)).is_equal(1)


## Steps `world` `seconds` with only the crew acting; returns the pick flag writes it queued.
func _step(world: SimWorld, crew: BotCrew, seconds: float) -> Array[SetFlagCommand]:
	var flags: Array[SetFlagCommand] = []
	for i: int in ceili(seconds * SimWorld.HZ):
		crew.act(world)
		for c: SimCommand in world.queued_commands():
			if c is SetFlagCommand:
				flags.append(c)
		world.step()
	return flags


## A fresh run's world with the average crew of ship 0, its offers from `source`.
func _play(source: Callable, seconds: float) -> Array:
	var world: SimWorld = ServerMain.new().run_setup(DefLibrary.new()).build()
	var crew: BotCrew = BotCrew.new(BotProfiles.average(), 0, 1)
	crew.offers = source
	return [world, crew, _step(world, crew, seconds)]


# FT: FT-TST-022
func test_the_captain_picks_once_per_gap_with_the_pick_flag() -> void:
	var source: Callable = func() -> Array[Dictionary]: return _offers()
	var played: Array = _play(source, BotProfiles.average().comms_time - 1.0)
	assert_array(played[2]).is_empty()  # not before comms_time
	played = _play(source, BotProfiles.average().comms_time * 3.0)
	var world: SimWorld = played[0]
	var flags: Array = played[2]
	assert_int(flags.size()).is_equal(1)
	var flag: SetFlagCommand = flags[0]
	assert_str(String(flag.flag_name)).is_equal(String(Director.pick_flag(world.faction_of(0))))
	assert_int(flag.value).is_equal(2)  # offer 1 at full hull
	assert_int(flag.ship_id).is_equal(-1)
	assert_int(world.story_flags.get_flag(Director.pick_flag(world.faction_of(0)))).is_equal(2)


# FT: FT-TST-022
func test_a_new_gap_gets_a_new_pick() -> void:
	# The same offers in a new gap (its gap flag changed) are a new list.
	var played: Array = _play(func() -> Array[Dictionary]: return _offers(), 0.0)
	var world: SimWorld = played[0]
	var crew: BotCrew = played[1]
	var gap: StringName = Director.gap_flag(world.faction_of(0))
	world.story_flags.set_flag(gap, 1000)
	var flags: Array[SetFlagCommand] = _step(world, crew, crew.profile.comms_time * 2.0)
	world.story_flags.set_flag(gap, 5000)
	flags.append_array(_step(world, crew, crew.profile.comms_time * 2.0))
	assert_int(flags.size()).is_equal(2)


# FT: FT-TST-022
func test_no_pick_with_fewer_than_two_offers() -> void:
	var one: Callable = func() -> Array[Dictionary]: return [_offer(&"rescue", 1, 2)]
	var played: Array = _play(one, BotProfiles.average().comms_time * 3.0)
	assert_array(played[2]).is_empty()
	var none: Callable = func() -> Array[Dictionary]: return []
	assert_array(_play(none, BotProfiles.average().comms_time * 3.0)[2]).is_empty()


static func _decision(
	scenario: StringName, site: int, reason: String, args: Dictionary
) -> DirectorDecision:
	return DirectorDecision.make(
		0,
		0,
		DirectorDecision.Kind.PICK_ENCOUNTER,
		{"scenario_id": scenario, "site": site, "reason": reason, "args": args}
	)


# FT: FT-TST-022
# The batch's per-encounter picked/offered and per-run crew_picks come from the director's log:
# a crew_pick decision names the offers; any other pick (and a rejected begin) none.
func test_the_batch_reads_the_picks_from_the_log() -> void:
	var rows: Array = [
		{"scenario": "rescue", "site": 2},
		{"scenario": "enemy_wave", "site": 3},
		{"scenario": "rescue", "site": 4},
	]
	var picks: Array[DirectorDecision] = [
		_decision(&"rescue", 2, "crew_pick", {"offers": ["debris_leg", "rescue"], "pick": 1}),
		_decision(&"debris_leg", 5, "crew_pick", {"offers": ["debris_leg"], "pick": 0}),
		_decision(&"enemy_wave", 3, "budget_fits", {}),
		_decision(&"rescue", 4, "crew_pick", {"offers": ["rescue", "enemy_wave"], "pick": 0}),
	]
	picks[1].kind = DirectorDecision.Kind.SKIP
	assert_int(BotRun._note_picks(rows, picks)).is_equal(2)
	assert_bool(rows[0]["picked"]).is_true()
	assert_array(rows[0]["offered"]).is_equal(["debris_leg", "rescue"])
	assert_bool(rows[1]["picked"]).is_false()
	assert_array(rows[1]["offered"]).is_empty()
	assert_array(rows[2]["offered"]).is_equal(["rescue", "enemy_wave"])
