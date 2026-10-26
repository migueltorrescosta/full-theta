class_name ScenarioMeta
extends RefCounted
## What a scenario declares for the director (FT-DAT-008, D64): constant data, checked by
## errors() in the L0 gate (tools/check_scenarios.gd) and by the director.

const TAGS: Array[String] = ["hostile", "rescue", "training", "travel"]
const STATIONS: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
const BEATS: Array[String] = ["hail", "taunt", "surrender", "distress"]

var id: StringName = &""
var tags: PackedStringArray = PackedStringArray()
## Threat points the director charges to a ship's budget (FT-MIS-029).
var threat_cost: int = 0
var duration_s: float = 0.0
var stations: PackedStringArray = PackedStringArray()
## Pair tests the scenario exercises ("p5", "p9", ...).
var pairs: PackedStringArray = PackedStringArray()
## Declared outcomes: [{id, outcome}], both non-empty strings.
var branches: Array[Dictionary] = []
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
	if threat_cost < 0:
		out.append("threat_cost must be at least 0, got %d" % threat_cost)
	if duration_s <= 0.0:
		out.append("duration_s must be positive, got %s" % duration_s)
	for s: String in stations:
		if not STATIONS.has(s):
			out.append("unknown station %s" % s)
	for p: String in pairs:
		if not p.begins_with("p") or not p.substr(1).is_valid_int():
			out.append("pair %s is not pN" % p)
	for b: Dictionary in branches:
		if str(b.get("id", "")) == "" or str(b.get("outcome", "")) == "":
			out.append("branch %s needs an id and an outcome" % [b])
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
