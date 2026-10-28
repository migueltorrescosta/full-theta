class_name SettingsScreen
extends PanelContainer
## The menu (per client, ClientSettings; FT-STN-011, D185, P28 menu), one opaque screen
## with tabs. In a session: Game (the ship's name, Sound, Full screen where offered, the
## host's Pause, Abandon or Give up, Leave; the final ones ask to confirm in place), Controls
## (the live bindings under the seat's role summary, ControlsPane; FT-STN-012), Tips, then
## Settings (UI scale 75-150 % FT-STN-013, invert pitch, first-run tips again, and comfort
## FT-STN-017: on/off, roll lock deck / target / reference plane, "set reference plane to
## my current deck", reduced field of view; the station cameras apply them) and Rebind keys
## (bindings per intent and device with rebind, hold/toggle and reset, FT-STN-007,
## FT-STN-014; hidden on a phone, which has no keys). Esc opens it on the tab last used
## (Game at first in a session, Settings outside one), `?` on Controls; help never opens
## by itself (P28-Help, ControlsChip). Saved on close; a language switch retranslates it
## at once. A change of the Pause or Abandon control updates its button in place, never
## the whole menu (load fix 2).

signal closed
signal leave_requested
signal host_pause_requested
## The abandon-run control was pressed (D241): the host abandons (after confirming here),
## a crew player votes.
signal abandon_requested
signal scale_changed
## "Set reference plane to my current deck": the shell stores the ship's orientation.
signal reference_plane_requested

## Intents that can't be left unbound: the way back to Settings, and the way to say no.
const ALWAYS_BOUND: Array[String] = ["menu", "decline"]
const MODIFIER_KEYS: Array[Key] = [KEY_SHIFT, KEY_ALT, KEY_CTRL]
## A trigger or stick past this deflection is captured.
const CAPTURE_DEFLECT: float = 0.5
## How long a final button waits for its second tap (ms).
const CONFIRM_MS: int = 4000
## The abandon-control keys that end the run at once (the host's), so they confirm first.
const FINAL_ABANDON: Array[String] = ["settings.abandon", "settings.forfeit"]

## The tab names: the children of `tabs`.
const TAB_GAME: String = "Game"
const TAB_CONTROLS: String = "Controls"
const TAB_TIPS: String = "Tips"
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
var _ship_name: String = ""
## What _build fills: a notification may not change the children of its own node.
var _root: VBoxContainer
## What `controls` shows, kept to refill it when the menu is rebuilt: [bindings,
## stations, device, role] or [].
var _controls_args: Array = []
var _rows: VBoxContainer
var _scale_label: Label
var _scale_slider: HSlider
## The Game tab's controls (null outside a session).
var _ship_label: Label
var _sound: SoundToggle
var _pause_button: Button
var _abandon_button: Button
var _leave_button: Button
## Final buttons waiting for their second tap: {button name: deadline in ms}.
var _armed: Dictionary = {}
## The opaque panel; its margins keep the menu inside the safe area (#28).
var _box: StyleBoxFlat


func setup(p_settings: ClientSettings, in_session: bool) -> void:
	settings = p_settings
	_in_session = in_session
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Opaque: the station behind must not show through (D185).
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Palette.color("panel")
	box.set_content_margin_all(16)
	add_theme_stylebox_override("panel", box)
	_box = box
	_root = VBoxContainer.new()
	add_child(_root)
	_build()


## Fills the Controls tab for `stations` on `device` under the role summary of `role`.
## Cheap: the pane builds a diagram only when it shows (load fix 1).
func set_controls(bindings: Bindings, stations: Array, device: String, role: String) -> void:
	_controls_args = [bindings, stations, device, role]
	if controls_pane != null:
		controls_pane.build(bindings, stations, device, role)


## Shows or hides the host's Pause control, in place.
func set_pause_control(on: bool) -> void:
	_pause_control = on
	if _pause_button != null:
		_pause_button.visible = on


## Shows the abandon-run control under `key` (CrewState.abandon_control), "" hides it; in
## place.
func set_abandon_control(key: String) -> void:
	if key == _abandon_key:
		return
	_abandon_key = key
	_armed.erase("Abandon")
	_show_abandon()


func _show_abandon() -> void:
	if _abandon_button != null:
		_abandon_button.visible = _abandon_key != ""
		_abandon_button.text = tr(_abandon_key) if _abandon_key != "" else ""


## The ship's name on the Game tab ("" hides it).
func set_ship_name(text: String) -> void:
	_ship_name = text
	if _ship_label != null:
		_ship_label.text = tr("menu.ship") % text
		_ship_label.visible = text != ""


## Opens the menu on `tab` (a TAB_ name), or on the tab last used when empty.
func open(tab: String = "") -> void:
	visible = true
	if _sound != null:
		# The top bar's toggle may have changed the sound since.
		_sound.button_pressed = _sound.is_on()
	open_tab(tab)


## The name of the tab showing.
func current_tab_name() -> String:
	return tabs.get_current_tab_control().name


func close() -> void:
	capturing = []
	_disarm_all()
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
	elif what == NOTIFICATION_ENTER_TREE:
		if not get_viewport().size_changed.is_connected(_fit_safe_area):
			get_viewport().size_changed.connect(_fit_safe_area)
		_fit_safe_area.call_deferred()
	elif what == NOTIFICATION_EXIT_TREE:
		if get_viewport().size_changed.is_connected(_fit_safe_area):
			get_viewport().size_changed.disconnect(_fit_safe_area)


## Keeps the menu clear of notches and, on a phone, the gesture band (SafeArea, #28); a
## phone has no Rebind keys tab.
func _fit_safe_area() -> void:
	if _box == null or not is_inside_tree():
		return
	var m: Vector4 = SafeArea.margins(self)
	_box.content_margin_left = 16.0 + m.x
	_box.content_margin_top = 16.0 + m.y
	_box.content_margin_right = 16.0 + m.z
	_box.content_margin_bottom = 16.0 + maxf(m.w, SafeArea.tap_band(self))
	var kind: LayoutMode.Kind = LayoutMode.kind_of(self)
	# A finger needs the slider's full touch height (#28: nothing tappable under 44 px).
	if _scale_slider != null:
		_scale_slider.custom_minimum_size.y = (
			UiTheme.TOUCH_MIN if LayoutMode.is_touch(kind) else 0.0
		)
	# A window that became a phone hides Rebind keys; one that stopped being one gets it.
	var keys: Node = tabs.get_node_or_null(TAB_KEYS) if tabs != null else null
	var phone: bool = kind == LayoutMode.Kind.PHONE
	if keys != null:
		if phone and tabs.get_current_tab_control() == keys:
			open_tab(TAB_SETTINGS)
		tabs.set_tab_hidden(keys.get_index(), phone)
	elif tabs != null and not phone:
		_build_keys()


## (Re)builds the tabs in the current language, keeping the tab showing.
func _build() -> void:
	var keep: String = TAB_GAME if _in_session else TAB_SETTINGS
	if tabs != null:
		keep = current_tab_name()
	capturing = []
	_armed.clear()
	for c: Node in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	var col: VBoxContainer = _root
	col.add_theme_constant_override("separation", 8)
	var top: HBoxContainer = HBoxContainer.new()
	col.add_child(top)
	_add_button(top, "Close", tr("settings.close"), close)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	controls = null
	controls_pane = null
	if _in_session:
		var game: VBoxContainer = VBoxContainer.new()
		_tab(TAB_GAME, tr("menu.tab_game"), game)
		_build_game(game)
		controls_pane = ControlsPane.new()
		controls = controls_pane.list
		_tab(TAB_CONTROLS, tr("overlay.title"), controls_pane)
		if not _controls_args.is_empty():
			controls_pane.build(
				_controls_args[0], _controls_args[1], _controls_args[2], _controls_args[3]
			)
		_tab(TAB_TIPS, tr("menu.tab_tips"), _tips_view())
	var general: VBoxContainer = VBoxContainer.new()
	_tab(TAB_SETTINGS, tr("menu.settings"), general)
	_build_general(general)
	_build_comfort(general)
	# A phone has no keys to rebind; a hidden tab would still widen the tab bar.
	_rows = null
	if not _phone():
		_build_keys()
	open_tab(keep)
	_fit_safe_area()


func _build_keys() -> void:
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


func _phone() -> bool:
	return is_inside_tree() and LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE


## The Game tab: the ship, Sound, Full screen, the host's Pause, Abandon or Give up, Leave;
## 48 px rows a thumb can hit.
func _build_game(col: VBoxContainer) -> void:
	_ship_label = _label("", 20)
	_ship_label.name = "ShipName"
	col.add_child(_ship_label)
	set_ship_name(_ship_name)
	_sound = SoundToggle.new()
	_sound.name = "Sound"
	_sound.flat = false
	_row(_sound)
	col.add_child(_sound)
	_add_fullscreen(col)
	_pause_button = _add_button(
		col,
		"HostPause",
		tr("settings.pause"),
		func() -> void:
			host_pause_requested.emit()
			close()
	)
	_row(_pause_button)
	_pause_button.visible = _pause_control
	_abandon_button = _add_button(col, "Abandon", "", _on_abandon)
	_row(_abandon_button)
	_show_abandon()
	_leave_button = _add_button(
		col,
		"Leave",
		tr("settings.leave"),
		func() -> void: _confirm(_leave_button, func() -> void: leave_requested.emit())
	)
	_row(_leave_button)


## Android and iPad only: fullscreen and a landscape lock (#28, load fix 6).
func _add_fullscreen(col: VBoxContainer) -> void:
	var fullscreen: FullscreenButton = FullscreenButton.new()
	fullscreen.name = "Fullscreen"
	fullscreen.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Its full label here, not a rail button's trimmed one ("Full").
	fullscreen.clip_text = false
	fullscreen.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	col.add_child(fullscreen)


## The Tips tab. The lead swaps in TipsView (strand T) at merge.
func _tips_view() -> Control:
	var l: Label = _label(tr("menu.tab_tips"))
	l.name = "TipsView"
	return l


func _on_abandon() -> void:
	var act: Callable = func() -> void:
		abandon_requested.emit()
		close()
	if _abandon_key in FINAL_ABANDON:
		_confirm(_abandon_button, act)
	else:
		act.call()


## A final button acts on its second tap within CONFIRM_MS; the first turns its label into
## "Tap again", which reverts if no second tap comes.
func _confirm(b: Button, act: Callable) -> void:
	var now: int = Time.get_ticks_msec()
	if int(_armed.get(b.name, -1)) >= now:
		_armed.erase(b.name)
		_restore(b)
		act.call()
		return
	_armed[b.name] = now + CONFIRM_MS
	b.text = tr("settings.confirm_leave" if b == _leave_button else "settings.confirm")
	if is_inside_tree():
		get_tree().create_timer(CONFIRM_MS / 1000.0).timeout.connect(
			func() -> void:
				if is_instance_valid(b) and int(_armed.get(b.name, -1)) < Time.get_ticks_msec():
					_armed.erase(b.name)
					_restore(b)
		)


## A final button's own label again.
func _restore(b: Button) -> void:
	if b == _leave_button:
		b.text = tr("settings.leave")
	elif b == _abandon_button and _abandon_key != "":
		b.text = tr(_abandon_key)


func _disarm_all() -> void:
	_armed.clear()
	for b: Button in [_leave_button, _abandon_button]:
		if b != null and is_instance_valid(b):
			_restore(b)


## A Game tab row: 48 px tall, as wide as its label.
static func _row(b: Button) -> void:
	b.custom_minimum_size.y = UiTheme.TOUCH_PRIMARY
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


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
	_scale_slider = slider
	_scale_label = _label("%d %%" % roundi(settings.ui_scale * 100.0))
	scale_row.add_child(_scale_label)
	_check(col, "InvertPitch", tr("settings.invert_pitch"), settings.invert_pitch).toggled.connect(
		func(on: bool) -> void: settings.invert_pitch = on
	)
	_add_button(
		col, "ResetTips", tr("settings.reset_tips"), func() -> void: settings.reset_tooltips()
	)
	# In a session it sits on the Game tab.
	if not _in_session:
		_add_fullscreen(col)


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
	if _rows == null:
		return
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
