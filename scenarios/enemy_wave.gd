class_name EnemyWave
extends Scenario
## A raider wave at a site (FT-MIS-003, FT-MIS-004, FT-MIS-041, D77): raiders close on the
## crewed ship from ahead. Comms has the beats of a hostile encounter: the raiders hail, taunt
## after a while, and the crew may demand their surrender over the hail card (P9, FT-PAIR-004;
## conv.surrender_demand rolls it). A yes is said as "we surrender" and the raiders' faction
## stands down; a no is said as a refusal and the fight goes on. Branches: the raiders are all
## destroyed or have retreated, they surrendered, or the time ran out. Only the Scenario API
## is used (FT-DAT-007), so a replay needs none of this (FT-ARC-008).

const ENEMY: StringName = &"m1_raider"
const RAIDER_FACTION: int = 2
const NPC: StringName = &"Marauder Kass"
## Raiders in the wave at strength 1, how far out they appear (m) and the clock position of the
## first. The difficulty preset scales the count (Q14, owner 2026-10-26), at least one.
const COUNT: int = 2
const RANGE_M: float = 9000.0
## The second raider joins this long after the first (s), from behind the first's side.
const SECOND_AFTER_S: float = 45.0
const TAUNT_AFTER_S: float = 25.0
const MAX_S: float = 240.0

var _ship: int = -1
var _faction: int = -1
var _raiders: Array[ApiHandle] = []
var _count: int = COUNT
var _hail_offered: bool = false
var _started: int = 0
var _taunted: bool = false
var _surrendered: bool = false
var _done: bool = false


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"enemy_wave"
	m.tags = PackedStringArray(["hostile"])
	m.threat_cost = 3
	m.duration_s = MAX_S
	m.stations = PackedStringArray(["helm", "weapons", "engineering", "comms"])
	m.pairs = PackedStringArray(["p9"])
	m.branches = [
		{"id": "destroyed", "outcome": "won"},
		{"id": "surrendered", "outcome": "won"},
		{"id": "timeout", "outcome": "won"},
	]
	m.comms_beats = PackedStringArray(["hail", "taunt", "surrender"])
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	var ships: PackedInt32Array = params["ships"]
	_ship = ships[0]
	_faction = api.ship(_ship).faction
	_started = api.tick()
	_count = maxi(1, roundi(COUNT * float(params.get("strength", 1.0))))
	api.set_relation(RAIDER_FACTION, _faction, Relation.HOSTILE)
	_raiders.append(api.spawn_at_range(ENEMY, RAIDER_FACTION, _ship, RANGE_M, _clock(api), 0))
	api.message("npc.hail_raider", {"npc": NPC}, SayTarget.npc(NPC, _ship))


func step(api: ScenarioApi) -> void:
	if _done:
		return
	var elapsed_s: float = float(api.tick() - _started) / ScenarioApi.HZ
	_offer_hail(api)
	if not _taunted and elapsed_s >= TAUNT_AFTER_S:
		_taunted = true
		api.message("npc.taunt_raider", {}, SayTarget.npc(NPC, _ship))
	if _raiders.size() < _count and elapsed_s >= SECOND_AFTER_S:
		_raiders.append(api.spawn_at_range(ENEMY, RAIDER_FACTION, _ship, RANGE_M, _clock(api), 0))
	for e: ApiEvent in api.events():
		if e.kind == &"surrender_roll" and e.ship_id == _ship and not _surrendered:
			if e.tag == &"yes":
				_surrendered = true
				api.message("npc.surrender", {}, SayTarget.npc(NPC, _ship))
				api.set_relation(RAIDER_FACTION, _faction, Relation.NEUTRAL)
			else:
				api.message("npc.surrender_refused", {}, SayTarget.npc(NPC, _ship))
	if _surrendered or (_raiders.size() == _count and _raiders_gone(api)) or elapsed_s >= MAX_S:
		_done = true


func finished(_api: ScenarioApi) -> int:
	return Result.WON if _done else Result.ACTIVE


## A clock position near the bow (11, 12 or 1).
func _clock(api: ScenarioApi) -> int:
	return (10 + floori(api.rand(&"enemy_wave") * 3.0)) % 12 + 1


## The raiders' hail card, once the first raider has its id (the spawn applies on the tick
## after start, Q24): the card is about that ship.
func _offer_hail(api: ScenarioApi) -> void:
	if _hail_offered or _raiders[0].pending():
		return
	_hail_offered = true
	if _raiders[0].rejected():
		return
	var hail: CardSpec = CardSpec.new()
	hail.kind = CardSpec.Kind.HAIL
	hail.npc_id = NPC
	hail.title_key = &"comms.card.hail"
	hail.conversation_id = &"conv.surrender_demand"
	hail.target = _raiders[0].id()
	api.offer(_ship, hail)


## Whether no raider of the wave is still in the run (destroyed or retreated).
func _raiders_gone(api: ScenarioApi) -> bool:
	for raider: ApiHandle in _raiders:
		# A spawn queued this tick has no ship yet: it is still to come. One that was
		# rejected never comes.
		if raider.pending():
			return false
		if not raider.rejected() and api.ship(raider.id()).in_play:
			return false
	return true
