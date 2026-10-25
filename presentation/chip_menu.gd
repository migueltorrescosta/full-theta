class_name ChipMenu
extends PanelContainer
## The numbered list B opens on a station that has several request chips (§5.0: "B, then
## 1-2"; View+Y, then the d-pad on a controller): one line per chip, the key beside it.
## A digit (or d-pad up, right, down, left for 1 to 4) picks a line, B or Escape closes the
## list. While it is open it takes those keys before the station sees them.

## A line was picked (0-based).
signal chosen(index: int)

const PAD_BUTTONS: Array[JoyButton] = [
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT
]

var _box: VBoxContainer = VBoxContainer.new()
var _title: Label = Label.new()
var _count: int = 0


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	_title.add_theme_color_override("font_color", Palette.color("text_dim"))
	_box.add_child(_title)


## Shows the lines (already translated; a line is greyed when `enabled[i]` is false).
func open(title: String, labels: PackedStringArray, enabled: Array[bool]) -> void:
	for c: Node in _box.get_children():
		if c != _title:
			_box.remove_child(c)
			c.queue_free()
	_title.text = title
	_count = labels.size()
	for i: int in labels.size():
		var b: Button = Button.new()
		b.name = "Chip%d" % (i + 1)
		b.text = "%d  %s" % [i + 1, labels[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not enabled[i]
		b.pressed.connect(choose.bind(i))
		_box.add_child(b)
	visible = true


func close() -> void:
	visible = false


## Picks line `index` and closes; false for a line that isn't there.
func choose(index: int) -> bool:
	if not visible or index < 0 or index >= _count:
		return false
	visible = false
	chosen.emit(index)
	return true


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var n: int = key.keycode - KEY_1
		if key.keycode == KEY_ESCAPE or key.keycode == KEY_B:
			close()
		elif n >= 0 and n < 9:
			choose(n)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad != null and pad.pressed:
		var at: int = PAD_BUTTONS.find(pad.button_index)
		if at >= 0:
			choose(at)
			get_viewport().set_input_as_handled()
