class_name FleeCostDef
extends Resource
## What fleeing an encounter costs (FT-MIS-015, D233): a ship that jumps out of its active
## encounter while a ship of a hostile faction still detects it pays these credits and a
## reputation draw with that faction, besides the jump's own propellant. PROVISIONAL (Q5):
## the numbers are placeholders for #13 to tune. Read-only at runtime (FT-ARC-020).

@export var id: StringName = &""
## Credits taken from the fleeing ship (cr).
@export var credits: int = 0
## RepDistDef id of the reputation draw with the hostile faction (FT-MIS-019), or &"".
@export var rep_dist: StringName = &""


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if credits < 0:
		errors.append("credits must be at least 0, got %d" % credits)
	return errors
