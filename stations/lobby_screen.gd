class_name LobbyScreen
extends Control
## The lobby as the station grid (D216, FT-NET-015, FT-NET-017, FT-NET-032, FT-STN-015,
## FT-JNT-006): the six crew stations as cells, 3 columns by 2 rows in landscape and 2 by
## 3 in portrait on every device, each with its name, its role description, the names of
## the crewmates who picked it and a border in its load colour; a one-line legend under
## the grid (compact, D257: about half the old height, a one-line role summary, no Take
## button, the cell takes or leaves the seat). Tapping cells multi-selects up to two
## stations (two make the joint view of that pair) and the pick goes to the server on
## each tap; with two picked the other cells grey out; tapping a picked cell deselects
## it. Under the grid the selection's
## name and summary show. Captain and Viewer are two buttons below (choosing one clears
## the station picks and vice versa). The host's difficulty is one line with Customise,
## which opens a dialog of the data-shortcut toggles (FT-PAIR-017, FT-STN-016; read-only
## for the others); Start is the confirm. Nothing scrolls: the whole lobby fits the
## screen. Picks go to the server (ShipIntents.pick); the screen shows what the events
## say. The host's lobby also has a "How to join" dialog (FT-NET-013): the browser URL
## with a QR code and the desktop address.
##
## Multi-ship sessions (#11, M4-Q3, M4-Q4, M4-Q6): the ship row lists the `fleet` ships
## (with their team in TEAMS and HOLDOUT) and a New ship button while there is room (any
## player, up to 6); a crew puts its ship on team A or B; the host's mode and options sit
## behind the Mode button (read-only for the others); Start is pressed per ship and then
## names the ships still to press it, since the universe starts all together.
##
## Phones (#28): in landscape (a short window) the ship row stays its own row and Start,
## Mode and the difficulty join the seat row; every tap target is at least TOUCH_PRIMARY
## px tall with TOUCH_GAP px between them.

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
## A window shorter than this (a phone in landscape) merges the header rows and puts the
## difficulty line on the seat row, so Start stays on screen.
const SHORT_HEIGHT: float = 500.0
## A window narrower than this (a phone upright) shortens the mode button to the mode's name.
const NARROW_WIDTH: float = 700.0
## Cell padding and the grid gap, in px at 100 % UI scale (a cell stays >= TOUCH_MIN tall).
const CELL_INSET: int = 5
const GRID_GAP: int = 4
const PORTRAIT_COLUMNS: int = 2
const CAPTAIN: String = "captain"
const VIEWER: String = "viewer"
## The dev entry holding every station, offered by --dev-all-stations only.
const DEV_ALL: String = "all"
## The crew changes the lobby depends on.
const KINDS: Array[StringName] = [&"catalogue", &"lobby", &"picked", &"toggles", &"fleet"]
## The names a new ship takes, the first one not in use (M4-Q3).
const NEW_SHIP_NAMES: Array[String] = [
	"Kestrel", "Heron", "Osprey", "Merlin", "Petrel", "Tern", "Curlew", "Swift"
]
## The team letters (team 0 is A).
const TEAM_LETTERS: Array[String] = ["A", "B"]
## Phone tap targets (#28): primary targets at least this tall, this far apart.
const PHONE_TARGET: int = UiTheme.TOUCH_PRIMARY
const PHONE_GAP: int = UiTheme.TOUCH_GAP

var ctx: StationContext
## The ship whose stations are shown.
var ship: int = -1

## The ship row: a button per ship, then New ship, the team buttons and Back to ships; it
## wraps on a narrow screen.
var _ships: HFlowContainer
var _new_ship: Button
var _teams: HBoxContainer
var _team_buttons: Array[Button] = []
var _mode_button: Button
var _mode_dialog: ModeDialog
## The name of the ship this player just added: chosen once the `fleet` event lists it.
var _added: String = ""
## Why the server refused the last request, shown under the grid until the next change.
var _refusal: String = ""
var _head: HBoxContainer
var _outer: VBoxContainer
var _margin: MarginContainer
var _diff_row: HBoxContainer
var _short: bool = false
## The lobby is on a phone (LayoutMode PHONE): cells and buttons take phone sizes.
var _phone: bool = false
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
## Difficulty (toggles): the one-line summary and its dialog.
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
## The stations tapped since the server last answered a pick: a second tap before the
## answer to the first must still add to it. Empty of meaning while `_tapped` is false.
var _local: Array[String] = []
var _tapped: bool = false
## The ship ids and station ids whose buttons exist; a refresh rebuilds only when they change.
var _ship_ids: Array = []
var _cell_ids: Array[String] = []


func setup(context: StationContext) -> void:
	ctx = context
	_build()
	ctx.crew.changed.connect(_on_crew_changed)
	ctx.crew.toast.connect(_on_refused)
	resized.connect(_apply_columns)
	refresh()


## Rebuilds every list from ctx.crew.
func refresh() -> void:
	var ships: Array = ctx.crew.fleet_ships()
	var ship_ids: Array = ships.map(func(s: Dictionary) -> Variant: return int(s["ship"]))
	if _added != "":
		for s: Dictionary in ships:
			if str(s.get("name", "")) == _added:
				_added = ""
				_browsing = false
				ship = int(s["ship"])
	if _browsing:
		ship = -1
	elif ship < 0 or not ship in ship_ids:
		ship = ctx.crew.ship if ctx.crew.ship in ship_ids else (ship_ids[0] if ships else -1)
	if ship_ids != _ship_ids:
		_ship_ids = ship_ids
		for c: Node in _ships.get_children():
			if str(c.name).begins_with("Ship_"):
				_ships.remove_child(c)
				c.queue_free()
		for i: int in ships.size():
			var b: Button = Button.new()
			b.name = "Ship_%d" % int(ships[i]["ship"])
			b.toggle_mode = true
			b.pressed.connect(_choose_ship.bind(int(ships[i]["ship"])))
			_ships.add_child(b)
			_ships.move_child(b, i)
	for i: int in ships.size():
		var b: Button = _ships.get_child(i) as Button
		b.text = ship_label(ships[i])
		b.set_pressed_no_signal(int(ships[i]["ship"]) == ship)
	var state: Dictionary = ctx.crew.ship_state(ship)
	_coverage.text = coverage_text(state)
	_build_legend()
	_refresh_grid()
	_refresh_seats()
	_refresh_summary()
	_refresh_fleet()
	_start.disabled = not (
		ctx.crew.is_crew() and ctx.crew.ship == ship and bool(state.get("ready", false))
	)
	_start.text = tr("lobby.start")
	if ctx.crew.waiting_for_others(ship):
		_start.disabled = true
		_start.text = tr("lobby.waiting") % ", ".join(ctx.crew.waiting_names())
	_start.visible = (
		not _browsing
		and (not bool(state.get("started", false)) or ctx.crew.waiting_for_others(ship))
	)
	_body.visible = not _browsing
	_leave.visible = not _browsing
	_refresh_data()
	if _refusal != "":
		_summary_role.text = _refusal
	if _browsing:
		_summary_name.text = tr("lobby.pick_ship")
		_summary_role.text = ""
		_body.visible = false


## A ship button's text: its name, and its team in TEAMS and HOLDOUT ("Heron (B)").
func ship_label(row: Dictionary) -> String:
	var text: String = str(row.get("name", ""))
	if ctx.crew.has_teams():
		text = tr("lobby.ship_team") % [text, TEAM_LETTERS[clampi(int(row.get("team", 0)), 0, 1)]]
	return text


## The mode button: "Mode: Teams (First to finish)" (M4-Q6); on a narrow or short screen
## just the mode's name.
func mode_text() -> String:
	var name: String = tr("mode." + ctx.crew.mode())
	if _short or size.x < NARROW_WIDTH:
		return name
	if ctx.crew.mode() == "teams":
		name = (
			tr("lobby.mode_rule")
			% [name, tr("mode.win." + str(ctx.crew.fleet.get("team_win", "")))]
		)
	return tr("lobby.mode") % name


## The first name of NEW_SHIP_NAMES no ship has, or "Ship 7" past the list.
func next_ship_name() -> String:
	var used: Array = ctx.crew.fleet_ships().map(func(s: Dictionary) -> Variant: return s["name"])
	for n: String in NEW_SHIP_NAMES:
		if not n in used:
			return n
	return "Ship %d" % (used.size() + 1)


## A player adds a ship (M4-Q3); the lobby shows it once the server lists it.
func add_ship() -> void:
	_added = next_ship_name()
	ctx.intents.add_ship(_added)


## Puts the shown ship on a team (M4-Q6): its own crew only, before Start.
func choose_team(team: int) -> void:
	if ctx.crew.ship == ship and not bool(ctx.crew.fleet.get("started", false)):
		ctx.intents.set_team(ship, team)
	refresh()


## The New ship and team buttons and the mode line, from the `fleet` event.
func _refresh_fleet() -> void:
	_new_ship.visible = ctx.crew.can_add_ship()
	_new_ship.text = tr("lobby.new_ship")
	var teams: bool = ctx.crew.has_teams() and ship >= 0 and not _browsing
	_teams.visible = teams
	var mine: bool = ctx.crew.ship == ship and not bool(ctx.crew.fleet.get("started", false))
	for t: int in _team_buttons.size():
		var b: Button = _team_buttons[t]
		b.text = tr("lobby.team") % TEAM_LETTERS[t]
		b.set_pressed_no_signal(ctx.crew.team_of(ship) == t)
		b.disabled = not mine
	_mode_button.text = mode_text()
	_mode_button.visible = not ctx.crew.fleet.is_empty()
	if _mode_dialog != null:
		_mode_dialog.refresh()


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
	if _tapped:
		out.assign(_local)
		return out
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
	for seat: Variant in ctx.crew.ship_state(ship).get("seats", []):
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
		if entry == "":
			refresh()
			return
		ctx.intents.pick(ship, entry)
	_local = picks
	_tapped = true
	refresh()


## A tap on Captain, Viewer or the dev entry: picks it, or gives it up when it is the
## pick.
func tap_seat(id: String) -> void:
	_tapped = true
	_local = []
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
	for c: Node in _legend.get_children():
		if c != _coverage:
			_legend.remove_child(c)
			c.queue_free()
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


## Cells are kept while the same stations are listed; a refresh only updates their state
## and crew names, so a tap that lands during a refresh is not lost.
func _refresh_grid() -> void:
	var picks: Array[String] = selected_stations()
	var full: bool = picks.size() >= MAX_STATIONS
	# The dev entry holds every station: all six cells show as selected and locked; a tap
	# on one leaves it for that station alone.
	var dev: bool = ctx.crew.ship == ship and ctx.crew.entry == DEV_ALL
	var listed: Array[String] = []
	for id: String in GRID_STATIONS:
		if not ctx.crew.def_of(id).is_empty():
			listed.append(id)
	if listed != _cell_ids:
		_cell_ids = listed
		_clear(_grid)
		for id: String in listed:
			_grid.add_child(_cell(id, str(ctx.crew.def_of(id).get("load_tag", ""))))
	for cell: Node in _grid.get_children():
		var b: Button = cell as Button
		var id: String = str(b.name).trim_prefix("Entry_")
		b.set_pressed_no_signal(dev or id in picks)
		b.disabled = full and not id in picks
		# Fade the text but not the seat holders' names (they keep their contrast).
		var fade: Color = Color(1, 1, 1, 0.45) if b.disabled else Color.WHITE
		b.find_child("Name", true, false).self_modulate = fade
		b.find_child("Role", true, false).self_modulate = fade
		_set_crew(b, crew_at(id))
	_apply_columns()


## A station cell (D257): a toggle button, about half the old height: the name left and the
## seat holders' names right on the first line, the role's first sentence on the second.
## Tapping it takes the seat or leaves it. Its height follows the text, at least TOUCH_MIN.
func _cell(id: String, tag: String) -> Button:
	var b: Button = Button.new()
	b.name = "Entry_" + id
	b.toggle_mode = true
	b.theme_type_variation = "LoadCell_" + (tag if tag in LOAD_TAGS else "none")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.tooltip_text = tr("role." + id)
	b.pressed.connect(tap_station.bind(id))
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = CELL_INSET
	box.offset_top = CELL_INSET
	box.offset_right = -CELL_INSET
	box.offset_bottom = -CELL_INSET
	box.add_theme_constant_override("separation", 0)
	b.add_child(box)
	var top: HBoxContainer = HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name_label: Label = _cell_label("Name", tr("station." + id), "HeadingLabel")
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var role: Label = _cell_label("Role", _first_sentence(tr("role." + id)), "CaptionLabel")
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	role.autowrap_mode = TextServer.AUTOWRAP_OFF
	role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	role.clip_text = true
	role.custom_minimum_size = Vector2(10, 0)
	box.add_child(role)
	box.minimum_size_changed.connect(_fit_cell.bind(b, box))
	_fit_cell.call_deferred(b, box)
	return b


## The first sentence of a role text: the one line a cell shows.
static func _first_sentence(text: String) -> String:
	var i: int = text.find(". ")
	return text.left(i + 1) if i > 0 else text


## Shows the seat holders' names on a cell, right of its name; empty while nobody sits there.
func _set_crew(cell: Button, crew: PackedStringArray) -> void:
	var label: Label = cell.find_child("Crew", true, false) as Label
	if label == null:
		label = _cell_label("Crew", "", "CrewLabel")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		cell.find_child("Top", true, false).add_child(label)
	label.text = ", ".join(crew)


func _cell_label(node_name: String, text: String, variation: String) -> Label:
	var l: Label = _label(text, variation)
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Takes Variants: a deferred call can outlive the cell (a refresh rebuilds the grid).
static func _fit_cell(cell_node: Variant, box_node: Variant) -> void:
	if is_instance_valid(cell_node) and is_instance_valid(box_node):
		var cell: Button = cell_node
		var box: Control = box_node
		var h: float = box.get_combined_minimum_size().y + 2.0 * CELL_INSET
		var least: int = UiTheme.TOUCH_MIN
		if cell.get_parent() != null and cell.get_parent().get_meta(&"phone", false):
			least = PHONE_TARGET
		cell.custom_minimum_size = Vector2(0.0, maxf(h, float(least)))


func _apply_columns() -> void:
	if _grid != null:
		_grid.columns = columns_for(size)
		if size.y > 0.0:
			_arrange(size.y < SHORT_HEIGHT)
			_mode_button.text = mode_text()
			_customise.text = (preset_label(ctx.crew.toggles) if _short else tr("lobby.customise"))
		if is_inside_tree():
			_apply_targets(LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE)
			_apply_safe_area()


## Keeps the lobby inside the safe area (#28): clear of notches on each side and, on a
## phone, of the bottom gesture band.
func _apply_safe_area() -> void:
	var m: Vector4 = SafeArea.margins(self)
	_margin.offset_left = m.x
	_margin.offset_top = m.y
	_margin.offset_right = -m.z
	_margin.offset_bottom = -maxf(m.w, SafeArea.tap_band(self))


## Phones (#28): every button at least PHONE_TARGET px tall and PHONE_GAP px from the next;
## elsewhere the theme's sizes and the compact gaps (D257).
func _apply_targets(phone: bool) -> void:
	var gap: int = PHONE_GAP if phone else GRID_GAP
	for box: Control in [_grid, _ships]:
		box.add_theme_constant_override("h_separation", gap)
		box.add_theme_constant_override("v_separation", gap)
	for box: Control in [_head, _seat_row, _diff_row, _teams, _body]:
		box.add_theme_constant_override("separation", gap if phone else 4)
	_outer.add_theme_constant_override("separation", PHONE_GAP if phone else (3 if _short else 6))
	for b: Node in find_children("*", "BaseButton", true, false):
		var button: BaseButton = b as BaseButton
		if not str(button.name).begins_with("Entry_") or button.get_parent() == _seat_row:
			button.custom_minimum_size = Vector2.ONE * (PHONE_TARGET if phone else 0.0)
	_grid.set_meta(&"phone", phone)
	if phone != _phone:
		for cell: Node in _grid.get_children():
			_fit_cell(cell, cell.get_child(0))
	_phone = phone


## Lays the rows out for the window: normal, or short (a phone in landscape, #28), where
## the title row goes: the coverage joins the legend line, the team buttons and Back to
## ships the seat row, and the mode, difficulty, How to join, Main menu and Start one
## bottom row; the role summary hides (each cell shows its first sentence).
func _arrange(short: bool) -> void:
	if short == _short:
		return
	_short = short
	var pad: int = 6 if short else 12
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, pad)
	_head.visible = not short
	_summary_role.visible = not short
	_difficulty.visible = not short
	_coverage.size_flags_horizontal = Control.SIZE_EXPAND_FILL if short else Control.SIZE_FILL
	if short:
		_reparent(_coverage, _legend, 0)
		_reparent(_teams, _seat_row, -1)
		_reparent(_leave, _seat_row, -1)
		for c: Control in [_join_button, _menu, _start]:
			_reparent(c, _diff_row, -1)
	else:
		_reparent(_coverage, _outer, _ships.get_index() + 1)
		_reparent(_teams, _ships, -1)
		_reparent(_leave, _ships, -1)
		_reparent(_join_button, _head, 1)
		_reparent(_menu, _head, 2)
		_reparent(_start, _outer, -1)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _reparent(node: Control, parent: Node, index: int) -> void:
	if node.get_parent() != parent:
		node.get_parent().remove_child(node)
		parent.add_child(node)
	parent.move_child(node, index)


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
	_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	# Nothing scrolls (D216): the grid takes the height the rows around it leave.
	var outer: VBoxContainer = VBoxContainer.new()
	outer.name = "Layout"
	_outer = outer
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)
	var head: HBoxContainer = HBoxContainer.new()
	outer.add_child(head)
	_head = head
	_title = _label(tr("lobby.title"), "HeadingLabel")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_join_button = _button("JoinButton", tr("lobby.join_title"), _open_join)
	head.add_child(_join_button)
	_join_button.visible = ctx.host_bind != ""
	_menu = _button("MainMenu", tr("lobby.menu"), menu_requested.emit)
	head.add_child(_menu)
	_ships = HFlowContainer.new()
	_ships.name = "Ships"
	outer.add_child(_ships)
	_new_ship = _button("NewShip", tr("lobby.new_ship"), add_ship)
	_ships.add_child(_new_ship)
	_teams = HBoxContainer.new()
	_teams.name = "Teams"
	_ships.add_child(_teams)
	for t: int in TEAM_LETTERS.size():
		var b: Button = _button("Team_%d" % t, "", choose_team.bind(t))
		b.toggle_mode = true
		_teams.add_child(b)
		_team_buttons.append(b)
	_leave = _button("BackToShips", tr("lobby.leave_pick"), _back_to_ships)
	_ships.add_child(_leave)
	_coverage = _label("", "DimLabel")
	_coverage.name = "Coverage"
	outer.add_child(_coverage)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_body)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GRID_GAP)
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
	_start.clip_text = true
	_start.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_diff_row = row
	parent.add_child(row)
	_mode_button = _button("ModeButton", "", _open_mode)
	row.add_child(_mode_button)
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
	_mode_dialog = ModeDialog.new()
	add_child(_mode_dialog)
	_mode_dialog.setup(ctx)
	_join_dialog = AcceptDialog.new()
	_join_dialog.name = "JoinDialog"
	_join_dialog.title = tr("lobby.join_title")
	_join_dialog.ok_button_text = tr("lobby.done")
	add_child(_join_dialog)
	if ctx.host_bind != "":
		_build_join_panel(_join_dialog)


func _open_mode() -> void:
	_mode_dialog.open(get_viewport_rect().size.x < 600.0)


func _open_difficulty() -> void:
	_dialog.popup_centered_clamped(Vector2i(520, 480), 0.9)


func _open_join() -> void:
	_join_dialog.popup_centered_clamped(Vector2i(360, 320), 0.9)


## One toggle: its name, its value and a one-line description naming both stations.
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
	_customise.text = preset_label(toggles) if _short else tr("lobby.customise")
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
		row.get_node("Line/Name").text = tr("lobby.toggle." + String(def.id))
		row.get_node("Desc").text = tr("lobby.toggle.%s.desc" % def.id)
		var value: OptionButton = row.get_node("Line/Value")
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
		_menu.text = tr("lobby.menu")
		_leave.text = tr("lobby.leave_pick")
		_join_button.text = tr("lobby.join_title")
		_join_dialog.title = tr("lobby.join_title")
		_join_dialog.ok_button_text = tr("lobby.done")
		_dialog.ok_button_text = tr("lobby.done")
		if _join_panel != null:
			_join_dialog.remove_child(_join_panel)
			_join_panel.queue_free()
			_build_join_panel(_join_dialog)
		refresh()


## The server refused a request: the screen goes back to what the server holds, and a
## refused lobby request (a full fleet, a closed lobby, a bad team) says why under the grid.
func _on_refused(key: String, args: Dictionary) -> void:
	_tapped = false
	_refusal = tr(key).format(args) if TranslationServer.translate(key) != key else ""
	refresh()


func _on_crew_changed(what: StringName) -> void:
	if what == &"picked":
		_tapped = false
	if what in [&"picked", &"fleet"]:
		_refusal = ""
	if what == &"lobby":
		_push_saved_toggles()
	if what in KINDS or what == &"toggles":
		refresh()
