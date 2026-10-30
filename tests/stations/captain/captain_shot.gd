## The WR page shot (tests/stations/wr/page_shot.gd) for the Captain (#28 follow-up): no
## chip goes to the Captain, so `chip` adds an open Helm-to-Engineering Boost request, which
## the Captain's Requests page lists read-only (FT-CPT-004).
extends "res://tests/stations/wr/page_shot.gd"


func _chip_row(_s: StationScreen) -> Dictionary:
	var chips: Array[ChipDef] = NetChips.def().chips
	var boost: int = chips.find_custom(func(c: ChipDef) -> bool: return c.id == &"boost")
	return {
		"id": 5,
		"chip": boost,
		"arg": -1,
		"from": StationViews.CREW.find(String(chips[boost].from_station)),
		"to": StationViews.CREW.find(String(chips[boost].to_station)),
		"sent": StationFixture.TICK - 240,
		"expires": StationFixture.TICK + 1080,
	}
