extends GdUnitTestSuite
## STORY: hails, answers, replies, and accepting or declining alone, on the
## cards of Comms' board. The world comes from StoryFixture; BLUE's corvette is ship 0 and
## RED's raider ship 1.

const BLUE: int = StoryFixture.BLUE
const RED: int = StoryFixture.RED


func _reply(w: SimWorld, card: int, option: StringName) -> bool:
	var c: ReplyCommand = ReplyCommand.new()
	c.card = card
	c.option = option
	return StoryFixture.run(w, 0, c)


func _hail(w: SimWorld, target: int = 1) -> bool:
	var c: HailCommand = HailCommand.new()
	c.target = target
	return StoryFixture.run(w, 0, c)


# FT: FT-COM-001, FT-COM-002, FT-COM-007
# Comms hails a detected contact: a HAIL card opens at the contact's conversation start,
# the NPC speaks its line, and a structured reply closes the conversation and the card.
func test_hail_a_contact_and_reply() -> void:
	var w: SimWorld = StoryFixture.duel()
	w.drain_events()
	assert_bool(_hail(w)).is_true()
	var t: StoryTable = w.story
	assert_int(t.size()).is_equal(1)
	assert_int(t.kind[0]).is_equal(StoryTable.Kind.HAIL)
	assert_int(t.state[0]).is_equal(StoryTable.State.ACCEPTED)
	assert_str(t.node[0]).is_equal("n0")
	assert_str(t.npc[0]).is_equal("Raider")
	assert_int(t.rep_faction[0]).is_equal(RED)
	var say: Array[SimEvent] = StoryFixture.events(w, &"say")
	assert_int(say.size()).is_equal(1)
	assert_str(say[0].tag).is_equal("npc.hail_trader")
	assert_int(say[0].other_id).is_equal(1)
	assert_str(say[0].args["npc_id"]).is_equal("Raider")
	assert_array(Story.npc_names(w)).is_equal(["Raider"])
	# The options are the node's, with the bluff locked until the cargo is scanned.
	var options: Array[Dictionary] = Story.options(w, 0, 0)
	(
		assert_array(options.map(func(o: Dictionary) -> String: return o["id"]))
		. is_equal(["o1", "o2", "o3", "o4"])
	)
	assert_bool(options[2]["enabled"]).is_false()
	assert_bool(options[2]["verify"]).is_true()
	assert_bool(_reply(w, 0, &"o4")).is_true()
	assert_str(t.node[0]).is_equal("")
	assert_int(t.state[0]).is_equal(StoryTable.State.DONE)


# FT: FT-COM-002
# A hail needs a contact the faction detects, with a conversation to answer it, and
# isn't opened twice.
func test_hail_refusals() -> void:
	var w: SimWorld = StoryFixture.duel(1, 90000.0)
	w.drain_events()
	assert_bool(_hail(w)).is_false()
	assert_str(StoryFixture.events(w, &"hail_refused")[0].tag).is_equal("not_detected")
	var near: SimWorld = StoryFixture.duel()
	near.drain_events()
	assert_bool(_hail(near, 0)).is_false()
	assert_bool(_hail(near)).is_true()
	assert_bool(_hail(near)).is_false()
	var why: Array[SimEvent] = StoryFixture.events(near, &"hail_refused")
	assert_str(why[0].tag).is_equal("no_target")
	assert_str(why[1].tag).is_equal("already_talking")
	near.hail_conversations = {}
	near.story.state[0] = StoryTable.State.DONE
	assert_bool(_hail(near)).is_false()
	assert_str(StoryFixture.events(near, &"hail_refused")[0].tag).is_equal("no_answer")


# FT: FT-COM-002, FT-COM-008
# An incoming hail waits OPEN on the board until Comms answers it, once.
func test_answer_an_incoming_hail() -> void:
	var w: SimWorld = StoryFixture.duel()
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.HAIL, &"conv.trader_bluff")
	spec.target = 1
	var card: int = StoryFixture.post(w, 0, spec)
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	assert_str(w.story.node[card]).is_equal("")
	assert_bool(_reply(w, card, &"o4")).override_failure_message("no conversation yet").is_false()
	var answer: AnswerHailCommand = AnswerHailCommand.new()
	answer.card = card
	assert_bool(StoryFixture.run(w, 0, answer)).is_true()
	assert_int(w.story.state[card]).is_equal(StoryTable.State.ACCEPTED)
	assert_str(w.story.node[card]).is_equal("n0")
	var again: AnswerHailCommand = AnswerHailCommand.new()
	again.card = card
	assert_bool(StoryFixture.run(w, 0, again)).is_false()


# FT: FT-COM-007
# Replies are structured choices by option id: an unknown one is refused, one that
# requires a scan fact is refused until Science's fact is in, then it sets the contact's
# intent in KNOW, draws a reputation change and moves on to the next node.
func test_replies_are_structured_choices_with_effects() -> void:
	var w: SimWorld = StoryFixture.duel()
	assert_bool(_hail(w)).is_true()
	assert_bool(_reply(w, 0, &"say anything")).is_false()
	assert_bool(_reply(w, 0, &"o3")).is_false()
	var why: Array[SimEvent] = StoryFixture.events(w, &"reply_refused")
	assert_str(why[0].tag).is_equal("no_option")
	assert_str(why[1].tag).is_equal("requirement")
	Story.learn_fact(w, BLUE, 1, "cargo")
	assert_bool(Story.options(w, 0, 0)[2]["enabled"]).is_true()
	assert_bool(_reply(w, 0, &"o3")).is_true()
	var row: int = w.knowledge.row_for(BLUE, 1)
	assert_int(w.knowledge.intent[row]).is_equal(KnowledgeTable.Intent.BLUFFING)
	assert_str(w.story.node[0]).is_equal("n2")
	assert_float(w.reputation.value_of(BLUE, RED)).is_between(-5.0, 15.0)
	assert_int(w.reputation.row_for(BLUE, RED)).is_greater_equal(0)
	# n2 has no options: the conversation can't go on.
	assert_array(Story.options(w, 0, 0)).is_empty()


# FT: FT-COM-007
# A reply can open another node and ask the crew to verify a scan fact (P14).
func test_reply_moves_between_nodes() -> void:
	var w: SimWorld = StoryFixture.duel()
	assert_bool(_hail(w)).is_true()
	assert_bool(_reply(w, 0, &"o2")).is_true()
	assert_str(w.story.node[0]).is_equal("n1")
	assert_str(w.story.verify[0]).is_equal("cargo")
	assert_bool(_reply(w, 0, &"o5")).is_true()
	assert_str(w.story.node[0]).is_equal("n0")


# FT: FT-COM-003, FT-PAIR-011
# Comms alone accepts or declines contracts: one command, no co-sign. Accepting puts the
# contract's target flag in the faction's KNOW; a settled card can't be accepted again.
func test_accept_and_decline_alone() -> void:
	var w: SimWorld = StoryFixture.duel()
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT)
	spec.target = 1
	spec.target_flag = KnowledgeTable.Flag.DISABLE
	spec.reward_credits = 400
	var one: int = StoryFixture.post(w, 0, spec)
	var two: int = StoryFixture.post(w, 0, StoryFixture.card(StoryTable.Kind.MISSION))
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = one
	assert_bool(StoryFixture.run(w, 0, accept)).is_true()
	assert_int(w.story.state[one]).is_equal(StoryTable.State.ACCEPTED)
	assert_int(w.knowledge.flag[w.knowledge.row_for(BLUE, 1)]).is_equal(KnowledgeTable.Flag.DISABLE)
	var decline: DeclineCardCommand = DeclineCardCommand.new()
	decline.card = two
	assert_bool(StoryFixture.run(w, 0, decline)).is_true()
	assert_int(w.story.state[two]).is_equal(StoryTable.State.DECLINED)
	var again: AcceptCardCommand = AcceptCardCommand.new()
	again.card = two
	assert_bool(StoryFixture.run(w, 0, again)).is_false()
	var missing: AcceptCardCommand = AcceptCardCommand.new()
	missing.card = 99
	assert_bool(StoryFixture.run(w, 0, missing)).is_false()


# FT: FT-COM-003, FT-MIS-036
# A card that needs docking can be accepted only while docked.
func test_card_requiring_docked() -> void:
	var w: SimWorld = StoryFixture.duel()
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT, &"", StoryFixture.SITE)
	spec.requires_docked = true
	var card: int = StoryFixture.post(w, 0, spec)
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = card
	assert_bool(StoryFixture.run(w, 0, accept)).is_false()
	StoryFixture.dock(w, 0)
	var retry: AcceptCardCommand = AcceptCardCommand.new()
	retry.card = card
	assert_bool(StoryFixture.run(w, 0, retry)).is_true()


# FT: FT-COM-007, FT-COM-003
# A reply can accept the card it belongs to: the contract conversation accepts and draws
# the contract reputation; declining closes the card and draws the decline reputation.
func test_contract_conversation_accepts_and_declines() -> void:
	var w: SimWorld = StoryFixture.duel()
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT, &"conv.escort_contract")
	spec.target = 1
	var yes: int = StoryFixture.post(w, 0, spec)
	var no: int = StoryFixture.post(w, 0, spec)
	for card: int in [yes, no]:
		var open: AnswerHailCommand = AnswerHailCommand.new()
		open.card = card
		assert_bool(StoryFixture.run(w, 0, open)).is_true()
		assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	assert_bool(_reply(w, yes, &"o1")).is_true()
	assert_int(w.story.state[yes]).is_equal(StoryTable.State.ACCEPTED)
	assert_float(w.reputation.value_of(BLUE, RED)).is_between(2.0, 10.0)
	var after_yes: float = w.reputation.value_of(BLUE, RED)
	assert_bool(_reply(w, no, &"o2")).is_true()
	assert_int(w.story.state[no]).is_equal(StoryTable.State.DECLINED)
	assert_float(w.reputation.value_of(BLUE, RED)).is_between(after_yes - 3.0, after_yes)


# FT: FT-COM-008
# A card lapses when its time is up, closing its conversation.
func test_cards_expire() -> void:
	var w: SimWorld = StoryFixture.duel()
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION, &"conv.escort_contract")
	spec.expires_s = 1.0
	var card: int = StoryFixture.post(w, 0, spec)
	var open: AnswerHailCommand = AnswerHailCommand.new()
	open.card = card
	assert_bool(StoryFixture.run(w, 0, open)).is_true()
	SimFixture.run(w, 57)
	assert_int(w.story.state[card]).is_equal(StoryTable.State.OPEN)
	SimFixture.run(w, 4)
	assert_int(w.story.state[card]).is_equal(StoryTable.State.EXPIRED)
	assert_str(w.story.node[card]).is_equal("")
	assert_bool(_reply(w, card, &"o1")).is_false()


# FT: FT-COM-001, FT-COM-008
# A faction-wide card is on every ship's board of that faction (D82) and the first to act
# settles it for all; another faction doesn't see it.
func test_faction_wide_cards() -> void:
	var w: SimWorld = StoryFixture.duel()
	var mate: int = StoryFixture.spawn(w, TestDefs.corvette(), BLUE, Vector3(100.0, 0.0, 0.0))
	var spec: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION)
	spec.faction_wide = true
	var card: int = StoryFixture.post(w, 0, spec)
	assert_int(w.story.ship_ids[card]).is_equal(-1)
	assert_bool(Story.visible_to(w, card, 0)).is_true()
	assert_bool(Story.visible_to(w, card, mate)).is_true()
	assert_bool(Story.visible_to(w, card, 1)).is_false()
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = card
	assert_bool(StoryFixture.run(w, mate, accept)).is_true()
	assert_int(w.story.state[card]).is_equal(StoryTable.State.ACCEPTED)
	var foreign: AcceptCardCommand = AcceptCardCommand.new()
	foreign.card = card
	assert_bool(StoryFixture.run(w, 1, foreign)).is_false()


# FT: FT-MIS-042
# A server contract flag lands in the faction's KNOW, before or after detection, and
# only for a contact of another faction.
func test_server_contract_flag() -> void:
	var w: SimWorld = StoryFixture.duel()
	var set_flag: SetContractFlagCommand = SetContractFlagCommand.new()
	set_flag.faction = BLUE
	set_flag.contact = 1
	set_flag.flag = KnowledgeTable.Flag.PROTECT
	set_flag.source = SimCommand.Source.SERVER
	assert_bool(StoryFixture.run(w, 0, set_flag)).is_true()
	assert_int(w.knowledge.flag[w.knowledge.row_for(BLUE, 1)]).is_equal(KnowledgeTable.Flag.PROTECT)
	var own: SetContractFlagCommand = SetContractFlagCommand.new()
	own.faction = BLUE
	own.contact = 0
	own.flag = KnowledgeTable.Flag.DISABLE
	assert_bool(StoryFixture.run(w, 0, own)).is_false()


# FT: FT-ARC-008, FT-COM-001
# Every Comms command round-trips through the command log codec, and the same commands
# in two worlds of the same seed end in the same state hash.
func test_commands_replay_to_the_same_state() -> void:
	for cls: GDScript in [
		HailCommand,
		AnswerHailCommand,
		ReplyCommand,
		AcceptCardCommand,
		DeclineCardCommand,
		TradeCommand,
		BuyModuleCommand,
		SellModuleCommand,
		PostCardCommand,
		SetContractFlagCommand,
		CardResultCommand
	]:
		var c: SimCommand = cls.new()
		var back: SimCommand = SimCommands.from_dict(c.to_dict())
		assert_object(back).is_not_null()
		assert_str(back.kind()).is_equal(c.kind())
	var hashes: Array[String] = []
	for i: int in 2:
		var w: SimWorld = StoryFixture.duel(7)
		assert_bool(_hail(w)).is_true()
		Story.learn_fact(w, BLUE, 1, "cargo")
		assert_bool(_reply(w, 0, &"o3")).is_true()
		SimFixture.run(w, 30)
		hashes.append(w.state_hash())
	assert_str(hashes[0]).is_equal(hashes[1])
