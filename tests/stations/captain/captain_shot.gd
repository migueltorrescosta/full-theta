## The WR page shot (tests/stations/wr/page_shot.gd) for the Captain (#28 follow-up): no
## chip goes to the Captain, so `chip` adds an open Helm-to-Engineering Boost request, which
## the Captain's Requests page lists read-only (FT-CPT-004).
extends "res://tests/stations/wr/page_shot.gd"

## `states` (R23-12): three requests, then two of them go, one answered with time left and one
## run out, so the list shows a waiting row over "Answered" and "Expired".
var states: bool = false


func _chip_row(_s: StationScreen) -> Dictionary:
	var chips: Array[ChipDef] = ChipsReader.def().chips
	var boost: int = chips.find_custom(func(c: ChipDef) -> bool: return c.id == &"boost")
	return {
		"id": 5,
		"chip": boost,
		"arg": -1,
		"from": StationCatalogue.CREW.find(String(chips[boost].from_station)),
		"to": StationCatalogue.CREW.find(String(chips[boost].to_station)),
		"sent": StationFixture.TICK - 240,
		"expires": StationFixture.TICK + 1080,
	}


func _set_page() -> void:
	await super()
	if not states:
		return
	for n: Node in find_children("*", "StationScreen", true, false):
		var s: StationScreen = n
		var waiting: Dictionary = _chip_row(s)
		var answered: Dictionary = waiting.duplicate()
		answered["id"] = 6
		answered["expires"] = StationFixture.TICK + 12 * SimWorld.HZ
		var lapsed: Dictionary = waiting.duplicate()
		lapsed["id"] = 7
		lapsed["expires"] = StationFixture.TICK + SimWorld.HZ
		s.ctx.snap.blocks[StationCatalogue.Section.CHIPS] = {"chips": [waiting, answered, lapsed]}
		await get_tree().process_frame
		await get_tree().process_frame
		s.ctx.snap.blocks[StationCatalogue.Section.CHIPS] = {"chips": [waiting]}
