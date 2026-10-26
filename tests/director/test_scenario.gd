class_name TestScenario
extends Scenario
## A scripted scenario for the director and run tests: it declares an id and a threat cost,
## optionally spawns one raider 3 km off the ship when it starts, and reports WON after
## `ticks` ticks. It uses the Scenario API only, like a real scenario.

var _id: StringName = &""
var _cost: int = 1
var _spawn: bool = false
var _ticks: int = 60
var _started_at: int = 0
var _hostile: bool = false


static func make(
	id: StringName, cost: int, spawn: bool = false, ticks: int = 60, hostile: bool = false
) -> TestScenario:
	var s: TestScenario = TestScenario.new()
	s._id = id
	s._cost = cost
	s._spawn = spawn
	s._ticks = ticks
	s._hostile = hostile
	return s


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = _id
	m.threat_cost = _cost
	m.duration_s = 10.0
	m.tags = PackedStringArray(["hostile"] if _hostile else ["rescue"])
	m.comms_beats = PackedStringArray(["hail"] if _hostile else [])
	return m


## Copies keep the configuration (the director clones from the catalogue instance by script).
func _init() -> void:
	pass


func start(api: ScenarioApi, params: Dictionary) -> void:
	_started_at = api.tick()
	if _spawn:
		var ships: PackedInt32Array = params["ships"]
		api.spawn_at_range(&"raider", 2, ships[0], 3000.0, 12, 0)


func finished(api: ScenarioApi) -> int:
	return Scenario.Result.WON if api.tick() - _started_at >= _ticks else Scenario.Result.ACTIVE
