class_name LobbyGameSetup
extends RefCounted
## The lobby's game setup (#37 C1): one line for everyone, the setup summary ("Co-op ·
## Normal", plus the team win rule in TEAMS and "(custom)" for an edited toggle set), and for
## the host a Game setup button opening one sheet: the mode (ModePanel, M4-Q6), the ships with
## their teams and Add a ship (M4-Q3, M4-Q6), and the difficulty presets with the data-shortcut
## toggles (FT-PAIR-017, FT-STN-016). Only the host opens it, and only before the game starts:
## the mode and toggles lock then. It builds its row and sheet; LobbyScreen places the row and
## lays it out.

## A toggle change was refused here (the toggles are locked): the screen shows the session's
## set again.
signal refresh_needed
## The host pressed Add a ship (LobbyScreen.add_ship names it and shows it once listed).
signal add_ship_requested

## The team letters (team 0 is A).
const TEAM_LETTERS: Array[String] = ["A", "B"]
## A sheet narrower than this puts two mode buttons a row.
const NARROW_SHEET: float = 600.0

## The setup row: the Game setup button (host) and the summary line.
var row: HBoxContainer
var setup_button: Button
var summary: Label
var _ctx: StationContext
var _sheet: AcceptDialog
var _mode: ModePanel
var _headings: Dictionary = {}
var _ships: VBoxContainer
var _add_ship: Button
var _preset_buttons: Dictionary = {}
var _preset_name: Label
var _toggle_rows: VBoxContainer
var _toggle_note: Label
## The host's saved set was sent to the server for this connection.
var _pushed: bool = false


func _init(context: StationContext) -> void:
	_ctx = context
	row = HBoxContainer.new()
	row.name = "Setup"
	setup_button = _button("GameSetup", tr("lobby.setup"), open)
	row.add_child(setup_button)
	summary = _label("", "DimLabel")
	summary.name = "SetupSummary"
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.max_lines_visible = 2
	row.add_child(summary)


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


## The one-line summary everyone sees: the mode (with its win rule in TEAMS) and the
## difficulty, "Co-op · Normal" (#37 C1).
func summary_text() -> String:
	var mode: String = tr("mode." + _ctx.crew.mode())
	if _ctx.crew.mode() == "teams":
		var rule: String = tr("mode.win." + str(_ctx.crew.fleet.get("team_win", "")))
		mode = tr("lobby.mode_rule") % [mode, rule]
	return tr("lobby.summary") % [mode, preset_label(_ctx.crew.toggles)]


static func _label(text: String, variation: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _button(node_name: String, text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size.y = UiTheme.TOUCH_MIN
	b.pressed.connect(handler)
	return b


func _heading(key: String, col: VBoxContainer) -> void:
	var l: Label = _label(tr(key), "HeadingLabel")
	l.name = "Heading_" + key.trim_prefix("lobby.")
	_headings[key] = l
	col.add_child(l)


## The Game setup sheet, added to `host`: mode, ships and teams, difficulty.
func add_dialogs(host: Node) -> void:
	_sheet = AcceptDialog.new()
	_sheet.name = "SetupDialog"
	_sheet.title = tr("lobby.setup")
	_sheet.ok_button_text = tr("lobby.done")
	host.add_child(_sheet)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "SetupScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet.add_child(scroll)
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "SetupSheet"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	scroll.add_child(col)
	_heading("lobby.mode_title", col)
	_mode = ModePanel.new()
	_mode.setup(_ctx)
	col.add_child(_mode)
	_heading("lobby.ships", col)
	_ships = VBoxContainer.new()
	_ships.name = "SetupShips"
	_ships.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.add_child(_ships)
	_add_ship = _button("AddShip", tr("lobby.add_ship"), add_ship_requested.emit)
	_add_ship.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_add_ship)
	_heading("lobby.data", col)
	var presets: HBoxContainer = HBoxContainer.new()
	presets.name = "Presets"
	presets.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
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
	_toggle_rows = VBoxContainer.new()
	_toggle_rows.name = "Toggles"
	_toggle_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_toggle_rows)
	for def: DataToggleDef in DataToggles.def().toggles:
		_toggle_rows.add_child(_toggle_row(def))


## A language switch: the sheet's title and button (the rest follows the next refresh).
func retranslate() -> void:
	_sheet.title = tr("lobby.setup")
	_sheet.ok_button_text = tr("lobby.done")
	setup_button.text = tr("lobby.setup")
	for key: String in _headings:
		(_headings[key] as Label).text = tr(key)
	_add_ship.text = tr("lobby.add_ship")


## The summary shares a short screen's one row with the buttons (trimmed when it must) and
## wraps elsewhere (a long mode name on a phone upright).
func fit_summary(short: bool) -> void:
	summary.autowrap_mode = TextServer.AUTOWRAP_OFF if short else TextServer.AUTOWRAP_WORD_SMART
	summary.clip_text = short
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


## Opens the sheet (the host's Game setup button), sized for the window.
func open() -> void:
	var view: Vector2 = row.get_viewport_rect().size
	var narrow: bool = view.x < NARROW_SHEET
	_mode.fit(narrow)
	refresh_mode()
	var scroll: ScrollContainer = _sheet.get_node("SetupScroll")
	scroll.custom_minimum_size = Vector2(minf(view.x * 0.9 - 32.0, 520.0), view.y * 0.8 - 110.0)
	_sheet.reset_size()
	_sheet.popup_centered()


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


## The row and the mode and ships parts of the sheet, from the `fleet` event: the Game setup
## button for the host only (#37 C1).
func refresh_mode() -> void:
	setup_button.visible = _ctx.crew.host
	summary.text = summary_text()
	if _mode == null:
		return
	_mode.refresh()
	_refresh_ships()


## The sheet's ships: each with its Team A and B buttons in TEAMS and HOLDOUT, and Add a
## ship while there is room (M4-Q3, M4-Q6); the section shows only when it has one of them.
func _refresh_ships() -> void:
	var teams: bool = _ctx.crew.has_teams()
	var ships: Array = _ctx.crew.fleet_ships() if teams else []
	for c: Node in _ships.get_children():
		_ships.remove_child(c)
		c.queue_free()
	var open: bool = not bool(_ctx.crew.fleet.get("started", false))
	for s: Dictionary in ships:
		var id: int = int(s["ship"])
		var line: HBoxContainer = HBoxContainer.new()
		line.name = "ShipRow_%d" % id
		line.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
		var label: Label = _label(str(s.get("name", "")))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		for t: int in TEAM_LETTERS.size():
			var b: Button = _button(
				"Team_%d" % t,
				tr("lobby.team") % TEAM_LETTERS[t],
				func() -> void: _ctx.intents.set_team(id, t)
			)
			b.toggle_mode = true
			b.set_pressed_no_signal(_ctx.crew.team_of(id) == t)
			b.disabled = not open
			line.add_child(b)
		_ships.add_child(line)
	_add_ship.visible = _ctx.crew.can_add_ship()
	_add_ship.text = tr("lobby.add_ship")
	(_headings["lobby.ships"] as Label).visible = teams or _add_ship.visible


## Shows the session's set: the summary, the pressed preset, every toggle's text and value,
## and whether the host can still change them.
func refresh() -> void:
	var toggles: DataToggles = _ctx.crew.toggles
	var editable: bool = can_edit_toggles()
	summary.text = summary_text()
	setup_button.text = tr("lobby.setup")
	if _sheet == null:
		return
	_preset_name.text = preset_label(toggles)
	for preset: String in _preset_buttons:
		var b: Button = _preset_buttons[preset]
		b.text = tr("lobby.preset_" + preset)
		b.button_pressed = preset == toggles.preset and not toggles.is_custom()
		b.disabled = not editable
	_toggle_note.text = tr("lobby.toggles_locked") if toggles_locked() else ""
	_toggle_note.visible = _toggle_note.text != ""
	for def: DataToggleDef in DataToggles.def().toggles:
		var toggle: Control = _toggle_rows.get_node("Toggle_" + String(def.id))
		toggle.get_node("Line/Name").text = tr("lobby.toggle." + String(def.id))
		toggle.get_node("Desc").text = tr("lobby.toggle.%s.desc" % def.id)
		var value: OptionButton = toggle.get_node("Line/Value")
		value.clear()
		var summary_kind: bool = def.kind == DataToggleDef.Kind.SUMMARY
		var names: Array[String] = ["off", "on"]
		if summary_kind:
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
