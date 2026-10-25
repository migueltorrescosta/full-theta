class_name ChipsDef
extends Resource
## The request-chip list and the CUE expiry every chip shares (spec §7.1, §7.4,
## FT-PAIR-013, FT-PAIR-021). One definition for the whole game, read-only at runtime
## (FT-ARC-020).

@export var id: StringName = &"chips"
@export var chips: Array[ChipDef] = []
## An unanswered chip goes away silently after this long (s of sim time).
@export var expiry_s: float = 0.0
## Most chips open on one ship at a time (count).
@export var max_open: int = 0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.positive(errors, "expiry_s", expiry_s)
	if max_open < 1 or max_open > 255:
		errors.append("max_open: must be in 1..255, got %d" % max_open)
	if chips.size() > 255:
		errors.append("chips: at most 255")
	var seen: Dictionary[StringName, bool] = {}
	for i: int in chips.size():
		var c: ChipDef = chips[i]
		if not DefCheck.required(errors, "chips[%d]" % i, c):
			continue
		if seen.has(c.id):
			errors.append("chips[%d].id: duplicate %s" % [i, c.id])
		seen[c.id] = true
		for e: String in c.validate():
			errors.append("chips[%d].%s" % [i, e])
	return errors
