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
const GAP: int = 6

## The space (px) between buttons; a phone's is UiTheme.TOUCH_GAP (D274).
var gap: int = GAP:
	set(value):
		gap = value
		add_theme_constant_override("h_separation", value)
		add_theme_constant_override("v_separation", value)

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
	gap = GAP


## The shortcuts this screen's stations may share: toggle ids in file order.
static func features(stations: Array[String], toggles: DataToggles) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in DataToggles.shareable():
		var def: DataToggleDef = DataToggles.toggle_def(id)
		if (
			toggles.on(id)
			and stations.has(String(def.source))
			and not stations.has(String(def.receiver))
		):
			out.append(id)
	return out


## The lines of the receiving side (C5), feature -> line: data another station of this ship
## shared here and that is still live, "Routes on Helm from Relay · 12 s". `left` is feature ->
## seconds left (ClientState shares); a joint view holding the source sees the data anyway.
## The station screen shows each as a note in its toast queue.
static func incoming(stations: Array[String], left: Dictionary) -> Dictionary[StringName, String]:
	var out: Dictionary[StringName, String] = {}
	for id: StringName in left:
		var seconds: int = ceili(float(left[id]))
		var def: DataToggleDef = DataToggles.toggle_def(id)
		if seconds <= 0 or def == null:
			continue
		if stations.has(String(def.receiver)) and not stations.has(String(def.source)):
			var what: String = TranslationServer.translate("lobby.toggle." + String(id))
			var from: String = TranslationServer.translate("station." + String(def.source))
			out[id] = TranslationServer.translate("share.incoming") % [what, from, seconds]
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
		var what: String = tr("lobby.toggle." + String(id))
		# A live share reads as sent and is lit; idle it invites the press (C5).
		_buttons[id].text = (
			tr("share.button") % what if seconds <= 0 else tr("share.sent") % [what, seconds]
		)
		var variation: String = "" if seconds <= 0 else "RailAccentButton"
		if _buttons[id].theme_type_variation != variation:
			_buttons[id].theme_type_variation = variation
	visible = not shown.is_empty()
