extends GdUnitTestSuite
## Review fixes for STORY (#10 m3-r): a refused accept draws nothing, a rewarding reply is
## paid once, a hail can be closed, a docked requirement checks the replying ship, a dock
## before the first card is not an arrival, and malformed card or jump commands are
## refused.

const BLUE: int = StoryFixture.BLUE
const RED: int = StoryFixture.RED
const SITE: int = StoryFixture.SITE


func _reply(w: SimWorld, ship: int, card: int, option: StringName) -> bool:
	var c: ReplyCommand = ReplyCommand.new()
	c.card = card
	c.option = option
	return StoryFixture.run(w, ship, c)


func _answer(w: SimWorld, ship: int, card: int) -> bool:
	var c: AnswerHailCommand = AnswerHailCommand.new()
	c.card = card
	return StoryFixture.run(w, ship, c)


func _contract(w: SimWorld, requires_docked: bool = false) -> int:
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT, &"conv.escort_contract")
	spec.target = 1
	spec.requires_docked = requires_docked
	spec.site = SITE if requires_docked else -1
	return StoryFixture.post(w, 0, spec)


# FT: FT-COM-003, FT-COM-007
# A reply whose accept is refused draws no reputation and leaves the conversation open.
func test_refused_accept_draws_nothing() -> void:
	var w: SimWorld = StoryFixture.duel()
	var card: int = _contract(w, true)
	assert_bool(_answer(w, 0, card)).is_true()
	assert_bool(_reply(w, 0, card, &"o1")).is_false()
	assert_int(w.reputation.row_for(BLUE, RED)).is_equal(-1)
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	assert_str(w.story.node[card]).is_equal("n0")
	StoryFixture.dock(w, 0)
	assert_bool(_reply(w, 0, card, &"o1")).is_true()
	assert_int(w.story.state[card]).is_equal(StoryTable.State.ACCEPTED)
	assert_int(w.reputation.row_for(BLUE, RED)).is_greater_equal(0)


# FT: FT-COM-003, FT-COM-007
# An accepted card's conversation, reopened, cannot pay the accept reward again.
func test_accepted_card_cannot_repeat_its_reward() -> void:
	var w: SimWorld = StoryFixture.duel()
	var card: int = _contract(w)
	assert_bool(_answer(w, 0, card)).is_true()
	assert_bool(_reply(w, 0, card, &"o1")).is_true()
	var paid: float = w.reputation.value_of(BLUE, RED)
	assert_bool(_answer(w, 0, card)).is_true()
	for i: int in 5:
		assert_bool(_reply(w, 0, card, &"o1")).is_false()
	assert_float(w.reputation.value_of(BLUE, RED)).is_equal(paid)


# FT: FT-COM-002, FT-COM-007
# A DONE hail can be hailed again but the bluff call draws its reputation once per contact.
func test_repeated_hails_draw_the_bluff_call_once() -> void:
	var w: SimWorld = StoryFixture.duel()
	var last: float = 0.0
	for round: int in 3:
		var hail: HailCommand = HailCommand.new()
		hail.target = 1
		assert_bool(StoryFixture.run(w, 0, hail)).is_true()
		Story.learn_fact(w, BLUE, 1, "cargo")
		assert_bool(_reply(w, 0, round, &"o3")).is_true()
		if round == 0:
			last = w.reputation.value_of(BLUE, RED)
			assert_float(last).is_not_equal(0.0)
		else:
			assert_float(w.reputation.value_of(BLUE, RED)).is_equal(last)
		var done: DeclineCardCommand = DeclineCardCommand.new()
		done.card = round
		assert_bool(StoryFixture.run(w, 0, done)).is_true()
		assert_int(w.story.state[round]).is_equal(StoryTable.State.DONE)


# FT: FT-COM-002
# An answered hail whose node has no closing option is closed by declining, so the contact
# can be hailed again.
func test_declining_closes_an_answered_hail() -> void:
	var w: SimWorld = StoryFixture.duel()
	var hail: HailCommand = HailCommand.new()
	hail.target = 1
	assert_bool(StoryFixture.run(w, 0, hail)).is_true()
	var again: HailCommand = HailCommand.new()
	again.target = 1
	assert_bool(StoryFixture.run(w, 0, again)).is_false()
	var close: DeclineCardCommand = DeclineCardCommand.new()
	close.card = 0
	assert_bool(StoryFixture.run(w, 0, close)).is_true()
	assert_int(w.story.state[0]).is_equal(StoryTable.State.DONE)
	var third: HailCommand = HailCommand.new()
	third.target = 1
	assert_bool(StoryFixture.run(w, 0, third)).is_true()


# FT: FT-COM-007, FT-MIS-036
# A docked requirement checks the ship that replies, also on a faction-wide card.
func test_docked_requirement_checks_the_replying_ship() -> void:
	var w: SimWorld = StoryFixture.duel()
	var mate: int = StoryFixture.spawn(w, TestDefs.corvette(), BLUE, Vector3(100.0, 0.0, 0.0))
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION)
	spec.faction_wide = true
	var card: int = StoryFixture.post(w, 0, spec)
	StoryFixture.dock(w, mate)
	var req: Dictionary = {"docked": true}
	assert_bool(Story.requirement_met(w, card, req, mate)).is_true()
	assert_bool(Story.requirement_met(w, card, req, 0)).is_false()
	assert_bool(Story.requirement_met(w, card, {"docked": false}, 0)).is_true()
	assert_bool(Story.requirement_met(w, card, req, -1)).is_false()


# FT: FT-PAIR-001
# Docking before any card exists is not an arrival once a clearance for the site is posted.
func test_early_dock_does_not_fail_a_later_clearance() -> void:
	var w: SimWorld = StoryFixture.duel()
	StoryFixture.dock(w, 0)
	w.step()
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.OFFER, &"", SITE)
	spec.lane_open_s = 1.0
	spec.lane_s = 5.0
	spec.rep_faction = RED
	var card: int = StoryFixture.post(w, 0, spec)
	SimFixture.run(w, 5)
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	assert_int(w.reputation.row_for(BLUE, RED)).is_equal(-1)


# FT: FT-COM-001
# A card with an unknown target flag, or half-set power terms, is rejected.
func test_malformed_cards_are_rejected() -> void:
	var w: SimWorld = StoryFixture.duel()
	var flag: PostCardCommand = StoryFixture.card(StoryTable.Kind.OFFER)
	flag.target_flag = 9
	assert_bool(StoryFixture.run(w, 0, flag)).is_false()
	var pips: PostCardCommand = StoryFixture.card(StoryTable.Kind.OFFER)
	pips.needs_pips = 2
	assert_bool(StoryFixture.run(w, 0, pips)).is_false()
	var neg: PostCardCommand = StoryFixture.card(StoryTable.Kind.OFFER)
	neg.needs_subsystem = &"engines"
	neg.needs_pips = -1
	assert_bool(StoryFixture.run(w, 0, neg)).is_false()
	assert_int(w.story.size()).is_equal(0)
	var ok: PostCardCommand = StoryFixture.card(StoryTable.Kind.OFFER)
	ok.needs_subsystem = &"engines"
	ok.needs_pips = 2
	assert_bool(StoryFixture.run(w, 0, ok)).is_true()


# FT: FT-SIM-034
# A jump with a target kind outside the enum is rejected.
func test_jump_rejects_an_unknown_target_kind() -> void:
	var w: SimWorld = StoryFixture.duel()
	var jump: JumpCommand = JumpCommand.new()
	jump.target_kind = 2
	jump.x = 1000.0
	assert_bool(StoryFixture.run(w, 0, jump)).is_false()
	assert_int(w.helm.jump_left[0]).is_equal(0)


# FT: FT-ARC-008
# A command for a ship spawned earlier in the same tick's batch is applied and logged.
func test_command_for_a_ship_spawned_this_tick_applies() -> void:
	var w: SimWorld = StoryFixture.duel()
	var enemy: EnemyDef = TestDefs.raider_enemy()
	w.catalog = {&"raider": enemy}
	var spawn: SpawnShipCommand = SpawnShipCommand.new()
	spawn.enemy_key = &"raider"
	spawn.faction = RED
	var id: int = w.ship_count()
	w.submit(spawn)
	var help: AllStopCommand = AllStopCommand.new()
	help.ship_id = id
	w.submit(help)
	w.step()
	assert_bool(spawn.accepted).is_true()
	assert_bool(w.command_log.has(help)).is_true()
	assert_int(w.ship_count()).is_equal(id + 1)


# FT: FT-COM-003, FT-COM-007
# Review 2 L7: an option whose accept is refused applies none of its effects, also the ones
# listed before the accept, and the scan_option event of its requirement is not counted.
func test_a_refused_accept_applies_no_earlier_effect() -> void:
	var w: SimWorld = StoryFixture.duel()
	w.conversations[&"conv.effects_first"] = {
		"id": "conv.effects_first",
		"start": "n0",
		"nodes":
		{
			"n0":
			{
				"line": "x",
				"options":
				[
					{
						"id": "o1",
						"text": "t",
						"requires": {},
						"effects":
						[
							{"flag": "early", "value": 1},
							{"intent": "neutral"},
							{"rep": "rep.complete_mission"},
							{"accept": true}
						]
					}
				]
			}
		}
	}
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT, &"conv.effects_first")
	spec.target = 1
	spec.requires_docked = true
	spec.site = SITE
	var card: int = StoryFixture.post(w, 0, spec)
	assert_bool(_answer(w, 0, card)).is_true()
	assert_bool(_reply(w, 0, card, &"o1")).is_false()
	assert_int(w.story_flags.get_flag(&"early")).is_equal(0)
	assert_int(w.knowledge.intent[w.knowledge.row_for(BLUE, 1)]).is_equal(
		KnowledgeTable.Intent.UNKNOWN
	)
	assert_int(w.reputation.row_for(BLUE, RED)).is_equal(-1)
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	StoryFixture.dock(w, 0)
	assert_bool(_reply(w, 0, card, &"o1")).is_true()
	assert_int(w.story_flags.get_flag(&"early")).is_equal(1)


# FT: FT-COM-003
# Q23, owner 2026-10-26: an INFO card tells and can't be accepted; it stays on the board.
func test_an_info_card_cannot_be_accepted() -> void:
	var w: SimWorld = StoryFixture.duel()
	var card: int = StoryFixture.post(w, 0, StoryFixture.card(StoryTable.Kind.INFO))
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = card
	assert_bool(StoryFixture.run(w, 0, accept)).is_false()
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	assert_int(StoryFixture.events(w, &"card_refused").size()).is_equal(1)
