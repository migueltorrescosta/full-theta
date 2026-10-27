class_name SayTarget
extends RefCounted
## Who hears a ScenarioApi.message line (FT-AUD-005, FT-AUD-006): an NPC's line to a
## ship, or the ship computer's line to some stations of a ship. Plain values.

## The speaking NPC (CardSpec.npc_id), or &"" for the ship computer.
var npc_id: StringName = &""
## The ship that hears it, or -1 for the first crewed ship in play.
var ship: int = -1
## The stations a computer line concerns (helm, weapons, ...), empty for all.
var stations: PackedStringArray = PackedStringArray()


## An NPC's line, heard on `ship`.
static func npc(npc_name: StringName, to_ship: int = -1) -> SayTarget:
	var t: SayTarget = SayTarget.new()
	t.npc_id = npc_name
	t.ship = to_ship
	return t


## The ship computer's line on `ship` for the given stations.
static func computer(to_ship: int, to_stations: PackedStringArray) -> SayTarget:
	var t: SayTarget = SayTarget.new()
	t.ship = to_ship
	t.stations = to_stations
	return t
