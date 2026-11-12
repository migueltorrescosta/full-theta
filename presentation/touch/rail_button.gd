class_name RailButton
extends Button
## A thumb-rail button (#28): at least UiTheme.TOUCH_PRIMARY px square, no keyboard focus,
## the text trimmed to fit. Every finger works, not only the first: a touch presses it
## while a stick is held. `hold` buttons report the press and the release (`held`), for
## intents held down (Approach, FIRE on a beam).
##
##     var b := RailButton.make("All stop", RailButton.Role.DANGER)
##     b.pressed.connect(_all_stop)
##
## Holding a button for HoldHelp.HOLD_S shows what it does (HoldHelp, D6) and the release then
## is no tap; a mouse hover shows the same line as the tooltip. Hold buttons (`hold`) are
## never explained this way: their press is already the action.

## True on the press, false on the release, of a `hold` button.
signal held(down: bool)

enum Role { PLAIN, ACCENT, DANGER }

## The least a button's text shrinks to so it fits (fit_text).
const MIN_FONT: int = 12

var role: Role = Role.PLAIN:
	set(value):
		role = value
		theme_type_variation = ["RailButton", "RailAccentButton", "RailDangerButton"][value]
## Also report presses and releases through `held`.
var hold: bool = false

var _touch: int = -1
## The finger's hold showed the explanation: its release is no tap.
var _explained: bool = false


## Shrinks `b`'s text, down to MIN_FONT, until it fits the button (a long word in a half
## rail button, a longer language); a button that wraps its text fits its longest word.
static func fit_text(b: Button) -> void:
	b.remove_theme_font_size_override("font_size")
	var font: Font = b.get_theme_font("font")
	var room: float = b.size.x - b.get_theme_stylebox("normal").get_minimum_size().x
	var fs: int = b.get_theme_font_size("font_size")
	var parts: PackedStringArray = [b.text]
	if b.autowrap_mode != TextServer.AUTOWRAP_OFF:
		parts = b.text.split(" ", false)
	while fs > MIN_FONT and _widest(font, parts, fs) > room:
		fs -= 1
	b.add_theme_font_size_override("font_size", fs)


static func _widest(font: Font, parts: PackedStringArray, fs: int) -> float:
	var w: float = 0.0
	for part: String in parts:
		w = maxf(w, font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w


## Lets `b`'s text take two lines where one doesn't fit (a verb and its object in a half rail
## button, C3); fit_text then fits its longest word.
static func wrap(b: Button) -> void:
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false


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
		_explained = false
		TouchInput.held += 1
		_show_down(true)
		_hold(true)
		if not hold and is_inside_tree():
			get_tree().create_timer(HoldHelp.HOLD_S).timeout.connect(_explain.bind(t.index))
	elif not t.pressed and t.index == _touch:
		var tapped: bool = Rect2(Vector2.ZERO, size).has_point(t.position) and not _explained
		_release()
		if tapped:
			_click()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _touch >= 0:
		_release()


func _exit_tree() -> void:
	if _touch >= 0:
		_release()


## The mouse hover's line: what the button does.
func _get_tooltip(_at_position: Vector2) -> String:
	return tooltip_text if tooltip_text != "" else HoldHelp.explain(text)


## The finger `index` is still down after HoldHelp.HOLD_S: say what the button does.
func _explain(index: int) -> void:
	if _touch != index or hold or not is_inside_tree():
		return
	var line: String = HoldHelp.explain(text)
	if line != "":
		_explained = true
		HoldHelp.bubble(self, line)


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
