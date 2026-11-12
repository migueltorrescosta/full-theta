class_name EnemyWave
extends Scenario
## A raider wave at a site (FT-MIS-003, FT-MIS-004, FT-MIS-041, D77): raiders close on the
## crewed ship from ahead. Comms has the beats of a hostile encounter: the raiders hail, taunt
## after a while, and the crew may demand their surrender over the hail card (P9, FT-PAIR-004;
## conv.surrender_demand rolls it). A yes is said as "we surrender" and the raiders' faction
## stands down; a no is said as a refusal and the fight goes on. Branches: the raiders are all
## destroyed or have retreated, they surrendered (both won), or the time ran out (partial):
## the encounter ends but the raiders still in the run stay hostile and keep after the ship.
## The whole fleet is served (A2): the hail card is faction-wide, so any ship's Comms can
## demand the surrender, a yes from any of them ends it, and the lines go to every ship still
## in the fight; the raiders arrive from the ship that is first in the fight.
## Only the Scenario API is used (FT-DAT-007), so a replay needs none of this (FT-ARC-008).

const NPC: StringName = &"Marauder Kass"
## Raiders in the wave at strength 1, how far out they appear (m) and the clock position of the
## first. The difficulty preset scales the count (Q14, owner 2026-10-26), at least one.
const COUNT: int = 2
## The second raider joins this long after the first (s), from behind the first's side, and
## each further one this long after the one before.
const SECOND_AFTER_S: float = 45.0
const NEXT_EVERY_S: float = 15.0
const TAUNT_AFTER_S: float = 25.0
const MAX_S: float = 240.0

var _ships: PackedInt32Array = PackedInt32Array()
var _faction: int = -1
var _raiders: Array[ApiHandle] = []
var _count: int = COUNT
var _hail_offered: bool = false
var _hail: ApiHandle
var _started: int = 0
var _taunted: bool = false
var _surrendered: bool = false
var _result: int = Result.ACTIVE


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"enemy_wave"
	m.tags = PackedStringArray(["hostile"])
	m.threat_cost = 3
	m.comms_beats = PackedStringArray(["hail", "taunt", "surrender"])
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	_ships = params["ships"]
	_faction = api.faction_of(_ships[0])
	_started = api.tick()
	_count = Scenario.count_for(COUNT, float(params.get("strength", 1.0)))
	api.set_relation(Factions.RAIDER, _faction, Relation.HOSTILE)
	_raiders.append(_spawn(api))
	_say(api, "npc.hail_raider", {"npc": NPC})


func step(api: ScenarioApi) -> void:
	if _result != Result.ACTIVE:
		return
	var elapsed_s: float = Scenario.seconds_since(api, _started)
	_offer_hail(api)
	if not _taunted and elapsed_s >= TAUNT_AFTER_S:
		_taunted = true
		_say(api, "npc.taunt_raider", {})
	if (
		_raiders.size() < _count
		and elapsed_s >= SECOND_AFTER_S + NEXT_EVERY_S * (_raiders.size() - 1)
	):
		_raiders.append(_spawn(api))
	for e: ApiEvent in api.events():
		if e.kind == &"surrender_roll" and _ships.has(e.ship_id) and not _surrendered:
			if e.tag == &"yes":
				_surrendered = true
				_say(api, "npc.surrender", {})
				api.set_relation(Factions.RAIDER, _faction, Relation.NEUTRAL)
			else:
				_say(api, "npc.surrender_refused", {})
	if _surrendered or (_raiders.size() == _count and api.all_gone(_raiders)):
		_result = Result.WON
	elif elapsed_s >= MAX_S:
		# The raiders are left as they are: hostile, in the run, still after the ship.
		_result = Result.PARTIAL


func finished(_api: ScenarioApi) -> int:
	return _result


## However it ended (a flee or a loss included), the hail card does not linger.
func end(api: ScenarioApi, _result_value: int) -> void:
	if _hail != null:
		api.decline_card(_hail.id())


## A raider at range from the first ship still in the fight.
func _spawn(api: ScenarioApi) -> ApiHandle:
	var lead: int = Scenario.fleet(api, _ships)[0]
	return api.spawn_at_range(
		Factions.RAIDER_KEY, Factions.RAIDER, lead, Factions.RAIDER_RANGE_M, _clock(api), 0
	)


## A line from the raiders to every ship still in the fight.
func _say(api: ScenarioApi, line: String, args: Dictionary) -> void:
	for ship: int in Scenario.fleet(api, _ships):
		api.message(line, args, LineAudience.npc(NPC, ship))


## A clock position near the bow (11, 12 or 1).
func _clock(api: ScenarioApi) -> int:
	return Scenario.clock_slot(10 + floori(api.rand(&"enemy_wave") * 3.0))


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
	hail.subject = _raiders[0].id()
	hail.faction_wide = true
	_hail = api.offer(Scenario.fleet(api, _ships)[0], hail)
