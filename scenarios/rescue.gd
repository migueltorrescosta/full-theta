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
## encounter ends when the raiders are gone, or as partial when the time runs out first: an
## escort whose freighter is still there then pays its partial share (RunDef.partial_pay).
## The freighter lies abeam of the arriving ship's course, not ahead of it (review 2 H3), and
## the cards stay on the board until the encounter is over (review 2 M2). The difficulty
## preset scales the raiders (Q14), at most MAX_RAIDERS so that the last arrives with time to
## fight (R10-6). The whole fleet is served (A2): both cards are faction-wide, the ship that
## accepts one is the one paid, and the freighter lies abeam of the ship first in the fight.
## Accepting one card withdraws the other. Only the Scenario API is used (FT-DAT-007).

const FREIGHTER: StringName = &"stranded_freighter"
const RAIDER: StringName = &"m1_raider"
const RAIDER_FACTION: int = 2
const FREIGHTER_FACTION: int = 3
const NPC: StringName = &"Calliope"
const ESCORT_TITLE: StringName = &"comms.card.escort"
const SALVAGE_TITLE: StringName = &"comms.card.salvage"
const BROKER: StringName = &"Broker Vale"
## Terms of the escort (P12, FT-PAIR-011): the engines must be able to supply this many pips
## when the encounter settles, to keep pace with the freighter. Comms reads them on the
## card and in the NPC's line; only Engineering knows if the ship can (D57, D68).
const ESCORT_NEED: StringName = &"engines"
const ESCORT_NEED_PIPS: int = 2
const ESCORT_REWARD: int = 400
const SALVAGE_REWARD: int = 700
## The freighter's distance from the ship, abeam of its course (m), when the raiders appear
## (s), how far from the freighter (m), how many of them at strength 1.
const FREIGHTER_RANGE_M: float = 4000.0
const RAIDERS_AFTER_S: float = 20.0
const RAIDER_RANGE_M: float = 9000.0
const RAIDERS: int = 2
const RAIDER_GAP_S: float = 30.0
## At most this many raiders: the last one arrives at RAIDERS_AFTER_S + RAIDER_GAP_S * 5 =
## 170 s, which leaves 130 s of the 300 to destroy them. Hard with six ships (5.25 times the
## strength at strength 1) would otherwise ask for 11, the last at 320 s, after the limit.
const MAX_RAIDERS: int = 6
## Seconds a salvaging ship must spend within SALVAGE_RANGE_M of the freighter.
const SALVAGE_S: float = 8.0
const SALVAGE_RANGE_M: float = 1200.0
const MAX_S: float = 300.0
## The cards outlast the encounter: it settles at MAX_S at the latest, and a lapsed card
## would pay nothing (review 2 M2).
const CARD_S: float = MAX_S + 30.0

var _ships: PackedInt32Array = PackedInt32Array()
var _faction: int = -1
var _freighter: ApiHandle
var _escort: ApiHandle
var _salvage: ApiHandle
var _raiders: Array[ApiHandle] = []
var _raider_count: int = RAIDERS
var _offered: bool = false
var _started: int = 0
var _near_ticks: int = 0
var _result: int = Result.ACTIVE


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"rescue"
	m.tags = PackedStringArray(["hostile", "rescue"])
	m.threat_cost = 2
	m.comms_beats = PackedStringArray(["distress"])
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	_ships = params["ships"]
	var lead: int = Scenario.fleet(api, _ships)[0]
	var view: ShipView = api.ship(lead)
	_faction = view.faction
	_started = api.tick()
	_raider_count = raider_count(float(params.get("strength", 1.0)))
	api.set_relation(FREIGHTER_FACTION, _faction, Relation.FRIENDLY)
	api.set_relation(FREIGHTER_FACTION, RAIDER_FACTION, Relation.HOSTILE)
	api.set_relation(RAIDER_FACTION, _faction, Relation.HOSTILE)
	_freighter = api.spawn_at_offset(
		FREIGHTER, FREIGHTER_FACTION, lead, _abeam(view.velocity) * FREIGHTER_RANGE_M
	)
	for ship: int in Scenario.fleet(api, _ships):
		api.message("npc.distress", {"npc": NPC}, SayTarget.npc(NPC, ship))


## The raiders of the encounter at `strength`: RAIDERS scaled, at least 1, at most MAX_RAIDERS.
static func raider_count(strength: float) -> int:
	return Scenario.count_for(RAIDERS, strength, MAX_RAIDERS)


## When the last of `count` raiders arrives (s).
static func last_raider_s(count: int) -> float:
	return RAIDERS_AFTER_S + RAIDER_GAP_S * (count - 1)


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
	escort.detail_key = &"comms.card.escort_terms"
	escort.needs_subsystem = ESCORT_NEED
	escort.needs_pips = ESCORT_NEED_PIPS
	escort.reward_credits = ESCORT_REWARD
	escort.rep_interaction = &"rep.complete_mission"
	escort.target = freighter
	escort.target_flag = 2
	escort.expires_s = CARD_S
	escort.faction_wide = true
	var to: int = Scenario.fleet(api, _ships)[0]
	_escort = api.offer(to, escort)
	var salvage: CardSpec = CardSpec.new()
	salvage.kind = CardSpec.Kind.OFFER
	salvage.npc_id = BROKER
	salvage.title_key = SALVAGE_TITLE
	salvage.conversation_id = &"conv.rescue_salvage"
	salvage.reward_credits = SALVAGE_REWARD
	salvage.rep_interaction = &"rep.salvage_wreck"
	salvage.target = freighter
	salvage.expires_s = CARD_S
	salvage.faction_wide = true
	_salvage = api.offer(to, salvage)


func step(api: ScenarioApi) -> void:
	if _result != Result.ACTIVE:
		return
	if _freighter.rejected():
		_result = Result.WON
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
			_settle(api, Result.PARTIAL)
		return
	_one_card_only(api)
	var salvaging: bool = _state(api, _salvage) == CardView.State.ACCEPTED
	if salvaging and _nearest_to_freighter(api) <= SALVAGE_RANGE_M:
		_near_ticks += 1
	if api.all_gone(_raiders):
		_settle(api, Result.WON)
	elif elapsed_s >= MAX_S:
		_settle(api, Result.PARTIAL)


func finished(_api: ScenarioApi) -> int:
	return _result


## However it ended, a card still open is withdrawn and an accepted one fails: a flee, a loss
## or an abandon does not leave a contract to lapse unpaid and unpunished (A8).
func end(api: ScenarioApi, result: int) -> void:
	var ended_by_other: bool = _result == Result.ACTIVE
	_result = result if ended_by_other else _result
	for card: ApiHandle in [_escort, _salvage]:
		var state: int = _state(api, card)
		if state == CardView.State.ACCEPTED and ended_by_other:
			api.settle_card(card.id(), false)
		elif state == CardView.State.OPEN:
			api.decline_card(card.id())


## The crew's choice is one card: once one is accepted the other is withdrawn.
func _one_card_only(api: ScenarioApi) -> void:
	var escort: int = _state(api, _escort)
	var salvage: int = _state(api, _salvage)
	if escort == CardView.State.ACCEPTED and salvage == CardView.State.OPEN:
		api.decline_card(_salvage.id())
	elif salvage == CardView.State.ACCEPTED and escort == CardView.State.OPEN:
		api.decline_card(_escort.id())


## The distance from the freighter of the nearest ship still in the fight (m).
func _nearest_to_freighter(api: ScenarioApi) -> float:
	var nearest: float = INF
	for ship: int in Scenario.fleet(api, _ships):
		nearest = minf(nearest, api.distance(ship, _freighter.id()))
	return nearest


## Pays out and ends with `result`: the accepted card is settled by how it went; an escort
## cut short by the time (PARTIAL) pays its partial share.
func _settle(api: ScenarioApi, result: int) -> void:
	_result = result
	if _state(api, _escort) == CardView.State.ACCEPTED:
		# A freighter that survives still counts as lost if the engines could not keep pace.
		var saved: bool = api.ship(_freighter.id()).in_play and api.needs_met(_escort.id())
		api.settle_card(_escort.id(), saved, result == Result.PARTIAL)
		if saved:
			for ship: int in Scenario.fleet(api, _ships):
				api.message("npc.rescue_thanks", {}, SayTarget.npc(NPC, ship))
	if _state(api, _salvage) == CardView.State.ACCEPTED:
		var done: bool = _near_ticks >= ceili(SALVAGE_S * ScenarioApi.HZ)
		api.settle_card(_salvage.id(), done, result == Result.PARTIAL)


## The state of the card a write posted, or EXPIRED while it isn't on the board.
func _state(api: ScenarioApi, card: ApiHandle) -> int:
	if card == null or card.id() < 0:
		return CardView.State.EXPIRED
	for c: CardView in api.cards_of(Scenario.fleet(api, _ships)[0]):
		if c.id == card.id():
			return c.state
	return CardView.State.EXPIRED
