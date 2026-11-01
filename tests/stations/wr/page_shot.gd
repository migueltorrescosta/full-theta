## The station shot (tests/visual/station_shot.gd) on a phone page (#28 follow-up, D287), for
## strand WR's stations: `page` opens that page of the focused panel's PageHost, `sheet`
## opens a sheet ("selection" or "alert") and `chip` adds an incoming request chip to the
## focused station.
extends "res://tests/visual/station_shot.gd"

var page: int = 0
var sheet: String = ""
var chip: bool = false


func _ready() -> void:
	super()
	_set_page.call_deferred()


func _set_page() -> void:
	await get_tree().process_frame
	for n: Node in find_children("*", "StationScreen", true, false):
		var s: StationScreen = n
		if chip:
			s.ctx.view.blocks[StationViews.Section.CHIPS] = {"chips": [_chip_row(s)]}
		var p: StationPanel = s.focused_panel()
		if p.pages != null:
			p.pages.current = page
		match sheet:
			"selection":
				s.frame.open_selection_sheet()
			"alert":
				s.frame.open_alert_sheet()


## An open request chip from another station to the focused one.
func _chip_row(s: StationScreen) -> Dictionary:
	var chips: Array[ChipDef] = NetChips.def().chips
	var to: String = s.focused_station()
	for i: int in chips.size():
		if String(chips[i].to_station) == to:
			return {
				"id": 5,
				"chip": i,
				"arg": -1,
				"from": StationViews.CREW.find(String(chips[i].from_station)),
				"to": StationViews.CREW.find(to),
				"sent": StationFixture.TICK - 240,
				"expires": StationFixture.TICK + 1080,
			}
	return {}
