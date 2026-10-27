class_name DataToggleDef
extends Resource
## One data-shortcut toggle of the lobby (spec §7.2, FT-PAIR-017, D84): what it gates, which
## station supplies the data and which receives it, and its value in each preset. Read-only
## at runtime (FT-ARC-020).

## How a toggle's value reads. A SUMMARY toggle is 0 absent, 1 banded, 2 exact (D193); a
## SHORTCUT toggle is 0 off (the data travels by voice, or not at all) and 1 on.
enum Kind { SUMMARY, SHORTCUT }

## Unique among toggles, in lower case (dimensionless id, e.g. routes). The lobby text
## keys are toggle.<id> and toggle.<id>.desc.
@export var id: StringName = &""
@export var kind: Kind = Kind.SHORTCUT
## The pairs of spec §7.3 the toggle serves, as shown in the lobby (e.g. "P4").
@export var pairs: String = ""
## The station whose data the toggle moves ("" for the summaries, which have an owner per
## field) and the station that receives it. A joint view holding the source station sees
## the data as if the toggle were on (FT-JNT-005).
@export var source: StringName = &""
@export var target: StringName = &""
## The value in the Easy preset (dimensionless, see Kind).
@export var easy: int = 0
## The value in the Normal preset (dimensionless, see Kind).
@export var normal: int = 0
## The value in the Hard preset (dimensionless, see Kind).
@export var hard: int = 0


## The preset's value, or -1 for an unknown preset.
func value_of(preset: StringName) -> int:
	match preset:
		&"easy":
			return easy
		&"normal":
			return normal
		&"hard":
			return hard
	return -1


## The most the toggle can be.
func max_value() -> int:
	return 2 if kind == Kind.SUMMARY else 1


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	for preset: StringName in [&"easy", &"normal", &"hard"]:
		var v: int = value_of(preset)
		if v < 0 or v > max_value():
			errors.append("%s: must be in 0..%d, got %d" % [preset, max_value(), v])
	return errors
