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
## A window shorter than this (a phone held sideways) puts the ships in two columns.
const SHORT_SHEET: float = 500.0
## The sheet's tabs, in order.
const TAB_KEYS: Array[String] = ["lobby.mode_title", "lobby.ships", "lobby.difficulty_title"]

## The setup row: the Game setup button (host) and the summary line.
var row: HBoxContainer
var setup_button: Button
var summary: Label
var _ctx: StationContext
var _sheet: AcceptDialog
var _tabs: TabContainer
var _mode: ModePanel
## The difficulty tab's heading over the data shortcuts.
var _data_heading: Label
var _ships: GridContainer
var _add_ship: Button
var _preset_buttons: Dictionary = {}
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


## Whether a run has started on any ship: the toggles are locked from then on.
func toggles_locked() -> bool:
	for state: Dictionary in _ctx.crew.lobby.values():
		if bool(state.get("started", false)):
			return true
	return false


## Only the host changes the toggles, and only before a run starts.
func can_edit_toggles() -> bool:
	return _ctx.crew.host and not toggles_locked()


## The one-line summary everyone sees, in short words so it is never cut (#37 C1): the
## mode's short name and the difficulty, with the number of toggles changed from its preset
## ("Teams · Easy", "Co-op · Normal +2"), then the host's options that are on (#40 D1, D2)
## and the run modifier (gp-11): "Co-op · Easy · Bots fill · Ion storm".
func summary_text() -> String:
	var mode: String = tr("lobby.short." + _ctx.crew.mode())
	var toggles: DataToggles = _ctx.crew.toggles
	var level: String = tr("lobby.preset_" + toggles.preset)
	var changed: int = changed_count(toggles)
	if changed > 0:
		level = tr("lobby.preset_changed") % [level, changed]
	var parts: PackedStringArray = [tr("lobby.summary") % [mode, level]]
	for id: String in ["drop_pause", "fill_bots"]:
		if bool(_ctx.crew.fleet.get(id, false)):
			parts.append(tr("lobby.short." + id))
	var modifier: String = ModePanel.modifier_name(str(_ctx.crew.fleet.get("modifier", "")))
	if modifier != "":
		parts.append(modifier)
	return " · ".join(parts)


## How many toggles differ from the set's preset.
static func changed_count(toggles: DataToggles) -> int:
	var base: DataToggles = DataToggles.of_preset(toggles.preset)
	var n: int = 0
	for id: StringName in DataToggles.ids():
		if toggles.value(id) != base.value(id):
			n += 1
	return n


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


## The Game setup sheet, added to `host`: three tabs, the mode, the ships and their teams
## (shown only when there are teams or room for another ship), and the difficulty with its
## data shortcuts. Each tab fits a phone held sideways; the shortcut list and the mode tab
## (with the host's options and the run modifier) scroll.
func add_dialogs(host: Node) -> void:
	_sheet = AcceptDialog.new()
	_sheet.name = "SetupDialog"
	_sheet.title = tr("lobby.setup")
	_sheet.ok_button_text = tr("lobby.done")
	host.add_child(_sheet)
	_tabs = TabContainer.new()
	_tabs.name = "SetupTabs"
	# The tabs are touch targets: at least UiTheme.TOUCH_PRIMARY px tall (theme tabs are ~34).
	for style: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var sb: StyleBox = UiTheme.box("panel", "line_strong", 12, 15)
		if style != "tab_unselected":
			sb = UiTheme.box(
				"panel_focus", "accent" if style == "tab_selected" else "line_strong", 12, 15
			)
		_tabs.add_theme_stylebox_override(style, sb)
	_sheet.add_child(_tabs)
	var mode_tab: VBoxContainer = _tab("ModeTab")
	# The mode, the host's options and the run modifier scroll on a phone held sideways.
	var mode_scroll: ScrollContainer = ScrollContainer.new()
	mode_scroll.name = "ModeScroll"
	mode_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mode_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mode_tab.add_child(mode_scroll)
	_mode = ModePanel.new()
	_mode.setup(_ctx)
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_scroll.add_child(_mode)
	var ships_tab: VBoxContainer = _tab("ShipsTab")
	_ships = GridContainer.new()
	_ships.name = "SetupShips"
	_ships.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP * 3)
	_ships.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	ships_tab.add_child(_ships)
	_add_ship = _button("AddShip", tr("lobby.add_ship"), add_ship_requested.emit)
	_add_ship.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ships_tab.add_child(_add_ship)
	var level_tab: VBoxContainer = _tab("DifficultyTab")
	var presets: HBoxContainer = HBoxContainer.new()
	presets.name = "Presets"
	presets.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	level_tab.add_child(presets)
	for preset: String in DataToggles.PRESETS:
		var b: Button = _button("Preset_" + preset, "", _choose_preset.bind(preset))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_preset_buttons[preset] = b
		presets.add_child(b)
	_toggle_note = _label("", "DimLabel")
	_toggle_note.name = "ToggleNote"
	level_tab.add_child(_toggle_note)
	_data_heading = _label(tr("lobby.data"), "HeadingLabel")
	_data_heading.name = "Heading_data"
	level_tab.add_child(_data_heading)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ToggleScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_tab.add_child(scroll)
	_toggle_rows = VBoxContainer.new()
	_toggle_rows.name = "Toggles"
	_toggle_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_toggle_rows)
	for def: DataToggleDef in DataToggles.def().toggles:
		_toggle_rows.add_child(_toggle_row(def))
	_title_tabs()


## A tab of the sheet: a column with the touch gap between its rows.
func _tab(node_name: String) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.name = node_name
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_tabs.add_child(col)
	return col


func _title_tabs() -> void:
	for i: int in TAB_KEYS.size():
		_tabs.set_tab_title(i, tr(TAB_KEYS[i]))


## A language switch: the sheet's title and button (the rest follows the next refresh).
func retranslate() -> void:
	_title_tabs()
	_sheet.title = tr("lobby.setup")
	_sheet.ok_button_text = tr("lobby.done")
	setup_button.text = tr("lobby.setup")
	_data_heading.text = tr("lobby.data")
	_add_ship.text = tr("lobby.add_ship")


## The summary is never cut (its words are short): on a short screen's one row it keeps its
## whole width and the buttons share the rest; elsewhere it takes the row and wraps.
func fit_summary(short: bool) -> void:
	summary.autowrap_mode = TextServer.AUTOWRAP_OFF if short else TextServer.AUTOWRAP_WORD_SMART
	summary.size_flags_horizontal = (Control.SIZE_FILL if short else Control.SIZE_EXPAND_FILL)


## Opens the sheet (the host's Game setup button): on a phone it fills the safe area, so
## nothing of the lobby shows around it; elsewhere a centred card.
func open() -> void:
	var view: Vector2 = row.get_viewport_rect().size
	var narrow: bool = view.x < NARROW_SHEET
	var short: bool = view.y < SHORT_SHEET
	_mode.fit(narrow)
	_ships.columns = 2 if short and not narrow else 1
	refresh_mode()
	_tabs.current_tab = 0
	if PhoneSheet.is_phone(row):
		var m: Vector4 = SafeArea.margins(row)
		var bottom: float = maxf(m.w, SafeArea.tap_band(row))
		var title: int = _sheet.get_theme_constant("title_height", "Window")
		var at: Vector2i = Vector2i(int(m.x), int(m.y) + title)
		var size: Vector2i = Vector2i(int(view.x - m.x - m.z), int(view.y - m.y - bottom) - title)
		_sheet.popup(Rect2i(at, size))
	else:
		_sheet.popup_centered(Vector2i(mini(int(view.x * 0.9), 600), mini(int(view.y * 0.85), 560)))


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
	_title_tabs()


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
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_tabs.set_tab_hidden(1, not (teams or _add_ship.visible))


## Shows the session's set: the summary, the pressed preset, every toggle's text and value,
## and whether the host can still change them.
func refresh() -> void:
	var toggles: DataToggles = _ctx.crew.toggles
	var editable: bool = can_edit_toggles()
	summary.text = summary_text()
	setup_button.text = tr("lobby.setup")
	if _sheet == null:
		return
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
