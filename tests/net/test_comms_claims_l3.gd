extends GdUnitTestSuite
## NPC conversations are claimable (FT-COM-006, D18): over loopback, two Comms players on
## one ship. Only the claimer replies to an NPC; the other sees who holds it in the COMMS
## section. Accepting, declining and trading stay Comms' alone, claimed or not (FT-COM-003).

const PLAYER: int = CommsL3.PLAYER
const ENEMY: int = CommsL3.ENEMY
const ACCEPTED: int = StoryTable.State.ACCEPTED

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## The NPC line of the first open conversation node in the client's COMMS block, or "".
func _line(c: NetClient) -> String:
	var nodes: Array = CommsL3.block(c).get("nodes", [])
	return nodes[0]["line"] if not nodes.is_empty() else ""


func _state(c: NetClient, card: int) -> int:
	return CommsL3.card_row(c, card).get("state", -1)


func _hail_card() -> PostCardCommand:
	var card: PostCardCommand = StoryFixture.card(StoryTable.Kind.HAIL, &"conv.trader_bluff")
	card.target = ENEMY
	return card


# FT: FT-COM-006
# Of two Comms players, the one holding `npc:<card>` replies to that NPC and the other is
# refused with `claimed`; both see the claimer in the card's row, and a released claim is
# free for the other player.
func test_only_the_claimer_replies() -> void:
	var server: NetServer = h.server()
	StoryFixture.wire(server.world)
	var ana: NetClient = await h.joined(server, "ana", "comms")
	var bo: NetClient = await h.joined(server, "bo", "comms")
	CommsL3.post(server, _hail_card())
	CommsL3.post(server, StoryFixture.card(StoryTable.Kind.CONTRACT))
	server.session.launch(PLAYER)
	(
		assert_bool(await h.until(func() -> bool: return not CommsL3.card_row(bo, 1).is_empty()))
		. is_true()
	)
	var open: Dictionary = {"kind": "comms_answer", "card": 0}
	assert_str(await CommsL3.verdict(h, server, ana, open)).is_equal("")
	(
		assert_bool(
			await h.until(func() -> bool: return CommsL3.card_row(bo, 0).get("open", false))
		)
		. is_true()
	)
	# Nobody holds it yet: either may claim; Ana does.
	assert_int(CommsL3.card_row(bo, 0)["claimer"]).is_equal(-1)
	ana.claim("npc:0")
	var ana_id: int = h.session_of(server, ana).id
	(
		assert_bool(
			await h.until(func() -> bool: return CommsL3.card_row(bo, 0)["claimer"] == ana_id)
		)
		. is_true()
	)
	assert_int(CommsL3.card_row(ana, 0)["claimer"]).is_equal(ana_id)
	# The NPC is heard by its claimer alone (G1 routes by this).
	assert_array(Array(server.session.npc_audience("Harbour Master"))).is_equal([ana_id])
	var reply: Dictionary = {"kind": "comms_reply", "card": 0, "option": "o2"}
	assert_str(await CommsL3.verdict(h, server, bo, reply)).is_equal(CommandGate.CLAIMED)
	assert_str(await CommsL3.verdict(h, server, ana, reply)).is_equal("")
	assert_bool(await h.until(func() -> bool: return _line(bo) == "npc.trade_offer")).is_true()
	# The claim moves: Bo can't take what Ana holds, but can after she lets go.
	bo.claim("npc:0")
	var refused: Dictionary = await h.next_event(bo, NetProtocol.EVENT_REQUEST_REJECTED)
	assert_str(refused["payload"]["reason"]).is_equal(CommandGate.CLAIMED)
	ana.release_claim("npc:0")
	(
		assert_bool(
			await h.until(
				func() -> bool: return server.session.npc_audience("Harbour Master").is_empty()
			)
		)
		. is_true()
	)
	(
		assert_bool(await h.until(func() -> bool: return CommsL3.card_row(bo, 0)["claimer"] == -1))
		. is_true()
	)
	(
		assert_str(
			await CommsL3.verdict(h, server, bo, {"kind": "comms_reply", "card": 0, "option": "o5"})
		)
		. is_equal("")
	)


# FT: FT-COM-006, FT-COM-003
# Claims are for conversations that exist: an unknown `npc:` item is refused, and deciding
# a card needs no claim (Bo accepts the contract while Ana holds its conversation).
func test_claims_cover_conversations_not_decisions() -> void:
	var server: NetServer = h.server()
	StoryFixture.wire(server.world)
	var ana: NetClient = await h.joined(server, "ana", "comms")
	var bo: NetClient = await h.joined(server, "bo", "comms")
	var contract: PostCardCommand = StoryFixture.card(
		StoryTable.Kind.CONTRACT, &"conv.escort_contract"
	)
	contract.target = ENEMY
	contract.target_flag = KnowledgeTable.Flag.PROTECT
	CommsL3.post(server, contract)
	CommsL3.post(server, StoryFixture.card(StoryTable.Kind.MISSION))
	server.session.launch(PLAYER)
	(
		assert_bool(await h.until(func() -> bool: return not CommsL3.card_row(bo, 1).is_empty()))
		. is_true()
	)
	var from: int = h.mark(ana)
	ana.claim("npc:1")
	(
		assert_str(
			(await h.next_event(ana, NetProtocol.EVENT_REQUEST_REJECTED, from))["payload"]["reason"]
		)
		. is_equal(ServerSession.BAD_ITEM)
	)
	ana.claim("npc:0")
	var ana_id: int = h.session_of(server, ana).id
	(
		assert_bool(
			await h.until(
				func() -> bool: return CommsL3.card_row(bo, 0).get("claimer", -1) == ana_id
			)
		)
		. is_true()
	)
	assert_str(await CommsL3.verdict(h, server, bo, {"kind": "comms_accept", "card": 0})).is_equal(
		""
	)
	assert_bool(await h.until(func() -> bool: return _state(ana, 0) == ACCEPTED)).is_true()
	assert_str(await CommsL3.verdict(h, server, bo, {"kind": "comms_decline", "card": 1})).is_equal(
		""
	)
