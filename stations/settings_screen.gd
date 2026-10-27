class_name SettingsScreen
extends PanelContainer
## The menu (per client, ClientSettings), one opaque screen with tabs: Controls (only in
## a session: the live bindings under the seat's role summary, ControlsPane; FT-STN-011,
## FT-STN-012, D185), Settings (UI scale 75-150 % FT-STN-013, invert pitch, first-run
## tips again, and comfort FT-STN-017: on/off, roll lock deck / target / reference plane,
## "set reference plane to my current deck", reduced field of view; the station cameras
## apply them) and Rebind keys (bindings per intent and device with rebind, hold/toggle
## and reset, FT-STN-007, FT-STN-014). Esc opens it on the tab last used (Settings at
## first), `?` and the first visit to a seat open Controls. Saved on close; a language
## switch retranslates it at once. In a session it also offers Leave.

signal closed
signal leave_requested
signal host_pause_requested
## The abandon-run control was pressed (D241): the host abandons, a crew player votes.
signal abandon_requested
signal scale_changed
## "Set reference plane to my current deck": the shell stores the ship's orientation.
signal reference_plane_requested

## Intents that can't be left unbound: the way back to Settings, and the way to say no.
const ALWAYS_BOUND: Array[String] = ["menu", "decline"]
const MODIFIER_KEYS: Array[Key] = [KEY_SHIFT, KEY_ALT, KEY_CTRL]
## A trigger or stick past this deflection is captured.
const CAPTURE_DEFLECT: float = 0.5

## The tab names: the children of `tabs`.
const TAB_CONTROLS: String = "Controls"
const TAB_SETTINGS: String = "Settings"
const TAB_KEYS: String = "Keys"

var settings: ClientSettings
## Waiting for an input to bind: [intent id, device], or [].
var capturing: Array = []
## Why the last captured input was refused ("" when it wasn't).
var warning: Label
var tabs: TabContainer
## The Controls tab's text list; null outside a session.
var controls: ControlsList
## The Controls tab: the diagrams and the list (ControlsPane); null outside a session.
var controls_pane: ControlsPane

## Modifier keys and pad buttons held during a capture, in press order.
var _held: Array[String] = []

var _in_session: bool = false
## The host's Pause control is offered (co-op host only, FT-MIS-040).
var _pause_control: bool = false
## The string key of the abandon-run control's label, "" when it isn't offered (D241).
var _abandon_key: String = ""
## What _build fills: a notification may not change the children of its own node.
var _root: VBoxContainer
## What `controls` shows, kept to refill it when the menu is rebuilt: [bindings,
## stations, device, role] or [].
var _controls_args: Array = []
var _rows: VBoxContainer
var _scale_label: Label


func setup(p_settings: ClientSettings, in_session: bool) -> void:
	settings = p_settings
	_in_session = in_session
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Opaque: the station behind must not show through (D185).
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Palette.color("panel")
	box.set_content_margin_all(16)
	add_theme_stylebox_override("panel", box)
	_root = VBoxContainer.new()
	add_child(_root)
	_build()


## Fills the Controls tab for `stations` on `device` under the role summary of `role`.
func set_controls(bindings: Bindings, stations: Array, device: String, role: String) -> void:
	_controls_args = [bindings, stations, device, role]
	if controls_pane != null:
		controls_pane.build(bindings, stations, device, role)


## Opens the menu on `tab` (a TAB_ name), or on the tab last used when empty.
## Shows or hides the host's Pause control (rebuilds the menu on a change).
func set_pause_control(on: bool) -> void:
	if on != _pause_control:
		_pause_control = on
		if _root != null:
			_build()


## Shows the abandon-run control under `key` (CrewState.abandon_control), "" hides it.
func set_abandon_control(key: String) -> void:
	if key != _abandon_key:
		_abandon_key = key
		if _root != null:
			_build()


func open(tab: String = "") -> void:
	visible = true
	open_tab(tab)


## The name of the tab showing.
func current_tab_name() -> String:
	return tabs.get_current_tab_control().name


func close() -> void:
	capturing = []
	visible = false
	settings.save()
	closed.emit()


func set_ui_scale(value: float) -> void:
	settings.set_ui_scale(value)
	_scale_label.text = "%d %%" % roundi(settings.ui_scale * 100.0)
	scale_changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and settings != null:
		_build()


## (Re)builds the tabs in the current language, keeping the tab showing.
func _build() -> void:
	var keep: String = current_tab_name() if tabs != null else TAB_SETTINGS
	capturing = []
	for c: Node in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	var col: VBoxContainer = _root
	col.add_theme_constant_override("separation", 8)
	var top: HBoxContainer = HBoxContainer.new()
	col.add_child(top)
	_add_button(top, "Close", tr("settings.close"), close)
	if _pause_control:
		_add_button(
			top,
			"HostPause",
			tr("settings.pause"),
			func() -> void:
				host_pause_requested.emit()
				close()
		)
	if _abandon_key != "":
		_add_button(
			top,
			"Abandon",
			tr(_abandon_key),
			func() -> void:
				abandon_requested.emit()
				close()
		)
	if _in_session:
		_add_button(top, "Leave", tr("settings.leave"), func() -> void: leave_requested.emit())
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	controls = null
	controls_pane = null
	if _in_session:
		controls_pane = ControlsPane.new()
		controls = controls_pane.list
		_tab(TAB_CONTROLS, tr("overlay.title"), controls_pane)
		if not _controls_args.is_empty():
			controls_pane.build(
				_controls_args[0], _controls_args[1], _controls_args[2], _controls_args[3]
			)
	var general: VBoxContainer = VBoxContainer.new()
	_tab(TAB_SETTINGS, tr("menu.settings"), general)
	_build_general(general)
	_build_comfort(general)
	var keys: VBoxContainer = VBoxContainer.new()
	_tab(TAB_KEYS, tr("settings.bindings"), keys)
	warning = _label("")
	warning.name = "Warning"
	warning.add_theme_color_override("font_color", Palette.color("warn"))
	_add_button(keys, "ResetBindings", tr("settings.reset_bindings"), _reset_bindings)
	keys.add_child(warning)
	_rows = VBoxContainer.new()
	keys.add_child(_rows)
	_build_bindings()
	open_tab(keep)


## One scrolling tab named `node_name` titled `title` holding `content`.
func _tab(node_name: String, title: String, content: Control) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = node_name
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	tabs.add_child(scroll)
	tabs.set_tab_title(scroll.get_index(), title)


func open_tab(tab: String) -> void:
	var node: Node = tabs.get_node_or_null(tab)
	if node != null:
		tabs.current_tab = tabs.get_tab_idx_from_control(node as Control)


## Starts capturing the next input as the binding of `id` on `device`.
func start_capture(id: String, device: String) -> void:
	capturing = [id, device]
	_held.clear()
	warning.text = ""


## Esc (or the pad's Menu) closes Settings. While capturing: a key, mouse button, pad
## button, trigger or stick becomes the binding; a modifier key or a pad button held
## first makes a chord, or binds alone when released alone; Esc cancels and Backspace
## unbinds, unless that key is the intent's default (Menu's Esc, Decline's Backspace).
func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if capturing.is_empty():
		if event.is_pressed() and _is_back(event):
			get_viewport().set_input_as_handled()
			close()
		return
	get_viewport().set_input_as_handled()
	var id: String = capturing[0]
	var device: String = capturing[1]
	var token: String = binding_from_event(event, device, IntentTable.row(id)["kind"])
	var pressed: bool = _pressed(event)
	var key: InputEventKey = event as InputEventKey
	if key != null and pressed and token not in IntentTable.defaults(id, device):
		if _code(key) == KEY_ESCAPE:
			capturing = []
			_build_bindings()
			return
		if _code(key) == KEY_BACKSPACE:
			_bind([])
			return
	if token == "":
		return
	if event is InputEventJoypadMotion and token not in ["LT", "RT"]:
		# A stick binds at once, after any pad buttons held.
		_bind(["+".join(_held + [token])])
	elif device == IntentTable.KBM and (key == null or _code(key) not in MODIFIER_KEYS):
		if pressed:
			_bind([token])
	elif pressed and token not in _held:
		if device == IntentTable.PAD and not _held.is_empty():
			_bind(["+".join(_held + [token])])
		else:
			_held.append(token)
	elif not pressed and token in _held:
		_bind(["+".join(_held)])


## The binding string (input/README.md grammar) of one event on `device`, or "": a key
## (physical, with Shift, Alt and Ctrl held) or mouse button, a pad button, a trigger
## or a stick past CAPTURE_DEFLECT (an axis intent, kind AXIS, gets the signed axis,
## "-LS_X"; others the stick, "LS"). Releases give the same name.
static func binding_from_event(event: InputEvent, device: String, kind: String = "") -> String:
	if device == IntentTable.KBM and event is InputEventKey:
		var k: InputEventKey = event
		if _code(k) == KEY_META:
			return ""
		var name: String = OS.get_keycode_string(_code(k))
		if _code(k) in MODIFIER_KEYS:
			return name
		return _mods(k) + name
	if device == IntentTable.KBM and event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		var mouse: Variant = InputMatcher.MOUSE_NAMES.find_key(mb.button_index)
		return "" if mouse == null else _mods(mb) + str(mouse)
	if device == IntentTable.PAD and event is InputEventJoypadButton:
		var pad: Variant = InputMatcher.PAD_BUTTONS.find_key(event.button_index)
		return "" if pad == null else str(pad)
	if device == IntentTable.PAD and event is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = event
		var axis: Variant = InputMatcher.PAD_AXES.find_key(m.axis)
		if axis == null:
			return ""
		var a: String = str(axis)
		if a in ["LT", "RT"]:
			return a
		if absf(m.axis_value) < CAPTURE_DEFLECT:
			return ""
		if kind == IntentTable.AXIS:
			return ("-" if m.axis_value < 0.0 else "") + a
		return a.left(2)
	return ""


## Pressed, with a trigger or stick pressed past CAPTURE_DEFLECT.
static func _pressed(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= CAPTURE_DEFLECT
	return event.is_pressed()


static func _code(k: InputEventKey) -> Key:
	return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode


static func _mods(ev: InputEventWithModifiers) -> String:
	return (
		("Shift+" if ev.shift_pressed else "")
		+ ("Alt+" if ev.alt_pressed else "")
		+ ("Ctrl+" if ev.ctrl_pressed else "")
	)


static func _is_back(event: InputEvent) -> bool:
	if event is InputEventKey:
		return _code(event as InputEventKey) == KEY_ESCAPE
	return event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START


## Binds `list` to the intent being captured, unless that collides with a common or
## always-live binding (refused with a warning, capture goes on) or leaves Menu or
## Decline unbound.
func _bind(list: Array[String]) -> void:
	var id: String = capturing[0]
	var device: String = capturing[1]
	if list.is_empty() and id in ALWAYS_BOUND:
		warning.text = tr("settings.must_bind")
		return
	for b: String in list:
		var other: String = collision(settings.bindings, id, device, b)
		if other != "":
			warning.text = tr("settings.taken").format({"intent": tr(IntentTable.label_key(other))})
			_held.clear()
			return
	settings.bindings.rebind(id, device, PackedStringArray(list))
	capturing = []
	_build_bindings()


## The intent that `binding` on `device` would clash with if bound to `id`, or "": two
## intents may share a binding unless one of them is common or always live (they act
## on every station). LMB is select and fire at once (D176).
static func collision(bindings: Bindings, id: String, device: String, binding: String) -> String:
	for other: String in bindings.intents_bound_to(binding, device):
		if (
			other == id
			or (binding == "LMB" and [id, other] in [["fire", "select"], ["select", "fire"]])
		):
			continue
		for x: String in [id, other]:
			if IntentTable.row(x)["group"] == IntentTable.COMMON or IntentTable.is_live(x, device):
				return other
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
