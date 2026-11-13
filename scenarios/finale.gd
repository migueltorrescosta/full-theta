class_name Finale
extends EnemyWave
## The run's finale (gp-06, D433): a raider wave whose first ship is a heavy raider dead ahead,
## its raider escorts joining on enemy_wave's timing, with enemy_wave's Comms beats and
## branches (won when the whole wave is gone or surrendered, PARTIAL at the time limit). The
## director plays it last, outside the budget, at strength preset x ramp_end; winning it closes
## the run, a partial or fled one is offered again (DirectorDef.finale_tries). Parameters
## besides site, ships and strength: "escorts" (count at strength 1) and "time_limit" (s),
## both from the DirectorDef.

const ID: StringName = &"finale"
## The boss's content key; the escorts fly the raider (Factions.RAIDER_KEY).
const BOSS_KEY: StringName = &"heavy_raider"


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = super.meta()
	m.id = ID
	m.threat_cost = 1
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	super.start(api, params)
	var escorts: float = float(params.get("escorts", 0.0)) * float(params.get("strength", 1.0))
	_count = 1 + (maxi(1, roundi(escorts)) if escorts > 0.0 else 0)
	_limit = float(params.get("time_limit", _limit))


## The boss first, dead ahead; then raiders as in a wave.
func _spawn(api: ScenarioApi) -> ApiHandle:
	if not _raiders.is_empty():
		return super._spawn(api)
	var lead: int = Scenario.fleet(api, _ships)[0]
	return api.spawn_at_range(BOSS_KEY, Factions.RAIDER, lead, Factions.RAIDER_REACH, 12, 0)
