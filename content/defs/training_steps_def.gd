class_name TrainingStepsDef
extends Resource
## The Shakedown's step list (FT-MIS-039, D235): every station's track in order, core
## actions first (D232), then the rest of its IntentTable group, then the common rows, one
## control per step; then one pair step per cooperation pair. Read-only at runtime
## (FT-ARC-020). A test checks the list against IntentTable.

@export var id: StringName = &"shakedown"
@export var steps: Array[TrainingStepDef] = []


## The steps of one station's own track, in order (pair steps excluded).
func track(station: StringName) -> Array[TrainingStepDef]:
	var out: Array[TrainingStepDef] = []
	for s: TrainingStepDef in steps:
		if s.station == station and not s.is_pair():
			out.append(s)
	return out


## The pair steps, in order.
func pairs() -> Array[TrainingStepDef]:
	var out: Array[TrainingStepDef] = []
	for s: TrainingStepDef in steps:
		if s.is_pair():
			out.append(s)
	return out


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if steps.is_empty():
		errors.append("steps: needs at least one")
	var seen: Dictionary[String, bool] = {}
	for i: int in steps.size():
		var s: TrainingStepDef = steps[i]
		if not DefCheck.required(errors, "steps[%d]" % i, s):
			continue
		for e: String in s.validate():
			errors.append("steps[%d].%s" % [i, e])
		var key: String = "%s/%s" % [s.station, s.intent]
		if seen.has(key):
			errors.append("steps[%d]: %s listed twice" % [i, key])
		seen[key] = true
	return errors
