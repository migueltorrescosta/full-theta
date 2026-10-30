## Weapons' phone pages for the L5 harness (#28 follow-up): station_shot.gd's screen (set
## from shots.json as there) with the Weapons panel on `page` (WeaponsTouch.Page), or, with
## `help` set, the touch help picture of its pages (WeaponsTouchHelp) alone.
extends "res://tests/visual/station_shot.gd"

var page: int = 0
var help: bool = false


func _ready() -> void:
	if help:
		I18n.apply("en")
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bg: ColorRect = ColorRect.new()
		bg.color = Palette.color("background")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var pic: WeaponsTouchHelp = WeaponsTouchHelp.new()
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(pic)
		return
	super()
	for c: Node in get_children():
		var s: StationScreen = c as StationScreen
		if s != null and s.focused_panel().pages != null:
			s.focused_panel().pages.current = page
