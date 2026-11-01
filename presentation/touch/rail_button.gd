class_name RailButton
extends Button
## A thumb-rail button (#28): at least UiTheme.TOUCH_PRIMARY px square, no keyboard focus,
## the text trimmed to fit. Every finger works, not only the first: a touch presses it
## while a stick is held. `hold` buttons report the press and the release (`held`), for
## intents held down (Approach, FIRE on a beam).
##
##     var b := RailButton.make("All stop", RailButton.Role.DANGER)
##     b.pressed.connect(_all_stop)

## True on the press, false on the release, of a `hold` button.
signal held(down: bool)

enum Role { PLAIN, ACCENT, DANGER }

var role: Role = Role.PLAIN:
	set(value):
		role = value
		theme_type_variation = ["RailButton", "RailAccentButton", "RailDangerButton"][value]
## Also report presses and releases through `held`.
var hold: bool = false

var _touch: int = -1


## A rail button with `text` and `role`.
static func make(label: String, button_role: Role = Role.PLAIN) -> RailButton:
	var b: RailButton = RailButton.new()
	b.text = label
	b.role = button_role
	return b


func _init() -> void:
	role = role
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(UiTheme.TOUCH_PRIMARY, UiTheme.TOUCH_PRIMARY)
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_to_group(TouchInput.GROUP)
	button_down.connect(func() -> void: _hold(true))
	button_up.connect(func() -> void: _hold(false))


func _gui_input(event: InputEvent) -> void:
	if TouchInput.is_emulated(event):
		# The same finger arrives as a ScreenTouch below.
		accept_event()
		return
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t == null or disabled:
		return
	accept_event()
	if t.pressed and _touch < 0:
		_touch = t.index
		TouchInput.held += 1
		_show_down(true)
		_hold(true)
	elif not t.pressed and t.index == _touch:
		_release()
		if Rect2(Vector2.ZERO, size).has_point(t.position):
			_click()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _touch >= 0:
		_release()


func _exit_tree() -> void:
	if _touch >= 0:
		_release()


func _release() -> void:
	_touch = -1
	TouchInput.held = maxi(TouchInput.held - 1, 0)
	_show_down(false)
	_hold(false)


## A finger's tap: toggles a toggle button (a group keeps one pressed) and emits `pressed`.
func _click() -> void:
	if toggle_mode:
		var keep: bool = button_group != null and button_pressed and not button_group.allow_unpress
		if not keep:
			button_pressed = not button_pressed
	pressed.emit()


func _hold(down: bool) -> void:
	if hold:
		held.emit(down)


## A finger shows the pressed style while it is down (Godot only does so for the mouse).
func _show_down(down: bool) -> void:
	if down:
		add_theme_stylebox_override("normal", get_theme_stylebox("pressed"))
		add_theme_stylebox_override("hover", get_theme_stylebox("pressed"))
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")
