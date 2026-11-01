class_name ScenarioMeta
extends RefCounted
## What a scenario declares for the director (FT-DAT-008, D64): constant data, checked by
## errors() in the L0 gate (tools/check_scenarios.gd) and by the director.

const TAGS: Array[String] = ["hostile", "rescue", "training", "travel"]
const BEATS: Array[String] = ["hail", "taunt", "surrender", "distress"]

var id: StringName = &""
var tags: PackedStringArray = PackedStringArray()
## Threat points the director charges to a ship's budget (FT-MIS-029).
var threat_cost: int = 0
var comms_beats: PackedStringArray = PackedStringArray()
## Hazard key on the leg of a travel scenario, or &"".
var travel_hazard: StringName = &""
## Shakedown: no director budget and no elimination.
var training: bool = false


## Why the declaration is wrong, or [] (FT-DAT-008, FT-DAT-009; a hostile scenario needs
## a Comms beat, FT-MIS-041).
func errors() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("id is empty")
	for t: String in tags:
		if not TAGS.has(t):
			out.append("unknown tag %s" % t)
	if threat_cost < (0 if training else 1):
		# Every scenario costs at least 1, so a run's encounters are bounded by its budget (Q14).
		out.append("threat_cost must be at least 1, got %d" % threat_cost)
	for beat: String in comms_beats:
		if not BEATS.has(beat):
			out.append("unknown comms beat %s" % beat)
	if tags.has("hostile") and comms_beats.is_empty():
		out.append("hostile scenario needs a Comms beat (FT-MIS-041)")
	if tags.has("travel") and travel_hazard == &"":
		out.append("travel scenario needs a travel_hazard")
	if training != tags.has("training"):
		out.append("training and the training tag must go together")
	if training and threat_cost != 0:
		out.append("a training scenario costs no threat")
	return out
