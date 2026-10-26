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
## encounter ends when the raiders are gone. Only the Scenario API is used (FT-DAT-007).

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
## The freighter's distance ahead (m), when the raiders appear (s), how far from it (m), how
## many of them.
const FREIGHTER_RANGE_M: float = 4000.0
const RAIDERS_AFTER_S: float = 20.0
const RAIDER_RANGE_M: float = 9000.0
const RAIDERS: int = 2
const RAIDER_GAP_S: float = 30.0
## Seconds a salvaging ship must spend within SALVAGE_RANGE_M of the freighter.
const SALVAGE_S: float = 8.0
const SALVAGE_RANGE_M: float = 1200.0
const CARD_S: float = 150.0
const MAX_S: float = 300.0

var _ship: int = -1
var _faction: int = -1
var _freighter: int = -1
var _raiders: PackedInt32Array = PackedInt32Array()
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
	_faction = api.ship(_ship).faction
	_started = api.tick()
	api.set_relation(FREIGHTER_FACTION, _faction, Relation.FRIENDLY)
	api.set_relation(FREIGHTER_FACTION, RAIDER_FACTION, Relation.HOSTILE)
	api.set_relation(RAIDER_FACTION, _faction, Relation.HOSTILE)
	_freighter = api.spawn_at_range(FREIGHTER, FREIGHTER_FACTION, _ship, FREIGHTER_RANGE_M, 12, 0)
	api.message("npc.distress", {"npc": NPC}, SayTarget.npc(NPC, _ship))
	var escort: CardSpec = CardSpec.new()
	escort.kind = CardSpec.Kind.CONTRACT
	escort.npc_id = NPC
	escort.title_key = ESCORT_TITLE
	escort.conversation_id = &"conv.rescue_escort"
	escort.reward_credits = ESCORT_REWARD
	escort.rep_interaction = &"rep.complete_mission"
	escort.target = _freighter
	escort.target_flag = 2
	escort.expires_s = CARD_S
	api.offer(_ship, escort)
	var salvage: CardSpec = CardSpec.new()
	salvage.kind = CardSpec.Kind.OFFER
	salvage.npc_id = BROKER
	salvage.title_key = SALVAGE_TITLE
	salvage.conversation_id = &"conv.rescue_salvage"
	salvage.reward_credits = SALVAGE_REWARD
	salvage.rep_interaction = &"rep.salvage_wreck"
	salvage.target = _freighter
	salvage.expires_s = CARD_S
	api.offer(_ship, salvage)


func step(api: ScenarioApi) -> void:
	if _done:
		return
	var elapsed_s: float = float(api.tick() - _started) / ScenarioApi.HZ
	# The raiders come one after the other, RAIDER_GAP_S apart.
	if _raiders.size() < RAIDERS and elapsed_s >= RAIDERS_AFTER_S + RAIDER_GAP_S * _raiders.size():
		var clock: int = 10 + 2 * _raiders.size()
		_raiders.append(
			api.spawn_at_range(RAIDER, RAIDER_FACTION, _freighter, RAIDER_RANGE_M, clock, 0)
		)
	if _raiders.size() < RAIDERS:
		return
	var salvaging: bool = _state(api, SALVAGE_TITLE) == CardView.State.ACCEPTED
	if salvaging and api.distance(_ship, _freighter) <= SALVAGE_RANGE_M:
		_near_ticks += 1
	if _raiders_gone(api) or elapsed_s >= MAX_S:
		_settle(api)


func finished(_api: ScenarioApi) -> int:
	return Result.WON if _done else Result.ACTIVE


## Pays out and ends: the accepted card is settled by how it went.
func _settle(api: ScenarioApi) -> void:
	_done = true
	if _state(api, ESCORT_TITLE) == CardView.State.ACCEPTED:
		var saved: bool = api.ship(_freighter).in_play
		api.settle_card(_card(api, ESCORT_TITLE).id, saved)
		if saved:
			api.message("npc.rescue_thanks", {}, SayTarget.npc(NPC, _ship))
	elif _state(api, SALVAGE_TITLE) == CardView.State.ACCEPTED:
		api.settle_card(
			_card(api, SALVAGE_TITLE).id, _near_ticks >= ceili(SALVAGE_S * ScenarioApi.HZ)
		)


## The state of the card offered under `title` (found by title: an id predicted at offer time
## can be taken by a crew hail applied first), or EXPIRED while it isn't on the board.
func _state(api: ScenarioApi, title: StringName) -> int:
	return _card(api, title).state if _card(api, title) != null else CardView.State.EXPIRED


func _card(api: ScenarioApi, title: StringName) -> CardView:
	for c: CardView in api.cards_of(_ship):
		if c.title_key == String(title) and c.npc_id != &"" and c.target == _freighter:
			return c
	return null


func _raiders_gone(api: ScenarioApi) -> bool:
	for id: int in _raiders:
		var view: ShipView = api.ship(id)
		# A spawn queued this tick has no ship yet: it is still to come.
		if view.id < 0 or view.in_play:
			return false
	return true
