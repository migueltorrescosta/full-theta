class_name Scenario
extends RefCounted
## Base of every scenario (FT-DAT-006, D64): a typed class in scenarios/ that plays one
## encounter through the Scenario API only (FT-DAT-007). The director picks one by its
## meta(), start()s it with parameters, steps it every tick while its encounter is active
## and ends the encounter when finished() reports a result.

## The ending of an encounter, the same numbers as EncounterTable.Result (a test checks).
## finished() returns ACTIVE while the scenario goes on.
enum Result { PENDING, ACTIVE, WON, LOST, FLED, ABANDONED }

# --- strand E ---
## The relations set_relation takes, the same numbers as SimWorld.Relation (a test checks).
enum Relation { FRIENDLY, NEUTRAL, HOSTILE }
# --- end strand E ---


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
