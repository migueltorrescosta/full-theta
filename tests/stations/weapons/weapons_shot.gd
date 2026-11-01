## Weapons' phone pages for the L5 harness (#28 follow-up): station_shot.gd's screen (set
## from shots.json as there) with the Weapons panel on `page` (WeaponsTouch.Page).
extends "res://tests/visual/station_shot.gd"

var page: int = 0


func _ready() -> void:
	super()
	for c: Node in get_children():
		var s: StationScreen = c as StationScreen
		if s != null and s.focused_panel().pages != null:
			s.focused_panel().pages.current = page
