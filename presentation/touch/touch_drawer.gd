class_name TouchDrawer
extends PanelContainer
## A panel that slides out beside a rail over the view (#28): the radar, contacts, a
## share list. A rail button opens and closes it (`bind_opener`), and so does its own
## close button; it never blocks the rest of the screen, so the sticks keep working while
## it is open. RailLayout.add_drawer places it next to its side's rail.
##
##     var radar_drawer := TouchDrawer.new("Radar", SIDE_LEFT)
##     radar_drawer.body.add_child(radar)
##     layout.add_drawer(radar_drawer)
##     radar_drawer.bind_opener(left.add(RailButton.make("Radar")) as RailButton)

signal toggled(open: bool)

const WIDTH: float = 240.0

var side: Side = SIDE_LEFT
## What the drawer shows, under its title row.
var body: VBoxContainer = VBoxContainer.new()
var title: Label = Label.new()
var close_button: RailButton = RailButton.make("×")
var opener: RailButton = null


func _init(heading: String = "", drawer_side: Side = SIDE_LEFT) -> void:
	side = drawer_side
	theme_type_variation = "Drawer"
	custom_minimum_size.x = WIDTH
	visible = false
	add_to_group(TouchInput.GROUP)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	title.text = heading
	title.theme_type_variation = "HeadingLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)


func is_open() -> bool:
	return visible


func open() -> void:
	_show(true)


func close() -> void:
	_show(false)


func toggle() -> void:
	_show(not visible)


## Makes `button` a toggle that opens and closes the drawer and shows its state.
func bind_opener(button: RailButton) -> void:
	opener = button
	button.toggle_mode = true
	button.button_pressed = visible
	button.pressed.connect(func() -> void: _show(button.button_pressed))


func _show(on: bool) -> void:
	if opener != null:
		opener.set_pressed_no_signal(on)
	if on == visible:
		return
	visible = on
	toggled.emit(on)
