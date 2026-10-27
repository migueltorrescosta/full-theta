class_name TouchRail
extends PanelContainer
## A column of thumb controls at the left or right edge of a station (#28): rail
## buttons, a stick, a throttle, tabs. `docked` rails are opaque and take their width from
## the view (RailLayout narrows it); overlay rails are translucent and float over the
## view, which keeps its content clear of them through RailLayout.content_rect_in.
## Children stack top to bottom with UiTheme.TOUCH_GAP between them; `add_spacer` pushes
## what follows to the bottom (where the thumb rests: sticks, FIRE).
##
##     var rail := layout.rail(SIDE_RIGHT)
##     rail.add_row([RailButton.make("Face"), RailButton.make("Align")])
##     rail.add_spacer()
##     rail.add(slide_stick)

## Default width of a rail (the mockups: 120-176 px).
const WIDTH: float = 136.0

## SIDE_LEFT or SIDE_RIGHT.
var side: Side = SIDE_LEFT
## Opaque and beside the view (true), or translucent over it (false).
var docked: bool = false:
	set(value):
		docked = value
		theme_type_variation = "DockedRail" if value else "OverlayRail"
## The column the controls go in.
var box: VBoxContainer = VBoxContainer.new()


func _init(rail_side: Side = SIDE_LEFT, is_docked: bool = false) -> void:
	side = rail_side
	docked = is_docked
	custom_minimum_size.x = WIDTH
	box.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(box)
	add_to_group(TouchInput.GROUP)


## Adds `control` under the others; it fills the rail's width. Returns it.
func add(control: Control) -> Control:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return control


## Adds controls side by side in one row, sharing the width equally. Returns the row.
func add_row(controls: Array) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	for c: Control in controls:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
	box.add_child(row)
	return row


## Adds a stretch: what is added after it sits at the bottom of the rail.
func add_spacer() -> Control:
	var s: Control = Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(s)
	return s
