class_name MatcherSuite
extends GdUnitTestSuite
## Shared fixture of the InputMatcher suites: a matcher on a Helm-only screen and
## synthetic InputEvents.

const PAD_BUTTONS: Dictionary = {
	"A": JOY_BUTTON_A,
	"B": JOY_BUTTON_B,
	"X": JOY_BUTTON_X,
	"LB": JOY_BUTTON_LEFT_SHOULDER,
	"RB": JOY_BUTTON_RIGHT_SHOULDER,
	"L3": JOY_BUTTON_LEFT_STICK,
	"R3": JOY_BUTTON_RIGHT_STICK,
	"View": JOY_BUTTON_BACK,
	"Left": JOY_BUTTON_DPAD_LEFT,
}

var _m: InputMatcher


func before_test() -> void:
	_m = InputMatcher.new()
	_m.set_context(["helm"], "helm")


func _key(name: String, pressed: bool, mods: String = "") -> InputEventKey:
	var k: InputEventKey = InputEventKey.new()
	k.physical_keycode = OS.find_keycode_from_string(name)
	k.pressed = pressed
	k.shift_pressed = "shift" in mods
	k.alt_pressed = "alt" in mods
	return k


func _mouse(button: MouseButton, pressed: bool, shift: bool = false) -> InputEventMouseButton:
	var b: InputEventMouseButton = InputEventMouseButton.new()
	b.button_index = button
	b.pressed = pressed
	b.shift_pressed = shift
	return b


func _pad(name: String, pressed: bool) -> InputEventJoypadButton:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.button_index = PAD_BUTTONS[name]
	b.pressed = pressed
	return b


func _motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var m: InputEventJoypadMotion = InputEventJoypadMotion.new()
	m.axis = axis
	m.axis_value = value
	return m


## Event ids, released ones suffixed "/up".
func _ids(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in events:
		out.append(e["id"] if e["pressed"] else e["id"] + "/up")
	return out


func _feed(event: InputEvent, now_ms: int = 0) -> Array[String]:
	return _ids(_m.feed(event, now_ms))
