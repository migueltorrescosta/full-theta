class_name SayCommand
extends SimCommand
## A spoken line from the run itself (E10, FT-AUD-005, FT-AUD-006, FT-COM-006): the
## server (a scenario's message(), a Comms reply) says `line_id`. It emits a &"say"
## event on the audience ship, with tag = line_id, other_id = -1 and
## args = the line's arguments plus "npc_id" (the speaking NPC, "" for the ship
## computer) and "stations" (the stations a computer line concerns); ServerVoice routes
## it. The source is SERVER, so it is logged and a replay says the same line on the same
## tick (FT-ARC-008).

var line_id: String = ""
## The speaking NPC (CardSpec.npc_id), or "" for a ship-computer line.
var npc_id: String = ""
## The stations a computer line concerns (StationViews.CREW names).
var stations: Array = []
var args: Dictionary = {}


func _init() -> void:
	source = Source.SERVER


func kind() -> StringName:
	return &"say"


## Rejects an empty line id.
func apply(world: SimWorld) -> bool:
	if line_id == "":
		return false
	var e: SimEvent = world.emit(&"say", ship_id, -1, 0.0, Vector3.ZERO, StringName(line_id))
	e.args = args.duplicate(true)
	e.args["npc_id"] = npc_id
	e.args["stations"] = stations.duplicate()
	return true
