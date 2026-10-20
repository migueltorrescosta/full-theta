class_name StationDef
extends RefCounted
## The data definition of one catalogue entry (FT-ARC-014, FT-STN-015): a functional
## station, a joint view, the Captain seat, the main screen (Viewer) or the dev entry.
## StationViews builds every StationDef from its tables; a joint view is the union of
## its stations (D20, FT-JNT-005). The Catalogue message carries to_dict() of each.

var id: String = ""
var display_name: String = ""
## StationViews.LIGHT, BUSY or INTENSE; "" for the Viewer (D126).
var load_tag: String = ""
## The functional stations it covers: one, two for a joint view, all six for the dev
## entry, none for Captain and Viewer (they never count for coverage, FT-NET-020).
var stations: Array[String] = []
## Snapshot sections it receives, ascending (StationViews.Section).
var sections: Array[int] = []
## Block section -> the field names it shows (StationViews.BLOCKS); blocks are whole.
var fields: Dictionary = {}
## Crew command kinds it may send (SimCommand.kind()).
var commands: Array[StringName] = []
## Claimable item kinds of its stations (StationViews.CLAIM_*; FT-NET-022).
var claims: Array[String] = []
## Ship-wide (last writer wins) controls of its stations (FT-NET-044).
var controls: Array[String] = []


## A crew entry: it covers at least one functional station.
func is_crew() -> bool:
	return not stations.is_empty()


func to_dict() -> Dictionary:
	var block_fields: Dictionary = {}
	for kind: int in fields:
		block_fields[kind] = (fields[kind] as Array).duplicate()
	return {
		"id": id,
		"name": display_name,
		"load_tag": load_tag,
		"stations": stations.duplicate(),
		"crew": is_crew(),
		"sections": sections.duplicate(),
		"fields": block_fields,
		"commands": commands.map(func(k: StringName) -> String: return String(k)),
		"claims": claims.duplicate(),
		"controls": controls.duplicate(),
	}
