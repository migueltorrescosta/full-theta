class_name LobbyScreen
extends Control
## The lobby as the station grid (D216, FT-NET-015, FT-NET-017, FT-NET-032, FT-STN-015,
## FT-JNT-006): the six crew stations as cells, 3 columns by 2 rows in landscape and 2 by
## 3 in portrait on every device, each with its name, its role description, the names of
## the crewmates who picked it and a border in its load colour; a one-line legend under
## the grid. Tapping cells multi-selects up to two stations (two make the joint view of
## that pair) and the pick goes to the server on each tap; with two picked the other
## cells grey out; tapping a picked cell deselects it. Under the grid the selection's
## name and summary show. Captain and Viewer are two buttons below (choosing one clears
## the station picks and vice versa). The host's difficulty is one line with Customise,
## which opens a dialog of the data-shortcut toggles (FT-PAIR-017, FT-STN-016; read-only
## for the others); Start is the confirm. Nothing scrolls: the whole lobby fits the
## screen. Picks go to the server (ShipIntents.pick); the screen shows what the events
## say. The host's lobby also has a "How to join" dialog (FT-NET-013): the browser URL
## with a QR code and the desktop address.

## The player wants out of the session (Main menu): the shell leaves, and the host's
## menu also stops its server.
signal menu_requested

## The load tags, in legend order, and the colour word the legend names them with.
const LOAD_TAGS: Array[String] = ["intense", "busy", "light"]
## The crew stations in grid order (row by row in landscape).
const GRID_STATIONS: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
## A player picks at most this many stations (a joint view covers two).
const MAX_STATIONS: int = 2
const LANDSCAPE_COLUMNS: int = 3
const PORTRAIT_COLUMNS: int = 2
const CAPTAIN: String = "captain"
const VIEWER: String = "viewer"
## The dev entry holding every station, offered by --dev-all-stations only.
const DEV_ALL: String = "all"
## The crew changes the lobby depends on.
const KINDS: Array[StringName] = [&"catalogue", &"lobby", &"picked", &"toggles"]

var ctx: StationContext
## The ship whose stations are shown.
var ship: int = -1

var _ships: HBoxContainer
var _grid: GridContainer
var _coverage: Label
var _legend: HBoxContainer
var _summary_name: Label
var _summary_role: Label
var _start: Button
var _title: Label
var _leave: Button
var _menu: Button
var _body: Control
var _seat_row: HBoxContainer
var _captain: Button
var _viewer: Button
var _dev_all: Button
var _join_button: Button
var _join_dialog: AcceptDialog
var _join_panel: VBoxContainer
## Difficulty (strand G's toggles): the one-line summary and its dialog.
var _difficulty: Label
var _customise: Button
var _dialog: AcceptDialog
var _preset_buttons: Dictionary = {}
var _preset_name: Label
var _toggle_rows: VBoxContainer
var _toggle_note: Label
## The host's saved set was sent to the server for this connection.
var _pushed: bool = false
## After "Back to ships": no ship is chosen until the player picks one.
var _browsing: bool = false


func setup(context: StationContext) -> void:
	ctx = context
	_build()
	ctx.crew.changed.connect(_on_crew_changed)
	resized.connect(_apply_columns)
	refresh()


## Rebuilds every list from ctx.crew.
func refresh() -> void:
	var ships: Array = ctx.crew.catalogue.get("ships", [])
	if _browsing:
		ship = -1
	elif ship < 0:
		ship = ctx.crew.ship if ctx.crew.ship >= 0 else (int(ships[0]["id"]) if ships else -1)
	_clear(_ships)
	for s: Dictionary in ships:
		var b: Button = Button.new()
		b.text = str(s.get("name", ""))
		b.toggle_mode = true
		b.button_pressed = int(s["id"]) == ship
		b.pressed.connect(_choose_ship.bind(int(s["id"])))
		_ships.add_child(b)
	var state: Dictionary = ctx.crew.lobby.get(ship, {})
	_coverage.text = coverage_text(state)
	_build_legend()
	_refresh_grid()
	_refresh_seats()
	_refresh_summary()
	_start.disabled = not (
		ctx.crew.is_crew() and ctx.crew.ship == ship and bool(state.get("ready", false))
	)
	_start.visible = not _browsing and not bool(state.get("started", false))
	_body.visible = not _browsing
	_leave.visible = not _browsing
	_refresh_data()
	if _browsing:
		_summary_name.text = tr("lobby.pick_ship")
		_summary_role.text = ""
		_body.visible = false


## "Easy", or "Easy (custom)" for a set with a toggle changed (FT-PAIR-017, D92).
static func preset_label(toggles: DataToggles) -> String:
	var name: String = TranslationServer.translate("lobby.preset_" + toggles.preset)
	if toggles.is_custom():
		return TranslationServer.translate("lobby.preset_custom") % name
	return name


## Whether a run has started on any ship: the toggles are locked from then on.
func toggles_locked() -> bool:
	for state: Dictionary in ctx.crew.lobby.values():
		if bool(state.get("started", false)):
			return true
	return false


## Only the host changes the toggles, and only before a run starts.
func can_edit_toggles() -> bool:
	return ctx.crew.host and not toggles_locked()


## "Crew 2/3 · uncovered: Science, Comms" (FT-NET-021).
func coverage_text(state: Dictionary) -> String:
	if state.is_empty():
		return ""
	var crew: String = tr("lobby.crew") % [int(state.get("crew", 0)), int(state.get("min_crew", 3))]
	var uncovered: Array = state.get("uncovered", [])
	if uncovered.is_empty():
		return "%s · %s" % [crew, tr("lobby.covered")]
	var names: PackedStringArray = []
	for s: Variant in uncovered:
		names.append(tr("station." + str(s)))
	return "%s · %s" % [crew, tr("lobby.uncovered") % ", ".join(names)]


## The hint of a joint view naming the pair it makes solo (FT-JNT-006); "" otherwise.
static func joint_hint(def: Dictionary) -> String:
	var st: Array = def.get("stations", [])
	if st.size() != 2:
		return ""
	return (
		TranslationServer.translate("lobby.joint_pair")
		% [
			TranslationServer.translate("station." + str(st[0])),
			TranslationServer.translate("station." + str(st[1])),
		]
	)


## The colour of a seat's load tag (intense, busy, light); the normal text colour for
## no tag (the Viewer).
static func load_color(tag: String) -> Color:
	return Palette.color("load_" + tag if tag in LOAD_TAGS else "text")


## The columns of the grid for a lobby of this size: 3 in landscape, 2 in portrait.
static func columns_for(size: Vector2) -> int:
	return PORTRAIT_COLUMNS if size.x < size.y else LANDSCAPE_COLUMNS


## The stations the player has picked on the shown ship (none for Captain, Viewer and
## the dev entry).
func selected_stations() -> Array[String]:
	var out: Array[String] = []
	if ctx.crew.ship != ship or ctx.crew.entry in [DEV_ALL, ""]:
		return out
	for st: Variant in ctx.crew.stations():
		out.append(str(st))
	return out


## The catalogue entry covering exactly these stations: the station itself for one, the
## joint view of the pair for two; "" when there is none.
func entry_for(stations: Array[String]) -> String:
	for def: Dictionary in ctx.crew.catalogue.get("entries", []):
		var st: Array = def.get("stations", [])
		if st.size() != stations.size() or stations.is_empty():
			continue
		var same: bool = true
		for s: String in stations:
			same = same and s in st
		if same:
			return str(def["id"])
	return ""


## The names of the crewmates who picked a station (a joint view covers both of its
## stations), from the `lobby` event's seats.
func crew_at(station: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for seat: Variant in ctx.crew.lobby.get(ship, {}).get("seats", []):
		var covered: Array = ctx.crew.def_of(str(seat["entry"])).get("stations", [])
		if station in covered:
			names.append(str(seat["name"]))
	return names


## A tap on a station cell: adds it to the picks (up to two), or takes it out; the pick
## goes to the server at once.
func tap_station(id: String) -> void:
	var picks: Array[String] = selected_stations()
	if id in picks:
		picks.erase(id)
	elif picks.size() < MAX_STATIONS:
		picks.append(id)
	else:
		refresh()
		return
	if picks.is_empty():
		ctx.intents.release_pick()
	else:
		var entry: String = entry_for(picks)
		if entry != "":
			ctx.intents.pick(ship, entry)
	refresh()


## A tap on Captain, Viewer or the dev entry: picks it, or gives it up when it is the
## pick.
func tap_seat(id: String) -> void:
	if ctx.crew.ship == ship and ctx.crew.entry == id:
		ctx.intents.release_pick()
	else:
		ctx.intents.pick(ship, id)
	refresh()


## The title and summary under the grid for the current pick: a station's name and
## role, or a joint view's name, its pair and its role.
func selection_text() -> Array[String]:
	var entry: String = ctx.crew.entry if ctx.crew.ship == ship else ""
	if entry == "":
		return [tr("lobby.no_pick"), ""]
	var name: String = tr("station." + entry)
	var pair: String = joint_hint(ctx.crew.def_of(entry))
	if pair != "":
		name += " (%s)" % pair
	return [name, tr("role." + entry)]


## The one-line legend under the grid: "Red: intense · Yellow: busy · Green: light", each
## part in its colour (D187).
func _build_legend() -> void:
	_clear(_legend)
	for i: int in LOAD_TAGS.size():
		if i > 0:
			_legend.add_child(_label("·", "SmallLabel"))
		var tag: String = LOAD_TAGS[i]
		var item: Label = _label(tr("lobby.legend_" + tag), "SmallLabel")
		item.name = "Legend_" + tag
		item.add_theme_color_override("font_color", load_color(tag))
		_legend.add_child(item)


static func _label(text: String, variation: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _refresh_grid() -> void:
	_clear(_grid)
	var picks: Array[String] = selected_stations()
	var full: bool = picks.size() >= MAX_STATIONS
	# The dev entry holds every station: all six cells show as selected and locked; a tap
	# on one leaves it for that station alone.
	var dev: bool = ctx.crew.ship == ship and ctx.crew.entry == DEV_ALL
	for id: String in GRID_STATIONS:
		var def: Dictionary = ctx.crew.def_of(id)
		if def.is_empty():
			continue
		var cell: Button = _cell(id, str(def.get("load_tag", "")))
		cell.set_pressed_no_signal(dev or id in picks)
		cell.disabled = full and not id in picks
		cell.modulate = Color(1, 1, 1, 0.45) if cell.disabled else Color.WHITE
		_grid.add_child(cell)
	_apply_columns()


## A station cell: a toggle button holding the name, the role and the crew's names,
## centred; its minimum size follows the text so a small screen shows when it doesn't fit.
func _cell(id: String, tag: String) -> Button:
	var b: Button = Button.new()
	b.name = "Entry_" + id
	b.toggle_mode = true
	b.theme_type_variation = "LoadCell_" + (tag if tag in LOAD_TAGS else "none")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.pressed.connect(tap_station.bind(id))
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = UiTheme.CELL_PAD
	box.offset_top = UiTheme.CELL_PAD
	box.offset_right = -UiTheme.CELL_PAD
	box.offset_bottom = -UiTheme.CELL_PAD
	box.add_theme_constant_override("separation", 2)
	b.add_child(box)
	box.add_child(_cell_label("Name", tr("station." + id), "HeadingLabel"))
	box.add_child(_cell_label("Role", tr("role." + id), "CaptionLabel"))
	var crew: PackedStringArray = crew_at(id)
	if not crew.is_empty():
		box.add_child(_cell_label("Crew", ", ".join(crew), "CrewLabel"))
	box.minimum_size_changed.connect(_fit_cell.bind(b, box))
	_fit_cell.call_deferred(b, box)
	return b


func _cell_label(node_name: String, text: String, variation: String) -> Label:
	var l: Label = _label(text, variation)
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _fit_cell(cell: Button, box: Control) -> void:
	if is_instance_valid(cell) and is_instance_valid(box):
		var pad: float = 2.0 * UiTheme.CELL_PAD
		cell.custom_minimum_size = Vector2(0.0, box.get_combined_minimum_size().y + pad)


func _apply_columns() -> void:
	if _grid != null:
		_grid.columns = columns_for(size)


## The Captain, Viewer and dev buttons: the pick's one is pressed; Captain is greyed out
## while another player holds it.
func _refresh_seats() -> void:
	var mine: String = ctx.crew.entry if ctx.crew.ship == ship else ""
	for pair: Array in [[_captain, CAPTAIN], [_viewer, VIEWER], [_dev_all, DEV_ALL]]:
		var b: Button = pair[0]
		b.set_pressed_no_signal(mine == pair[1])
		b.text = tr("station." + pair[1])
	_captain.disabled = ctx.crew.captain_seated(ship) and mine != CAPTAIN
	_dev_all.visible = not ctx.crew.def_of(DEV_ALL).is_empty()


func _refresh_summary() -> void:
	var text: Array[String] = selection_text()
	_summary_name.text = text[0]
	_summary_role.text = text[1]


func _choose_ship(id: int) -> void:
	_browsing = false
	ship = id
	refresh()


## "Back to ships": gives up the seat (the server answers with a `picked` event of no
## ship) and shows the ship list alone until a ship is chosen.
func _back_to_ships() -> void:
	ctx.intents.release_pick()
	_browsing = true
	refresh()


## The browser URL of the host's web stations: HTTP listens one port below the
## WebSocket port (D108, docs/launch.md).
static func join_url(bind: String, ws_port: int) -> String:
	return "http://%s:%d/?join=1" % [bind, ws_port - 1]


## True for an address only this computer can reach.
static func is_local_only(bind: String) -> bool:
	return bind.begins_with("127.") or bind == "::1" or bind == "localhost"


## The host's "How to join" content: URL and QR code, the desktop address, or why nobody
## else can join.
func _build_join_panel(parent: Node) -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "JoinPanel"
	parent.add_child(panel)
	_join_panel = panel
	if is_local_only(ctx.host_bind):
		var local: Label = _label(tr("lobby.join_local") % ctx.host_bind)
		local.name = "JoinLocal"
		local.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		local.custom_minimum_size = Vector2(320, 0)
		panel.add_child(local)
		return
	var url: String = join_url(ctx.host_bind, ctx.host_port)
	var browser: Label = _label(tr("lobby.join_browser") % url)
	browser.name = "JoinUrl"
	panel.add_child(browser)
	var desktop: Label = _label(tr("lobby.join_desktop") % ctx.host_bind)
	desktop.name = "JoinDesktop"
	panel.add_child(desktop)
	var qr: QrView = QrView.new()
	qr.name = "JoinQr"
	qr.set_text(url)
	panel.add_child(qr)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	# Nothing scrolls (D216): the grid takes the height the rows around it leave.
	var outer: VBoxContainer = VBoxContainer.new()
	outer.name = "Layout"
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)
	var head: HBoxContainer = HBoxContainer.new()
	outer.add_child(head)
	_title = _label(tr("lobby.title"), "HeadingLabel")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_join_button = _button("JoinButton", tr("lobby.join_title"), _open_join)
	head.add_child(_join_button)
	_join_button.visible = ctx.host_bind != ""
	_menu = _button("MainMenu", tr("lobby.menu"), menu_requested.emit)
	head.add_child(_menu)
	var ship_row: HBoxContainer = HBoxContainer.new()
	outer.add_child(ship_row)
	_ships = HBoxContainer.new()
	_ships.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_row.add_child(_ships)
	_leave = _button("BackToShips", tr("lobby.leave_pick"), _back_to_ships)
	ship_row.add_child(_leave)
	_coverage = _label("", "DimLabel")
	_coverage.name = "Coverage"
	outer.add_child(_coverage)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_body)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_grid)
	_legend = HBoxContainer.new()
	_legend.name = "Legend"
	_legend.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(_legend)
	_build_summary(_body)
	_build_seats(_body)
	_build_difficulty_row(_body)
	_start = _button("Start", tr("lobby.start"), func() -> void: ctx.intents.start())
	_start.theme_type_variation = "TouchButton"
	outer.add_child(_start)
	_build_dialogs()


func _build_summary(parent: Container) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Summary"
	parent.add_child(box)
	_summary_name = _label("", "HeadingLabel")
	_summary_name.name = "SummaryName"
	_summary_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary_name)
	_summary_role = _label("", "DimLabel")
	_summary_role.name = "SummaryRole"
	_summary_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary_role)


func _build_seats(parent: Container) -> void:
	_seat_row = HBoxContainer.new()
	_seat_row.name = "Seats"
	parent.add_child(_seat_row)
	_captain = _seat_button(CAPTAIN)
	_viewer = _seat_button(VIEWER)
	_dev_all = _seat_button(DEV_ALL)


func _seat_button(id: String) -> Button:
	var b: Button = _button("Entry_" + id, "", tap_seat.bind(id))
	b.toggle_mode = true
	b.theme_type_variation = "TouchButton"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seat_row.add_child(b)
	return b


func _build_difficulty_row(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Difficulty"
	parent.add_child(row)
	_difficulty = _label("")
	_difficulty.name = "DifficultyLine"
	_difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_difficulty)
	_customise = _button("Customise", tr("lobby.customise"), _open_difficulty)
	row.add_child(_customise)


func _button(node_name: String, text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.pressed.connect(handler)
	return b


## The dialogs: the difficulty toggles and, on the host, how to join.
func _build_dialogs() -> void:
	_dialog = AcceptDialog.new()
	_dialog.name = "DifficultyDialog"
	_dialog.title = tr("lobby.data")
	_dialog.ok_button_text = tr("lobby.done")
	add_child(_dialog)
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	_dialog.add_child(col)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Presets"
	col.add_child(row)
	for preset: String in DataToggles.PRESETS:
		var b: Button = _button("Preset_" + preset, "", _choose_preset.bind(preset))
		b.toggle_mode = true
		_preset_buttons[preset] = b
		row.add_child(b)
	_preset_name = _label("", "DimLabel")
	_preset_name.name = "PresetName"
	row.add_child(_preset_name)
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
	_join_dialog = AcceptDialog.new()
	_join_dialog.name = "JoinDialog"
	_join_dialog.title = tr("lobby.join_title")
	_join_dialog.ok_button_text = tr("lobby.done")
	add_child(_join_dialog)
	if ctx.host_bind != "":
		_build_join_panel(_join_dialog)


func _open_difficulty() -> void:
	_dialog.popup_centered_clamped(Vector2i(520, 480), 0.9)


func _open_join() -> void:
	_join_dialog.popup_centered_clamped(Vector2i(360, 320), 0.9)


## One toggle: its name, its value and a one-line description naming both stations, and
## for the two Comms toggles that it arrives in M3 (D190).
func _toggle_row(def: DataToggleDef) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.name = "Toggle_" + String(def.id)
	var line: HBoxContainer = HBoxContainer.new()
	line.name = "Line"
	row.add_child(line)
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
	row.add_child(desc)
	return row


## Shows the session's set: the difficulty line, the pressed preset, every toggle's text
## and value, and whether the host can still change them.
func _refresh_data() -> void:
	var toggles: DataToggles = ctx.crew.toggles
	var editable: bool = can_edit_toggles()
	_difficulty.text = tr("lobby.difficulty") % preset_label(toggles)
	_customise.text = tr("lobby.customise")
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
	elif not ctx.crew.host:
		note = tr("lobby.toggles_host_only")
	_toggle_note.text = note
	for def: DataToggleDef in DataToggles.def().toggles:
		var row: Control = _toggle_rows.get_node("Toggle_" + String(def.id))
		var text: String = tr("lobby.toggle." + String(def.id))
		if def.arrives_m3:
			text += " (%s)" % tr("lobby.arrives_m3")
		row.get_node("Line/Name").text = text
		row.get_node("Desc").text = tr("lobby.toggle.%s.desc" % def.id)
		var value: OptionButton = row.get_node("Line/Value")
		value.clear()
		var choices: Array = [2, 1, 0] if def.kind == DataToggleDef.Kind.SUMMARY else [1, 0]
		for v: int in choices:
			var key: String = (
				"lobby.v_"
				+ (
					["absent", "banded", "exact"][v]
					if def.kind == DataToggleDef.Kind.SUMMARY
					else ["off", "on"][v]
				)
			)
			value.add_item(tr(key), v)
		value.select(value.get_item_index(toggles.value(def.id)))
		value.disabled = not editable


func _choose_preset(preset: String) -> void:
	if can_edit_toggles():
		_apply_toggles(DataToggles.of_preset(preset))
	else:
		_refresh_data()


func _set_value(id: StringName, v: int) -> void:
	if can_edit_toggles():
		_apply_toggles(ctx.crew.toggles.with_value(id, v))
	else:
		_refresh_data()


## Sends the host's choice and remembers it for the next lobby (FT-STN-016).
func _apply_toggles(toggles: DataToggles) -> void:
	var code: String = toggles.encode()
	ctx.settings.host_toggles = code
	ctx.settings.save()
	ctx.intents.set_toggles(code)


## The host's lobby starts from its saved set: sent once per connection, before any run.
func _push_saved_toggles() -> void:
	if _pushed or not ctx.crew.host or toggles_locked():
		return
	_pushed = true
	if ctx.settings.host_toggles != ctx.crew.toggles.encode():
		ctx.intents.set_toggles(ctx.settings.host_toggles)


static func _clear(box: Container) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


## A language switch retranslates the whole lobby.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and ctx != null:
		_title.text = tr("lobby.title")
		_start.text = tr("lobby.start")
		_leave.text = tr("lobby.leave_pick")
		_menu.text = tr("lobby.menu")
		_join_button.text = tr("lobby.join_title")
		_join_dialog.title = tr("lobby.join_title")
		_join_dialog.ok_button_text = tr("lobby.done")
		_dialog.ok_button_text = tr("lobby.done")
		if _join_panel != null:
			_join_dialog.remove_child(_join_panel)
			_join_panel.queue_free()
			_build_join_panel(_join_dialog)
		refresh()


func _on_crew_changed(what: StringName) -> void:
	if what == &"lobby":
		_push_saved_toggles()
	if what in KINDS or what == &"toggles":
		refresh()
