class_name SelectionChip
extends HBoxContainer
## The selection chip of a phone's view-top row (#28 follow-up, P28-Common, design 1.3):
## `‹ H2 · 4 high mid ›`. The arrows cycle the target (the common cycle_target), a tap on
## the name opens the selection sheet (Ping, Mark here, Clear and the station's extras).
##
##     chip.cycled.connect(func(step: int) -> void: _cycle(step))
##     chip.opened.connect(_open_selection_sheet)
##     chip.show_text("H2 · 4 high mid")

## An arrow was tapped: +1 the next target, -1 the previous one.
signal cycled(step: int)
## The name was tapped.
signal opened

const NAME_W: float = 172.0
## The name's least width when the view is narrow (fit).
const NAME_MIN_W: float = 96.0
const FONT: int = 14

var prev_button: RailButton = RailButton.make("‹")
var next_button: RailButton = RailButton.make("›")
var name_button: RailButton = RailButton.make("")


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	prev_button.name = "Prev"
	next_button.name = "Next"
	name_button.name = "Selection"
	name_button.custom_minimum_size.x = NAME_W
	name_button.add_theme_font_size_override("font_size", FONT)
	prev_button.pressed.connect(func() -> void: cycled.emit(-1))
	next_button.pressed.connect(func() -> void: cycled.emit(1))
	name_button.pressed.connect(func() -> void: opened.emit())
	for b: RailButton in [prev_button, name_button, next_button]:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(b)
	show_text("")


## Narrows the name so the chip fits `width` px (down to NAME_MIN_W).
func fit(width: float) -> void:
	var arrows: float = 2.0 * (UiTheme.TOUCH_PRIMARY + UiTheme.TOUCH_GAP)
	var w: float = clampf(width - arrows, NAME_MIN_W, NAME_W)
	if name_button.custom_minimum_size.x != w:
		name_button.custom_minimum_size.x = w


## Shows the selection's text, or "Nothing selected" for "".
func show_text(text: String) -> void:
	var t: String = text if text != "" else tr("helm.no_selection")
	if name_button.text != t:
		name_button.text = t
