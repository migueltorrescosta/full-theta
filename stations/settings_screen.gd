class_name SettingsScreen
extends PanelContainer
## Settings (per client, ClientSettings): bindings per intent and device with rebind,
## hold/toggle and reset (FT-STN-007, FT-STN-014), UI scale 75-150 % (FT-STN-013),
## first-run tips again (FT-STN-012), invert pitch, and comfort (FT-STN-017: on/off,
## roll lock deck / target / reference plane, "set reference plane to my current deck",
## reduced field of view; the station cameras apply them). Saved on close. In a session
## it also offers Leave.

signal closed
signal leave_requested
signal scale_changed
## "Set reference plane to my current deck": the shell stores the ship's orientation.
signal reference_plane_requested

var settings: ClientSettings
## Waiting for an input to bind: [intent id, device], or [].
var capturing: Array = []

var _rows: VBoxContainer
var _scale_label: Label


func setup(p_settings: ClientSettings, in_session: bool) -> void:
	settings = p_settings
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll: ScrollContainer = ScrollContainer.new()
	add_child(scroll)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	var top: HBoxContainer = HBoxContainer.new()
	col.add_child(top)
	_add_button(top, "Close", tr("settings.close"), close)
	if in_session:
		_add_button(top, "Leave", tr("settings.leave"), func() -> void: leave_requested.emit())
	_build_general(col)
	_build_comfort(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label(tr("settings.bindings"), 22))
	_add_button(head, "ResetBindings", tr("settings.reset_bindings"), _reset_bindings)
	_rows = VBoxContainer.new()
	col.add_child(_rows)
	_build_bindings()


func open() -> void:
	visible = true


func close() -> void:
	capturing = []
	visible = false
	settings.save()
	closed.emit()


func set_ui_scale(value: float) -> void:
	settings.set_ui_scale(value)
	_scale_label.text = "%d %%" % roundi(settings.ui_scale * 100.0)
	scale_changed.emit()


## Starts capturing the next input as the binding of `id` on `device`.
func start_capture(id: String, device: String) -> void:
	capturing = [id, device]


func _input(event: InputEvent) -> void:
	if capturing.is_empty() or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	# Escape cancels; Backspace unbinds (provisional).
	if event is InputEventKey and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_BACKSPACE]:
		if (event as InputEventKey).keycode == KEY_BACKSPACE:
			settings.bindings.rebind(capturing[0], capturing[1], PackedStringArray())
		capturing = []
		_build_bindings()
		return
	var b: String = binding_from_event(event, capturing[1])
	if b == "":
		return
	settings.bindings.rebind(capturing[0], capturing[1], PackedStringArray([b]))
	capturing = []
	_build_bindings()


## The binding string (input/README.md grammar) of a pressed event on `device`, or "".
static func binding_from_event(event: InputEvent, device: String) -> String:
	if device == IntentTable.KBM and event is InputEventKey:
		var k: InputEventKey = event
		if k.keycode in [KEY_SHIFT, KEY_ALT, KEY_CTRL, KEY_META]:
			return ""
		var mods: String = (
			("Shift+" if k.shift_pressed else "")
			+ ("Alt+" if k.alt_pressed else "")
			+ ("Ctrl+" if k.ctrl_pressed else "")
		)
		return mods + OS.get_keycode_string(k.keycode)
	if device == IntentTable.KBM and event is InputEventMouseButton:
		var names: Dictionary = {
			MOUSE_BUTTON_LEFT: "LMB",
			MOUSE_BUTTON_RIGHT: "RMB",
			MOUSE_BUTTON_MIDDLE: "MMB",
			MOUSE_BUTTON_WHEEL_UP: "WheelUp",
			MOUSE_BUTTON_WHEEL_DOWN: "WheelDown",
		}
		var mb: InputEventMouseButton = event
		var mods: String = "Shift+" if mb.shift_pressed else ""
		return mods + str(names.get(mb.button_index, "")) if names.has(mb.button_index) else ""
	if device == IntentTable.PAD and event is InputEventJoypadButton:
		var pads: Dictionary = {
			JOY_BUTTON_A: "A",
			JOY_BUTTON_B: "B",
			JOY_BUTTON_X: "X",
			JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB",
			JOY_BUTTON_RIGHT_SHOULDER: "RB",
			JOY_BUTTON_LEFT_STICK: "L3",
			JOY_BUTTON_RIGHT_STICK: "R3",
			JOY_BUTTON_BACK: "View",
			JOY_BUTTON_START: "Menu",
			JOY_BUTTON_DPAD_UP: "Up",
			JOY_BUTTON_DPAD_DOWN: "Down",
			JOY_BUTTON_DPAD_LEFT: "Left",
			JOY_BUTTON_DPAD_RIGHT: "Right",
		}
		return str(pads.get((event as InputEventJoypadButton).button_index, ""))
	return ""


func _build_general(col: VBoxContainer) -> void:
	var scale_row: HBoxContainer = HBoxContainer.new()
	col.add_child(scale_row)
	scale_row.add_child(_label(tr("settings.ui_scale")))
	var slider: HSlider = HSlider.new()
	slider.name = "UiScale"
	slider.min_value = ClientSettings.UI_SCALE_MIN * 100.0
	slider.max_value = ClientSettings.UI_SCALE_MAX * 100.0
	slider.step = ClientSettings.UI_SCALE_STEP * 100.0
	slider.value = settings.ui_scale * 100.0
	slider.custom_minimum_size = Vector2(240, 0)
	slider.value_changed.connect(func(v: float) -> void: set_ui_scale(v / 100.0))
	scale_row.add_child(slider)
	_scale_label = _label("%d %%" % roundi(settings.ui_scale * 100.0))
	scale_row.add_child(_scale_label)
	_check(col, "InvertPitch", tr("settings.invert_pitch"), settings.invert_pitch).toggled.connect(
		func(on: bool) -> void: settings.invert_pitch = on
	)
	_add_button(
		col, "ResetTips", tr("settings.reset_tips"), func() -> void: settings.reset_tooltips()
	)


func _build_comfort(col: VBoxContainer) -> void:
	col.add_child(_label(tr("settings.comfort"), 22))
	_check(col, "Comfort", tr("settings.comfort_on"), settings.comfort).toggled.connect(
		func(on: bool) -> void: settings.comfort = on
	)
	var lock: OptionButton = OptionButton.new()
	lock.name = "RollLock"
	for l: String in ClientSettings.ROLL_LOCKS:
		lock.add_item(tr("settings.roll_" + l))
	lock.selected = ClientSettings.ROLL_LOCKS.find(settings.roll_lock)
	lock.item_selected.connect(
		func(i: int) -> void: settings.roll_lock = ClientSettings.ROLL_LOCKS[i]
	)
	col.add_child(lock)
	_add_button(
		col,
		"SetReference",
		tr("settings.set_reference"),
		func() -> void: reference_plane_requested.emit()
	)
	_check(col, "ReducedFov", tr("settings.reduced_fov"), settings.reduced_fov).toggled.connect(
		func(on: bool) -> void: settings.reduced_fov = on
	)


## One row per intent: label, KB/M binding, controller binding, hold/toggle.
func _build_bindings() -> void:
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var group: String = ""
	for r: Dictionary in IntentTable.INTENTS:
		var id: String = r["id"]
		if r["group"] != group:
			group = r["group"]
			_rows.add_child(_label(tr("settings.group_" + group), 18))
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Row_" + id
		_rows.add_child(row)
		var name_label: Label = _label(tr(IntentTable.label_key(id)))
		name_label.custom_minimum_size = Vector2(260, 0)
		row.add_child(name_label)
		for device: String in IntentTable.DEVICES:
			var text: String = BindingText.describe_all(settings.bindings.bindings(id, device))
			var b: Button = _add_button(
				row, device, text if text != "" else "-", start_capture.bind(id, device)
			)
			b.custom_minimum_size = Vector2(170, 0)
		if r["kind"] == IntentTable.HOLD:
			_check(row, "Toggle", tr("settings.toggle"), settings.bindings.is_toggle(id)).toggled.connect(
				func(on: bool) -> void: settings.bindings.set_toggle(id, on)
			)


func _reset_bindings() -> void:
	settings.bindings.reset()
	_build_bindings()


func _label(text: String, font_size: int = 0) -> Label:
	var l: Label = Label.new()
	l.text = text
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	return l


func _add_button(parent: Node, node_name: String, text: String, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _check(parent: Node, node_name: String, text: String, on: bool) -> CheckBox:
	var c: CheckBox = CheckBox.new()
	c.name = node_name
	c.text = text
	c.button_pressed = on
	parent.add_child(c)
	return c
