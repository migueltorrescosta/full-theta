## The touch help picture of a station (TouchHelpPicture, P28-Help) for the L5 harness, as the
## menu's Controls tab would show it on a phone: `station` picks it, `scroll` scrolls down
## that many px.
extends Control

var station: String = "engineering"
var scroll: int = 0


func _ready() -> void:
	I18n.apply("en")
	LayoutMode.apply(get_tree().root)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("panel")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box: ScrollContainer = ScrollContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16.0
	box.offset_top = 16.0
	box.offset_right = -16.0
	box.offset_bottom = -16.0
	box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(box)
	var pic: TouchHelpPicture = TouchHelpPicture.make(station)
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(pic)
	_scroll.call_deferred(box)


func _scroll(box: ScrollContainer) -> void:
	await get_tree().process_frame
	box.scroll_vertical = scroll
