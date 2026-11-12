class_name PackWave
extends Scenario
## A content pack's encounter (FT-DAT-015, D472): a wave of one NPC type that closes on the
## crewed ship from ahead, like EnemyWave without the surrender card. Comms has two beats:
## the NPCs hail when they arrive and taunt after a while (FT-MIS-041). Branches: every NPC
## destroyed or retreated (won), or the time ran out (partial; the rest stay hostile).
## The numbers come from the pack's JSON (ContentPacks checks them); without a pack the
## defaults are a two-raider wave, which no run lists. Only the Scenario API is used
## (FT-DAT-007).

## The defaults and the pack keys (s for times; ContentPacks.ENCOUNTER_RANGES has the ranges).
const DEFAULTS: Dictionary = {
	"id": &"pack_wave",
	"ship": Factions.RAIDER_KEY,
	"name": "Marauder Kass",
	"count": 2,
	"threat_cost": 3,
	"second_after": 45.0,
	"next_every": 15.0,
	"taunt_after": 25.0,
	"time_limit": 240.0,
}

var spec: Dictionary = DEFAULTS.duplicate()
var _ships: PackedInt32Array = PackedInt32Array()
var _npcs: Array[ApiHandle] = []
var _count: int = 1
var _started: int = 0
var _taunted: bool = false
var _result: int = Result.ACTIVE


## A wave configured by `pack_spec` (the keys of DEFAULTS; missing ones keep the default).
static func of(pack_spec: Dictionary) -> PackWave:
	var w: PackWave = PackWave.new()
	w.spec.merge(pack_spec, true)
	return w


func fresh() -> Scenario:
	return PackWave.of(spec)


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = StringName(spec["id"])
	m.tags = PackedStringArray(["hostile"])
	m.threat_cost = int(spec["threat_cost"])
	m.comms_beats = PackedStringArray(["hail", "taunt"])
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	_ships = params["ships"]
	_started = api.tick()
	_count = Scenario.count_for(int(spec["count"]), float(params.get("strength", 1.0)))
	api.set_relation(Factions.RAIDER, api.faction_of(_ships[0]), Relation.HOSTILE)
	_npcs.append(_spawn(api))
	_say(api, "npc.hail_raider", {"npc": spec["name"]})


func step(api: ScenarioApi) -> void:
	if _result != Result.ACTIVE:
		return
	var elapsed: float = Scenario.seconds_since(api, _started)
	if not _taunted and elapsed >= float(spec["taunt_after"]):
		_taunted = true
		_say(api, "npc.taunt_raider", {})
	var due: float = float(spec["second_after"]) + float(spec["next_every"]) * (_npcs.size() - 1)
	if _npcs.size() < _count and elapsed >= due:
		_npcs.append(_spawn(api))
	if _npcs.size() == _count and api.all_gone(_npcs):
		_result = Result.WON
	elif elapsed >= float(spec["time_limit"]):
		_result = Result.PARTIAL


func finished(_api: ScenarioApi) -> int:
	return _result


func _spawn(api: ScenarioApi) -> ApiHandle:
	var lead: int = Scenario.fleet(api, _ships)[0]
	var clock: int = Scenario.clock_slot(10 + floori(api.rand(&"pack_wave") * 3.0))
	return api.spawn_at_range(
		StringName(spec["ship"]), Factions.RAIDER, lead, Factions.RAIDER_REACH, clock, 0
	)


func _say(api: ScenarioApi, line: String, args: Dictionary) -> void:
	for ship: int in Scenario.fleet(api, _ships):
		api.message(line, args, LineAudience.npc(StringName(spec["name"]), ship))
