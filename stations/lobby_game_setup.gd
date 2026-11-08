class_name LobbyGameSetup
extends RefCounted
## The lobby's game setup (#37 C1's setup sheet): the difficulty row (the Mode button, the
## one-line difficulty and Customise), the Mode dialog (ModeDialog, M4-Q6) and the Customise
## dialog of the data-shortcut toggles (FT-PAIR-017, FT-STN-016; read-only for the others).
## Only the host changes the toggles, and only before a run starts. It builds its row and
## dialogs; LobbyScreen places the row and lays it out.

## A toggle change was refused here (the toggles are locked or not the host's): the screen
## shows the session's set again.
signal refresh_needed

## The difficulty row: the Mode button, the difficulty line and Customise.
var row: HBoxContainer
var mode_button: Button
var difficulty: Label
var customise: Button
var _ctx: StationContext
var _mode_dialog: ModeDialog
var _dialog: AcceptDialog
var _preset_buttons: Dictionary = {}
var _preset_name: Label
var _toggle_rows: VBoxContainer
var _toggle_note: Label
## The host's saved set was sent to the server for this connection.
var _pushed: bool = false


func _init(context: StationContext) -> void:
	_ctx = context
	row = HBoxContainer.new()
	row.name = "Difficulty"
	mode_button = _button("ModeButton", "", _open_mode)
	row.add_child(mode_button)
	difficulty = _label("")
	difficulty.name = "DifficultyLine"
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(difficulty)
	customise = _button("Customise", tr("lobby.customise"), _open_difficulty)
	row.add_child(customise)


## "Easy", or "Easy (custom)" for a set with a toggle changed (FT-PAIR-017, D92).
static func preset_label(toggles: DataToggles) -> String:
	var name: String = TranslationServer.translate("lobby.preset_" + toggles.preset)
	if toggles.is_custom():
		return TranslationServer.translate("lobby.preset_custom") % name
	return name


## Whether a run has started on any ship: the toggles are locked from then on.
func toggles_locked() -> bool:
	for state: Dictionary in _ctx.crew.lobby.values():
		if bool(state.get("started", false)):
			return true
	return false


## Only the host changes the toggles, and only before a run starts.
func can_edit_toggles() -> bool:
	return _ctx.crew.host and not toggles_locked()


## The mode button: "Mode: Teams (First to finish)" (M4-Q6); on a narrow or short screen
## just the mode's name.
func mode_text(narrow: bool) -> String:
	var name: String = tr("mode." + _ctx.crew.mode())
	if narrow:
		return tr("lobby.mode") % name  # still labelled: "Mode: Teams" (R24-5)
	if _ctx.crew.mode() == "teams":
		name = (
			tr("lobby.mode_rule")
			% [name, tr("mode.win." + str(_ctx.crew.fleet.get("team_win", "")))]
		)
	return tr("lobby.mode") % name


## The mode button and the mode dialog, from the `fleet` event.
func refresh_mode(text: String) -> void:
	mode_button.text = text
	mode_button.visible = not _ctx.crew.fleet.is_empty()
	if _mode_dialog != null:
		_mode_dialog.refresh()


## Customise names the preset on a phone or a short screen ("Difficulty: Easy").
func label_customise(small: bool) -> void:
	customise.text = (
		tr("lobby.difficulty") % preset_label(_ctx.crew.toggles) if small else tr("lobby.customise")
	)


static func _label(text: String, variation: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _button(node_name: String, text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.pressed.connect(handler)
	return b


## The difficulty toggles dialog and the mode dialog, added to `host`.
func add_dialogs(host: Node) -> void:
	_dialog = AcceptDialog.new()
	_dialog.name = "DifficultyDialog"
	_dialog.title = tr("lobby.data")
	_dialog.ok_button_text = tr("lobby.done")
	host.add_child(_dialog)
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	_dialog.add_child(col)
	var presets: HBoxContainer = HBoxContainer.new()
	presets.name = "Presets"
	col.add_child(presets)
	for preset: String in DataToggles.PRESETS:
		var b: Button = _button("Preset_" + preset, "", _choose_preset.bind(preset))
		b.toggle_mode = true
		_preset_buttons[preset] = b
		presets.add_child(b)
	_preset_name = _label("", "DimLabel")
	_preset_name.name = "PresetName"
	presets.add_child(_preset_name)
	_toggle_note = _label("", "DimLabel")
	_toggle_note.name = "ToggleNote"
	col.add_child(_toggle_note)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	col.add_child(scroll)
	_toggle_rows = VBoxContainer.new()
	_toggle_rows.name = "Toggles"
	_toggle_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_toggle_rows)
	for def: DataToggleDef in DataToggles.def().toggles:
		_toggle_rows.add_child(_toggle_row(def))
	_mode_dialog = ModeDialog.new()
	host.add_child(_mode_dialog)
	_mode_dialog.setup(_ctx)


## A language switch: the dialog's button (the rest follows the next refresh).
func retranslate() -> void:
	_dialog.ok_button_text = tr("lobby.done")


func _open_mode() -> void:
	_mode_dialog.open(mode_button.get_viewport_rect().size.x < 600.0)


func _open_difficulty() -> void:
	_dialog.popup_centered_clamped(Vector2i(520, 480), 0.9)


## One toggle: its name, its value and a one-line description naming both stations.
func _toggle_row(def: DataToggleDef) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Toggle_" + String(def.id)
	var line: HBoxContainer = HBoxContainer.new()
	line.name = "Line"
	box.add_child(line)
	var name: Label = Label.new()
	name.name = "Name"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name)
	var value: OptionButton = OptionButton.new()
	value.name = "Value"
	value.item_selected.connect(func(i: int) -> void: _set_value(def.id, value.get_item_id(i)))
	line.add_child(value)
	var desc: Label = _label("", "CaptionLabel")
	desc.name = "Desc"
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	return box


## Shows the session's set: the difficulty line, the pressed preset, every toggle's text
## and value, and whether the host can still change them; `small` as for label_customise.
func refresh(small: bool) -> void:
	var toggles: DataToggles = _ctx.crew.toggles
	var editable: bool = can_edit_toggles()
	difficulty.text = tr("lobby.difficulty") % preset_label(toggles)
	label_customise(small)
	_dialog.title = tr("lobby.data")
	_preset_name.text = preset_label(toggles)
	for preset: String in _preset_buttons:
		var b: Button = _preset_buttons[preset]
		b.text = tr("lobby.preset_" + preset)
		b.button_pressed = preset == toggles.preset and not toggles.is_custom()
		b.disabled = not editable
	var note: String = ""
	if toggles_locked():
		note = tr("lobby.toggles_locked")
	elif not _ctx.crew.host:
		note = tr("lobby.toggles_host_only")
	_toggle_note.text = note
	for def: DataToggleDef in DataToggles.def().toggles:
		var toggle: Control = _toggle_rows.get_node("Toggle_" + String(def.id))
		toggle.get_node("Line/Name").text = tr("lobby.toggle." + String(def.id))
		toggle.get_node("Desc").text = tr("lobby.toggle.%s.desc" % def.id)
		var value: OptionButton = toggle.get_node("Line/Value")
		value.clear()
		var summary: bool = def.kind == DataToggleDef.Kind.SUMMARY
		var names: Array[String] = ["off", "on"]
		if summary:
			names = ["absent", "banded", "exact"]
		for v: int in range(names.size() - 1, -1, -1):
			value.add_item(tr("lobby.v_" + names[v]), v)
		value.select(value.get_item_index(toggles.value(def.id)))
		value.disabled = not editable


func _choose_preset(preset: String) -> void:
	if can_edit_toggles():
		_apply_toggles(DataToggles.of_preset(preset))
	else:
		refresh_needed.emit()


func _set_value(id: StringName, v: int) -> void:
	if can_edit_toggles():
		_apply_toggles(_ctx.crew.toggles.with_value(id, v))
	else:
		refresh_needed.emit()


## Sends the host's choice and remembers it for the next lobby (FT-STN-016).
func _apply_toggles(toggles: DataToggles) -> void:
	var code: String = toggles.encode()
	_ctx.settings.host_toggles = code
	_ctx.settings.save()
	_ctx.intents.set_toggles(code)


## The host's lobby starts from its saved set: sent once per connection, before any run.
func push_saved_toggles() -> void:
	if _pushed or not _ctx.crew.host or toggles_locked():
		return
	_pushed = true
	if _ctx.settings.host_toggles != _ctx.crew.toggles.encode():
		_ctx.intents.set_toggles(_ctx.settings.host_toggles)
