class_name HelmSuite
extends GdUnitTestSuite
## Shared fixture of the Helm panel suites (T051): a Helm StationScreen on the station
## fixture at 1280x720, and KB/M and controller events fed to its matcher, so actions
## go through the one binding table; checks read the commands the panel sends.

const PAD_BUTTONS: Dictionary = {
	"B": JOY_BUTTON_B,
	"LB": JOY_BUTTON_LEFT_SHOULDER,
	"L3": JOY_BUTTON_LEFT_STICK,
	"View": JOY_BUTTON_BACK,
	"Up": JOY_BUTTON_DPAD_UP,
	"Down": JOY_BUTTON_DPAD_DOWN,
	"Left": JOY_BUTTON_DPAD_LEFT,
	"Right": JOY_BUTTON_DPAD_RIGHT,
}

var _screen: StationScreen
var _panel: HelmPanel


func before_test() -> void:
	I18n.apply("en")
	var ctx: StationContext = StationFixture.context("helm", "user://test_helm_panel.cfg")
	ctx.settings.mark_tooltip_seen("helm")
	_screen = auto_free(StationScreen.new())
	_screen.setup(ctx)
	add_child(_screen)
	# The headless window is tiny: lay the screen out at 1280x720.
	_screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_screen.size = Vector2(1280, 720)
	_panel = _screen.panels[0] as HelmPanel
	await await_idle_frame()
	_frame()


func _ctx() -> StationContext:
	return _screen.ctx


func _frame() -> void:
	_panel._process(0.016)


## Commands of one kind the panel sent, oldest first.
func _cmds(kind: String) -> Array:
	var out: Array = []
	for s: Array in StationFixture.sent(_ctx()).of("command"):
		if s[1][0]["kind"] == kind:
			out.append(s[1][0])
	return out


func _key(name: String, pressed: bool = true) -> void:
	var k: InputEventKey = InputEventKey.new()
	k.physical_keycode = OS.find_keycode_from_string(name)
	k.pressed = pressed
	_screen.feed(k)


func _tap_key(name: String) -> void:
	_key(name, true)
	_key(name, false)


func _pad(name: String, pressed: bool = true) -> void:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.button_index = PAD_BUTTONS[name]
	b.pressed = pressed
	_screen.feed(b)


func _tap_pad(name: String, modifier: String = "") -> void:
	if modifier != "":
		_pad(modifier)
	_pad(name)
	_pad(name, false)
	if modifier != "":
		_pad(modifier, false)


func _stick(axis: JoyAxis, value: float) -> void:
	var m: InputEventJoypadMotion = InputEventJoypadMotion.new()
	m.axis = axis
	m.axis_value = value
	_screen.feed(m)


## Holds View, flicks the right stick toward radial item i, lets go (FT-HLM-017).
func _radial(id: String) -> void:
	var i: int = HelmPanel.RADIAL.find(id)
	var a: float = TAU * i / HelmPanel.RADIAL.size()
	_pad("View")
	_stick(JOY_AXIS_RIGHT_X, sin(a))
	_stick(JOY_AXIS_RIGHT_Y, -cos(a))
	_frame()
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	_stick(JOY_AXIS_RIGHT_Y, 0.0)
	_pad("View", false)
