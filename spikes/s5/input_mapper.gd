class_name S5InputMapper
extends RefCounted
## Keyboard, mouse and gamepad bindings for the prototype, added to the InputMap at run
## time so project.godot stays untouched. Turns device state into S5HelmInput
## (research/tech §5). Provisional bindings follow spec §5.1 where they can.

const STICK_DEAD_ZONE: float = 0.2
const TRIGGER_DEAD_ZONE: float = 0.1
## Mouse: counts to virtual-stick deflection, and how fast the stick re-centres.
const MOUSE_SENSITIVITY: float = 0.006
const MOUSE_HALF_LIFE: float = 0.12

var invert_pitch: bool = false
## Mouse virtual stick (x right, y down); the HUD shows it.
var mouse_stick: Vector2 = Vector2.ZERO
## Edge presses waiting for the next sim tick.
var pending: S5HelmInput = S5HelmInput.new()
## UI-only edges, consumed by the scene.
var mark_ahead: bool = false
var mark_here: bool = false
var chase_toggled: bool = false
var help_toggled: bool = false
var zoom_pressed: bool = false
var reset_pressed: bool = false


static func register() -> void:
	_key("s5_throttle_up", [KEY_W])
	_key("s5_throttle_down", [KEY_S])
	_key("s5_strafe_left", [KEY_A])
	_key("s5_strafe_right", [KEY_D])
	_key("s5_lift_up", [KEY_R])
	_key("s5_lift_down", [KEY_V])
	_key("s5_pitch_up", [KEY_UP])
	_key("s5_pitch_down", [KEY_DOWN])
	_key("s5_yaw_left", [KEY_LEFT])
	_key("s5_yaw_right", [KEY_RIGHT])
	_key("s5_roll_left", [KEY_Q])
	_key("s5_roll_right", [KEY_E])
	_key("s5_face", [KEY_F])
	_key("s5_approach", [KEY_X])
	_key("s5_all_stop", [KEY_SPACE])
	_key("s5_decoupled", [KEY_TAB])
	_key("s5_level", [KEY_L])
	_key("s5_select", [KEY_T])
	_key("s5_mark", [KEY_M])
	_key("s5_chase", [KEY_C])
	_key("s5_help", [KEY_H, KEY_F1])
	_key("s5_zoom", [KEY_Z])
	_key("s5_invert", [KEY_I])
	_key("s5_reset", [KEY_BACKSPACE])
	_key("s5_fullscreen", [KEY_F11])
	_axis("s5_pad_throttle_up", JOY_AXIS_TRIGGER_RIGHT, 1.0, TRIGGER_DEAD_ZONE)
	_axis("s5_pad_throttle_down", JOY_AXIS_TRIGGER_LEFT, 1.0, TRIGGER_DEAD_ZONE)
	_axis("s5_pad_strafe_left", JOY_AXIS_RIGHT_X, -1.0, STICK_DEAD_ZONE)
	_axis("s5_pad_strafe_right", JOY_AXIS_RIGHT_X, 1.0, STICK_DEAD_ZONE)
	_axis("s5_pad_lift_up", JOY_AXIS_RIGHT_Y, -1.0, STICK_DEAD_ZONE)
	_axis("s5_pad_lift_down", JOY_AXIS_RIGHT_Y, 1.0, STICK_DEAD_ZONE)
	_axis("s5_pad_pitch_up", JOY_AXIS_LEFT_Y, -1.0, STICK_DEAD_ZONE)
	_axis("s5_pad_pitch_down", JOY_AXIS_LEFT_Y, 1.0, STICK_DEAD_ZONE)
	_axis("s5_pad_left", JOY_AXIS_LEFT_X, -1.0, STICK_DEAD_ZONE)
	_axis("s5_pad_right", JOY_AXIS_LEFT_X, 1.0, STICK_DEAD_ZONE)
	_button("s5_pad_roll_mod", JOY_BUTTON_LEFT_SHOULDER)
	_button("s5_pad_face", JOY_BUTTON_LEFT_STICK)
	_button("s5_pad_view", JOY_BUTTON_BACK)
	_button("s5_pad_a", JOY_BUTTON_A)
	_button("s5_pad_b", JOY_BUTTON_B)
	_button("s5_pad_x", JOY_BUTTON_X)
	_button("s5_pad_y", JOY_BUTTON_Y)
	_button("s5_pad_start", JOY_BUTTON_START)
	_button("s5_pad_zoom", JOY_BUTTON_DPAD_UP)


static func _add(action: String, dead_zone: float) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, dead_zone)


static func _key(action: String, keys: Array[Key]) -> void:
	_add(action, 0.5)
	for k: Key in keys:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


static func _axis(action: String, axis: JoyAxis, sign: float, dead_zone: float) -> void:
	_add(action, dead_zone)
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = sign
	ev.device = -1
	InputMap.action_add_event(action, ev)


static func _button(action: String, button: JoyButton) -> void:
	_add(action, 0.5)
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = button
	ev.device = -1
	InputMap.action_add_event(action, ev)


## Feeds one input event: mouse motion and the edge presses (with the View chords).
func handle_event(event: InputEvent, mouse_captured: bool) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		var motion: InputEventMouseMotion = event
		mouse_stick = (mouse_stick + motion.relative * MOUSE_SENSITIVITY).limit_length(1.0)
		return
	if event.is_echo():
		return
	var view: bool = Input.is_action_pressed("s5_pad_view")
	if event.is_action_pressed("s5_all_stop") or (view and event.is_action_pressed("s5_pad_b")):
		pending.all_stop_pressed = true
	if event.is_action_pressed("s5_decoupled") or (view and event.is_action_pressed("s5_pad_a")):
		pending.decoupled_pressed = true
	if event.is_action_pressed("s5_level") or (view and event.is_action_pressed("s5_pad_x")):
		pending.level_pressed = true
	if event.is_action_pressed("s5_select") or (not view and event.is_action_pressed("s5_pad_x")):
		pending.select_pressed = true
	if event.is_action_pressed("s5_mark"):
		var key: InputEventKey = event as InputEventKey
		if key != null and key.shift_pressed:
			mark_here = true
		else:
			mark_ahead = true
	if not view and event.is_action_pressed("s5_pad_a"):
		mark_ahead = true
	if event.is_action_pressed("s5_chase") or (not view and event.is_action_pressed("s5_pad_y")):
		chase_toggled = true
	if event.is_action_pressed("s5_help") or (not view and event.is_action_pressed("s5_pad_start")):
		help_toggled = true
	if event.is_action_pressed("s5_reset") or (view and event.is_action_pressed("s5_pad_start")):
		reset_pressed = true
	if event.is_action_pressed("s5_zoom") or event.is_action_pressed("s5_pad_zoom"):
		zoom_pressed = true
	if event.is_action_pressed("s5_invert"):
		invert_pitch = not invert_pitch


## Samples the continuous axes for this frame and merges the pending edges.
func read(frame_delta: float) -> S5HelmInput:
	mouse_stick *= pow(0.5, frame_delta / MOUSE_HALF_LIFE)
	var inp: S5HelmInput = S5HelmInput.new()
	var view: bool = Input.is_action_pressed("s5_pad_view")
	var roll_mod: bool = Input.is_action_pressed("s5_pad_roll_mod")
	var stick_x: float = Input.get_axis("s5_pad_left", "s5_pad_right")

	inp.throttle = (
		Input.get_axis("s5_throttle_down", "s5_throttle_up")
		+ Input.get_axis("s5_pad_throttle_down", "s5_pad_throttle_up")
	)
	inp.strafe = (
		Input.get_axis("s5_strafe_left", "s5_strafe_right")
		+ Input.get_axis("s5_pad_strafe_left", "s5_pad_strafe_right")
	)
	inp.lift = (
		Input.get_axis("s5_lift_down", "s5_lift_up")
		+ Input.get_axis("s5_pad_lift_down", "s5_pad_lift_up")
	)
	var pitch: float = (
		Input.get_axis("s5_pitch_down", "s5_pitch_up")
		+ Input.get_axis("s5_pad_pitch_down", "s5_pad_pitch_up")
		- mouse_stick.y
	)
	inp.pitch = -pitch if invert_pitch else pitch
	# Yaw + is nose to port, so "right" inputs are negative.
	inp.yaw = Input.get_axis("s5_yaw_right", "s5_yaw_left") - mouse_stick.x
	inp.roll = Input.get_axis("s5_roll_right", "s5_roll_left")
	if roll_mod:
		inp.roll -= stick_x
	else:
		inp.yaw -= stick_x
	inp.throttle = clampf(inp.throttle, -1.0, 1.0)
	inp.strafe = clampf(inp.strafe, -1.0, 1.0)
	inp.lift = clampf(inp.lift, -1.0, 1.0)
	inp.pitch = clampf(inp.pitch, -1.0, 1.0)
	inp.yaw = clampf(inp.yaw, -1.0, 1.0)
	inp.roll = clampf(inp.roll, -1.0, 1.0)

	inp.face = Input.is_action_pressed("s5_face") or Input.is_action_pressed("s5_pad_face")
	var pad_approach: bool = Input.is_action_pressed("s5_pad_b") and not view
	inp.approach = Input.is_action_pressed("s5_approach") or pad_approach
	inp.all_stop_pressed = pending.all_stop_pressed
	inp.decoupled_pressed = pending.decoupled_pressed
	inp.level_pressed = pending.level_pressed
	inp.select_pressed = pending.select_pressed
	return inp


## Clears the edges once a sim tick has consumed them.
func consume_edges() -> void:
	pending = S5HelmInput.new()
