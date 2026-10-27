class_name Rescue
extends Scenario
## A distress call (FT-MIS-003, FT-MIS-004, FT-MIS-041): a stranded freighter with raiders
## closing. Comms holds two cards and the crew's choice is which it accepts (D82 style, a
## consequential choice):
## - ESCORT: cover the freighter until the raiders are gone. Paid 400 credits and a gain in
##   standing with the freighter's faction (rep.complete_mission), a loss if it is destroyed.
## - SALVAGE: strip the freighter's cargo, staying near it for a while. Pays more (700) and
##   costs standing with its faction (rep.salvage_wreck).
## Accept neither and the raiders still come, with nothing paid. Whichever is chosen, the
## encounter ends when the raiders are gone. The freighter lies abeam of the arriving ship's
## course, not ahead of it (review 2 H3), and the cards stay on the board until the
## encounter is over (review 2 M2). The difficulty preset scales the raiders (Q14). Only the
## Scenario API is used (FT-DAT-007).

const FREIGHTER: StringName = &"stranded_freighter"
const RAIDER: StringName = &"m1_raider"
const RAIDER_FACTION: int = 2
const FREIGHTER_FACTION: int = 3
const NPC: StringName = &"Calliope"
const ESCORT_TITLE: StringName = &"comms.card.escort"
const SALVAGE_TITLE: StringName = &"comms.card.salvage"
const BROKER: StringName = &"Broker Vale"
const ESCORT_REWARD: int = 400
const SALVAGE_REWARD: int = 700
## The freighter's distance from the ship, abeam of its course (m), when the raiders appear
## (s), how far from the freighter (m), how many of them at strength 1.
const FREIGHTER_RANGE_M: float = 4000.0
const RAIDERS_AFTER_S: float = 20.0
const RAIDER_RANGE_M: float = 9000.0
const RAIDERS: int = 2
const RAIDER_GAP_S: float = 30.0
## Seconds a salvaging ship must spend within SALVAGE_RANGE_M of the freighter.
const SALVAGE_S: float = 8.0
const SALVAGE_RANGE_M: float = 1200.0
const MAX_S: float = 300.0
## The cards outlast the encounter: it settles at MAX_S at the latest, and a lapsed card
## would pay nothing (review 2 M2).
const CARD_S: float = MAX_S + 30.0

var _ship: int = -1
var _faction: int = -1
var _freighter: ApiHandle
var _escort: ApiHandle
var _salvage: ApiHandle
var _raiders: Array[ApiHandle] = []
var _raider_count: int = RAIDERS
var _offered: bool = false
var _started: int = 0
var _near_ticks: int = 0
var _done: bool = false


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"rescue"
	m.tags = PackedStringArray(["hostile", "rescue"])
	m.threat_cost = 2
	m.duration_s = MAX_S
	m.stations = PackedStringArray(["helm", "weapons", "engineering", "comms"])
	m.pairs = PackedStringArray([])
	m.branches = [
		{"id": "escort_done", "outcome": "won"},
		{"id": "escort_failed", "outcome": "won"},
		{"id": "salvage_done", "outcome": "won"},
		{"id": "ignored", "outcome": "won"},
	]
	m.comms_beats = PackedStringArray(["distress"])
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	var ships: PackedInt32Array = params["ships"]
	_ship = ships[0]
	var view: ShipView = api.ship(_ship)
	_faction = view.faction
	_started = api.tick()
	_raider_count = maxi(1, roundi(RAIDERS * float(params.get("strength", 1.0))))
	api.set_relation(FREIGHTER_FACTION, _faction, Relation.FRIENDLY)
	api.set_relation(FREIGHTER_FACTION, RAIDER_FACTION, Relation.HOSTILE)
	api.set_relation(RAIDER_FACTION, _faction, Relation.HOSTILE)
	_freighter = api.spawn_at_offset(
		FREIGHTER, FREIGHTER_FACTION, _ship, _abeam(view.velocity) * FREIGHTER_RANGE_M
	)
	api.message("npc.distress", {"npc": NPC}, SayTarget.npc(NPC, _ship))


## The unit direction at right angles to the course (level with it), or +X for a ship at
## rest: a ship coming in at speed passes a point so placed at the full distance.
static func _abeam(velocity: Vector3) -> Vector3:
	if velocity.length() < 1.0:
		return Vector3.RIGHT
	var side: Vector3 = velocity.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = velocity.cross(Vector3.RIGHT)
	return side.normalized()


## The two cards, once the freighter has its id (the spawn applies on the tick after start,
## Q24): both are about it.
func _offer_cards(api: ScenarioApi) -> void:
	var freighter: int = _freighter.id()
	_offered = true
	var escort: CardSpec = CardSpec.new()
	escort.kind = CardSpec.Kind.CONTRACT
	escort.npc_id = NPC
	escort.title_key = ESCORT_TITLE
	escort.conversation_id = &"conv.rescue_escort"
	escort.reward_credits = ESCORT_REWARD
	escort.rep_interaction = &"rep.complete_mission"
	escort.target = freighter
	escort.target_flag = 2
	escort.expires_s = CARD_S
	_escort = api.offer(_ship, escort)
	var salvage: CardSpec = CardSpec.new()
	salvage.kind = CardSpec.Kind.OFFER
	salvage.npc_id = BROKER
	salvage.title_key = SALVAGE_TITLE
	salvage.conversation_id = &"conv.rescue_salvage"
	salvage.reward_credits = SALVAGE_REWARD
	salvage.rep_interaction = &"rep.salvage_wreck"
	salvage.target = freighter
	salvage.expires_s = CARD_S
	_salvage = api.offer(_ship, salvage)


func step(api: ScenarioApi) -> void:
	if _done:
		return
	if _freighter.rejected():
		_done = true
		return
	if not _offered and not _freighter.pending():
		_offer_cards(api)
	var elapsed_s: float = float(api.tick() - _started) / ScenarioApi.HZ
	# The raiders come one after the other, RAIDER_GAP_S apart, once the freighter exists.
	if (
		_offered
		and _raiders.size() < _raider_count
		and elapsed_s >= RAIDERS_AFTER_S + RAIDER_GAP_S * _raiders.size()
	):
		var clock: int = 10 + 2 * _raiders.size()
		_raiders.append(
			api.spawn_at_range(RAIDER, RAIDER_FACTION, _freighter.id(), RAIDER_RANGE_M, clock, 0)
		)
	if _raiders.size() < _raider_count:
		if elapsed_s >= MAX_S:
			_settle(api)
		return
	var salvaging: bool = _state(api, _salvage) == CardView.State.ACCEPTED
	if salvaging and api.distance(_ship, _freighter.id()) <= SALVAGE_RANGE_M:
		_near_ticks += 1
	if _raiders_gone(api) or elapsed_s >= MAX_S:
		_settle(api)


func finished(_api: ScenarioApi) -> int:
	return Result.WON if _done else Result.ACTIVE


## Pays out and ends: the accepted card is settled by how it went.
func _settle(api: ScenarioApi) -> void:
	_done = true
	if _state(api, _escort) == CardView.State.ACCEPTED:
		var saved: bool = api.ship(_freighter.id()).in_play
		api.settle_card(_escort.id(), saved)
		if saved:
			api.message("npc.rescue_thanks", {}, SayTarget.npc(NPC, _ship))
	elif _state(api, _salvage) == CardView.State.ACCEPTED:
		api.settle_card(_salvage.id(), _near_ticks >= ceili(SALVAGE_S * ScenarioApi.HZ))


## The state of the card a write posted, or EXPIRED while it isn't on the board.
func _state(api: ScenarioApi, card: ApiHandle) -> int:
	if card == null or card.id() < 0:
		return CardView.State.EXPIRED
	for c: CardView in api.cards_of(_ship):
		if c.id == card.id():
			return c.state
	return CardView.State.EXPIRED


func _raiders_gone(api: ScenarioApi) -> bool:
	for raider: ApiHandle in _raiders:
		# A spawn queued this tick has no ship yet: it is still to come. One that was
		# rejected never comes.
		if raider.pending():
			return false
		if not raider.rejected() and api.ship(raider.id()).in_play:
			return false
	return true
