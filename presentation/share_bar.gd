class_name ShareBar
extends HFlowContainer
## The share buttons of the station screen (§7.2, FT-PAIR-007, D210): one per data shortcut
## whose source is a station of this screen, whose toggle is on and whose partner is not on
## the screen too (a joint view holding both sees the data without a press, FT-JNT-005). A
## press sends it to the partner for a while; the button then shows the seconds left. The
## buttons are big enough to tap.

## Emitted with the toggle id when a button is pressed.
signal share_pressed(feature: StringName)

const BUTTON_H: float = 44.0
## A fine pointer needs less (a short window).
const SHORT_H: float = 36.0

## The button height; a fine pointer's short window uses SHORT_H.
var button_h: float = BUTTON_H:
	set(value):
		button_h = value
		for b: Button in _buttons.values():
			b.custom_minimum_size.y = value

## The least width of a button: wide enough for the longest label on a line (D195).
var min_width: float = 260.0:
	set(value):
		min_width = value
		for b: Button in _buttons.values():
			b.custom_minimum_size.x = value

var _shown: Array = []
var _buttons: Dictionary[StringName, Button] = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)


## The shortcuts this screen's stations may share: toggle ids in file order.
static func features(stations: Array[String], toggles: DataToggles) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in DataToggles.shareable():
		var def: DataToggleDef = DataToggles.toggle_def(id)
		if (
			toggles.on(id)
			and stations.has(String(def.source))
			and not stations.has(String(def.target))
		):
			out.append(id)
	return out


## Shows the buttons for `shown` (features()), each with the seconds `left` of its share
## (feature -> seconds, 0 when not shared). Rebuilds only when the set changes.
func show_features(shown: Array[StringName], left: Dictionary) -> void:
	if shown != _shown:
		_shown = shown.duplicate()
		for c: Node in get_children():
			remove_child(c)
			c.queue_free()
		_buttons.clear()
		for id: StringName in shown:
			var b: Button = Button.new()
			b.custom_minimum_size = Vector2(min_width, button_h)
			b.focus_mode = Control.FOCUS_NONE
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.pressed.connect(func() -> void: share_pressed.emit(id))
			add_child(b)
			_buttons[id] = b
	for id: StringName in shown:
		var seconds: int = ceili(float(left.get(id, 0.0)))
		var text: String = tr("share.button") % tr("lobby.toggle." + String(id))
		_buttons[id].text = text if seconds <= 0 else "%s · %d s" % [text, seconds]
	visible = not shown.is_empty()
