class_name Finale
extends Scenario
## The run's finale (gp-06, D3): a boss wave at a final site, a heavy raider dead ahead and
## its raider escorts, who join either side of it on enemy_wave's timing (the first after
## 45 s, then one every 15 s). Comms has the beats of enemy_wave: the boss
## hails, taunts after a while, and the crew may demand its surrender over the hail card
## (conv.surrender_demand). The director plays it last, outside the budget, at strength
## preset x ramp_end; winning it closes the run. Branches: every raider of the wave is
## destroyed or has retreated, or the boss's faction surrendered (both won), or the time ran
## out (partial: the director offers it again after the gap, DirectorDef.finale_tries).
## Parameters besides site, ships and strength: "escorts" (count at strength 1) and
## "time_limit" (s), both from the DirectorDef. Only the Scenario API is used (FT-DAT-007).

const ID: StringName = &"finale"
const NPC: StringName = &"Marauder Kass"
## The boss's content key; the escorts fly the raider (Factions.RAIDER_KEY).
const BOSS_KEY: StringName = &"heavy_raider"
## The escorts' clock positions around the boss's 12, in order (wrapping).
const ESCORT_CLOCKS: Array[int] = [11, 1, 10, 2, 9, 3]

var _ships: PackedInt32Array = PackedInt32Array()
var _faction: int = -1
var _wave: Array[ApiHandle] = []
var _hail: ApiHandle
var _hail_offered: bool = false
var _started: int = 0
var _limit: float = EnemyWave.MAX_S
var _escorts: int = 0
var _taunted: bool = false
var _surrendered: bool = false
var _result: int = Result.ACTIVE


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = ID
	m.tags = PackedStringArray(["hostile"])
	m.threat_cost = 1
	m.comms_beats = PackedStringArray(["hail", "taunt", "surrender"])
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	_ships = params["ships"]
	_faction = api.faction_of(_ships[0])
	_started = api.tick()
	_limit = float(params.get("time_limit", _limit))
	if int(params.get("escorts", 0)) > 0:
		_escorts = Scenario.count_for(int(params["escorts"]), float(params.get("strength", 1.0)))
	api.set_relation(Factions.RAIDER, _faction, Relation.HOSTILE)
	_wave.append(
		api.spawn_at_range(
			BOSS_KEY,
			Factions.RAIDER,
			Scenario.fleet(api, _ships)[0],
			Factions.RAIDER_RANGE_M,
			12,
			0
		)
	)
	_say(api, "npc.hail_raider", {"npc": NPC})


func step(api: ScenarioApi) -> void:
	if _result != Result.ACTIVE:
		return
	_offer_hail(api)
	# The escorts join like a raider wave's second and later raiders, either side of the boss.
	var joined: int = _wave.size() - 1
	if (
		joined < _escorts
		and Scenario.timed_out(
			api, _started, EnemyWave.SECOND_AFTER_S + EnemyWave.NEXT_EVERY_S * joined
		)
	):
		_wave.append(
			api.spawn_at_range(
				Factions.RAIDER_KEY,
				Factions.RAIDER,
				Scenario.fleet(api, _ships)[0],
				Factions.RAIDER_RANGE_M,
				ESCORT_CLOCKS[joined % ESCORT_CLOCKS.size()],
				0
			)
		)
	if not _taunted and Scenario.timed_out(api, _started, EnemyWave.TAUNT_AFTER_S):
		_taunted = true
		_say(api, "npc.taunt_raider", {})
	for e: ApiEvent in api.events():
		if e.kind == &"surrender_roll" and _ships.has(e.ship_id) and not _surrendered:
			if e.tag == &"yes":
				_surrendered = true
				_say(api, "npc.surrender", {})
				api.set_relation(Factions.RAIDER, _faction, Relation.NEUTRAL)
			else:
				_say(api, "npc.surrender_refused", {})
	if _surrendered or (_wave.size() == _escorts + 1 and api.all_gone(_wave)):
		_result = Result.WON
	elif Scenario.timed_out(api, _started, _limit):
		_result = Result.PARTIAL


func finished(_api: ScenarioApi) -> int:
	return _result


func end(api: ScenarioApi, _result_value: int) -> void:
	if _hail != null:
		api.decline_card(_hail.id())


func _say(api: ScenarioApi, line: String, args: Dictionary) -> void:
	for ship: int in Scenario.fleet(api, _ships):
		api.message(line, args, LineAudience.npc(NPC, ship))


## The boss's hail card, once its spawn has applied (Q24).
func _offer_hail(api: ScenarioApi) -> void:
	if _hail_offered or _wave[0].pending():
		return
	_hail_offered = true
	if _wave[0].rejected():
		return
	var hail: CardSpec = CardSpec.new()
	hail.kind = CardSpec.Kind.HAIL
	hail.npc_id = NPC
	hail.title_key = &"comms.card.hail"
	hail.conversation_id = &"conv.surrender_demand"
	hail.subject = _wave[0].id()
	hail.faction_wide = true
	_hail = api.offer(Scenario.fleet(api, _ships)[0], hail)
