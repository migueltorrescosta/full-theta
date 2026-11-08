class_name Scenario
extends RefCounted
## Base of every scenario (FT-DAT-006, D64): a typed class in scenarios/ that plays one
## encounter through the Scenario API only (FT-DAT-007). The director picks one by its
## meta(), start()s it with parameters, steps it every tick while its encounter is active
## and ends the encounter when finished() reports a result.

## The ending of an encounter, the same numbers as EncounterTable.Result (a test checks).
## finished() returns ACTIVE while the scenario goes on. PARTIAL: the time ran out before
## the objective was met; the encounter ends with lower pay.
enum Result { PENDING, ACTIVE, WON, LOST, FLED, ABANDONED, PARTIAL }

## The relations set_relation takes, the same numbers as SimWorld.Relation (a test checks).
enum Relation { FRIENDLY, NEUTRAL, HOSTILE }


## A new instance for one encounter, so two encounters never share state. The default is a
## new object of the same class; a scenario configured after construction overrides it.
func fresh() -> Scenario:
	return (get_script() as GDScript).new()


## The declared metadata (constant): what the director budgets and what the lint checks.
func meta() -> ScenarioMeta:
	return null


## Sets the encounter up through the API; `params` are the director's parameters (for
## example the site id and the crewed ships in "site" and "ships").
func start(_api: ScenarioApi, _params: Dictionary) -> void:
	pass


## Called every tick while the encounter is active.
func step(_api: ScenarioApi) -> void:
	pass


## Result.ACTIVE while going on, else the ending.
func finished(_api: ScenarioApi) -> int:
	return Result.ACTIVE


## The encounter is over with `result` (every kind of ending, the scenario's own included):
## the cards it posted must not be left to lapse (A8). Called once by the director, only for a
## scenario that started; a scenario that settled itself has nothing left to do.
func end(_api: ScenarioApi, _result: int) -> void:
	pass


## The ships a scenario serves: those of `ships` still in the fight, else all of them (a
## scenario that ends the moment it starts has none left). The first is where its lines and
## cards are addressed (A2).
static func fleet(api: ScenarioApi, ships: PackedInt32Array) -> PackedInt32Array:
	var engaged: PackedInt32Array = api.engaged(ships)
	return engaged if not engaged.is_empty() else ships


## The raider count of a wave of `base` at `strength`, at least one and at most `cap` (the
## encounter must be able to finish inside its time limit).
static func count_for(base: int, strength: float, cap: int = 1 << 20) -> int:
	return clampi(roundi(base * strength), 1, cap)


## Seconds since tick `since`.
static func seconds_since(api: ScenarioApi, since: int) -> float:
	return float(api.tick() - since) / ScenarioApi.HZ
