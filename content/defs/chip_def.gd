class_name ChipDef
extends Resource
## One request chip (spec §7.4 "Request chips", FT-PAIR-021): who may send it, who gets it
## and what it carries. Chips are cues between players: they change nothing in the sim.

## What the chip's argument names: nothing, one of the sender's mounts (by index) or a
## contact (by ship id).
enum Arg { NONE, MOUNT, CONTACT }

## The six functional stations (content/ may not name StationViews).
const STATIONS: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]

## Unique among chips, in lower case (dimensionless id, e.g. boost). The text key is
## chip.<id>.
@export var id: StringName = &""
@export var from_station: StringName = &""
@export var to_station: StringName = &""
## The pair of spec §7.3 the chip belongs to, lower case (e.g. p1); the debrief counts per
## pair (FT-PAIR-013).
@export var pair: StringName = &""
@export var arg: Arg = Arg.NONE
## False while nothing can answer the chip: hold fire (Comms to Weapons) is in the list but
## inert until #10 wires Comms (D191).
@export var active: bool = true


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if not STATIONS.has(String(from_station)):
		errors.append("from_station: not a station: %s" % from_station)
	if not STATIONS.has(String(to_station)):
		errors.append("to_station: not a station: %s" % to_station)
	if from_station == to_station:
		errors.append("to_station: must differ from from_station")
	return errors
