class_name LobbySeatGrid
extends RefCounted
## The lobby's seats (D216, D257, FT-NET-015, FT-JNT-006): the station grid (each cell
## names its load as a word in its load colour, #37 C9) and the coverage line, the
## selection's name and role, and the Captain, Viewer and dev buttons, with the pick rules
## (up to MAX_STATIONS stations, two make the joint view of the pair).
## It builds and fills its nodes; LobbyScreen places them and lays them out. A tap sends the
## pick to the server and emits `changed`, and the screen refreshes.

## A tap changed the picks: the lobby refreshes.
signal changed

## The load tags (a cell names its own: lobby.load_<tag>, in the tag's colour).
const LOAD_TAGS: Array[String] = ["intense", "busy", "light"]
## The crew stations in grid order (row by row in landscape).
const GRID_STATIONS: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
## Most px a grid row grows by into the lobby's spare room (grow).
const MAX_GROW: float = 64.0
## A player picks at most this many stations (a joint view covers two).
const MAX_STATIONS: int = 2
## Cell padding and the grid gap, in px at 100 % UI scale (a cell stays >= TOUCH_MIN tall).
const CELL_INSET: int = 4
const GRID_GAP: int = 4
## The lines a cell's role summary wraps to (P28-Lobby), in both orientations; the texts
## are written to fit a phone's portrait cell.
const ROLE_LINES: int = 2
const CAPTAIN: String = "captain"
const VIEWER: String = "viewer"
## The dev seat holding every station, offered by --dev-all-stations only, and shown only in a
## game started with --dev (ClientSettings.dev_flag).
const DEV_ALL: String = "all"

## The ship whose stations are shown (LobbyScreen.ship).
var ship: int = -1
## The nodes, placed by LobbyScreen: the coverage line, the grid, the Info block (the
## selection's name and role) and the seat row.
var coverage: Label
var grid: GridContainer
var info: VBoxContainer
var summary: BoxContainer
var summary_name: Label
var summary_role: Label
var seat_row: HBoxContainer
var _ctx: StationContext
var _captain: Button
var _viewer: Button
var _dev_all: Button
## The stations tapped since the server last answered a pick: a second tap before the
## answer to the first must still add to it. Empty of meaning while `_tapped` is false.
var _local: Array[String] = []
var _tapped: bool = false
## The station ids whose cells exist; a refresh rebuilds only when they change.
var _cell_ids: Array[String] = []


func _init(context: StationContext) -> void:
	_ctx = context
	coverage = _label("", "DimLabel")
	coverage.name = "Coverage"
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	_build_summary()
	_build_seats()


## The coverage line and the cells, for the shown ship's `lobby` state.
func refresh_cells(state: Dictionary) -> void:
	coverage.text = coverage_text(state)
	_refresh_grid()


## The server answered the pick (or refused it): the picks are the server's again.
func answered() -> void:
	_tapped = false


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
		names.append(tr(StationCatalogue.name_key(str(s))))
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


## The stations the player has picked on the shown ship (none for Captain, Viewer and
## the dev seat).
func selected_stations() -> Array[String]:
	var out: Array[String] = []
	if _tapped:
		out.assign(_local)
		return out
	if _ctx.crew.ship != ship or _ctx.crew.seat in [DEV_ALL, ""]:
		return out
	for st: Variant in _ctx.crew.stations():
		out.append(str(st))
	return out


## The seat covering exactly these stations: the station itself for one, the
## joint view of the pair for two; "" when there is none.
func seat_for(stations: Array[String]) -> String:
	for def: Dictionary in _ctx.crew.catalogue.get("seats", []):
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
## stations), from the `lobby` event's seats; a tick before each one who is Ready (#37 C1).
func crew_at(station: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for seat: Variant in _ctx.crew.ship_state(ship).get("seats", []):
		var covered: Array = _ctx.crew.def_of(str(seat["seat"])).get("stations", [])
		if station in covered:
			var ready: bool = bool((seat as Dictionary).get("ready", false))
			names.append(("✓ " if ready else "") + str(seat["name"]))
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
		changed.emit()
		return
	if picks.is_empty():
		_ctx.intents.release_pick()
	else:
		var seat: String = seat_for(picks)
		if seat == "":
			changed.emit()
			return
		_ctx.intents.pick(ship, seat)
	_local = picks
	_tapped = true
	changed.emit()


## A tap on Captain, Viewer or the dev seat: picks it, or gives it up when it is the
## pick.
func tap_seat(id: String) -> void:
	_tapped = true
	_local = []
	if _ctx.crew.ship == ship and _ctx.crew.seat == id:
		_ctx.intents.release_pick()
	else:
		_ctx.intents.pick(ship, id)
	changed.emit()


## The title and summary under the grid for the current pick: a station's name and
## role, or a joint view's name, its pair and its role.
func selection_text() -> Array[String]:
	var seat: String = _ctx.crew.seat if _ctx.crew.ship == ship else ""
	if seat == "":
		return [tr("lobby.no_pick"), ""]
	var name: String = tr("seat." + seat)
	var pair: String = joint_hint(_ctx.crew.def_of(seat))
	if pair != "":
		name += " (%s)" % pair
	return [name, tr("role." + seat)]


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
	# The dev seat holds every station: all six cells show as selected and locked; a tap
	# on one leaves it for that station alone.
	var dev: bool = _ctx.crew.ship == ship and _ctx.crew.seat == DEV_ALL
	var listed: Array[String] = []
	for id: String in GRID_STATIONS:
		if not _ctx.crew.def_of(id).is_empty():
			listed.append(id)
	if listed != _cell_ids:
		_cell_ids = listed
		_clear(grid)
		for id: String in listed:
			grid.add_child(_cell(id, str(_ctx.crew.def_of(id).get("load_tag", ""))))
	for cell: Node in grid.get_children():
		var b: Button = cell as Button
		var id: String = str(b.name).trim_prefix("Seat_")
		b.set_pressed_no_signal(dev or id in picks)
		b.disabled = full and not id in picks
		# Fade the text but not the seat holders' names or the load word (they keep their
		# contrast).
		var fade: Color = Color(1, 1, 1, 0.45) if b.disabled else Color.WHITE
		b.find_child("Name", true, false).self_modulate = fade
		b.find_child("Role", true, false).self_modulate = fade
		_set_crew(b, crew_at(id))


## A station cell (D257, P28-Lobby): a toggle button: the name and its load word (light, busy,
## intense, in the load colour; #37 C9, reverses D316) left and the seat holders' names right
## on the first line, the role summary wrapped under it (ROLE_LINES lines; the texts are
## written to fit). Tapping it takes the seat or leaves it. Its height follows the text, at
## least TOUCH_MIN.
func _cell(id: String, tag: String) -> Button:
	var b: Button = Button.new()
	b.name = "Seat_" + id
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
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(box)
	var top: HBoxContainer = HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name_label: Label = _cell_label("Name", tr(StationCatalogue.name_key(id)), "HeadingLabel")
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(name_label)
	if tag in LOAD_TAGS:
		var load: Label = _cell_label("Load", tr("lobby.load_" + tag), "CaptionLabel")
		load.autowrap_mode = TextServer.AUTOWRAP_OFF
		load.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		load.add_theme_color_override("font_color", load_color(tag))
		load.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(load)
	var gap: Control = Control.new()
	gap.name = "Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var role: Label = _cell_label("Role", tr("role." + id), "CaptionLabel")
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	role.max_lines_visible = ROLE_LINES
	role.custom_minimum_size = Vector2(10, 0)
	box.add_child(role)
	box.minimum_size_changed.connect(_fit_cell.bind(b, box))
	_fit_cell.call_deferred(b, box)
	return b


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


## Puts each cell's load word on its name line (`inline`, three columns) or on a line of its
## own under the name (two columns upright, where a long name, its word and the seat holders'
## names don't fit one line, as in Italian).
func place_load(inline: bool) -> void:
	for cell: Node in grid.get_children():
		var load: Control = cell.find_child("Load", true, false)
		if load == null:
			continue
		var top: Node = cell.find_child("Top", true, false)
		var box: Node = top.get_parent()
		var want: Node = top if inline else box
		if load.get_parent() != want:
			load.get_parent().remove_child(load)
			want.add_child(load)
			want.move_child(load, 1)


## Gives each grid row up to MAX_GROW px of the room `free` (px) the lobby has to spare (the
## room a hidden ship row leaves), so the grid fills the screen rather than leaving an empty
## band.
func grow(free: float) -> void:
	var rows: int = ceili(float(grid.get_child_count()) / maxf(1.0, float(grid.columns)))
	var now: float = grid.get_meta(&"extra", 0.0)
	var want: float = clampf(floorf(now + free / maxf(1.0, float(rows))), 0.0, MAX_GROW)
	if absf(want - now) < 1.0:
		return
	grid.set_meta(&"extra", want)
	fit_cells()


## Re-fits every cell's height, after the grid's phone flag changed.
func fit_cells() -> void:
	for cell: Node in grid.get_children():
		_fit_cell(cell, cell.get_child(0))


## Takes Variants: a deferred call can outlive the cell (a refresh rebuilds the grid).
static func _fit_cell(cell_node: Variant, box_node: Variant) -> void:
	if is_instance_valid(cell_node) and is_instance_valid(box_node):
		var cell: Button = cell_node
		var box: Control = box_node
		var h: float = box.get_combined_minimum_size().y + 2.0 * CELL_INSET
		var least: int = UiTheme.TOUCH_MIN
		var extra: float = 0.0
		if cell.get_parent() != null:
			if cell.get_parent().get_meta(&"phone", false):
				least = UiTheme.TOUCH_PRIMARY
			extra = cell.get_parent().get_meta(&"extra", 0.0)
		cell.custom_minimum_size = Vector2(0.0, maxf(h, float(least)) + extra)


## The Captain, Viewer and dev buttons: the pick's one is pressed; Captain is greyed out
## while another player holds it.
func refresh_seats(phone: bool) -> void:
	var mine: String = _ctx.crew.seat if _ctx.crew.ship == ship else ""
	for pair: Array in [[_captain, CAPTAIN], [_viewer, VIEWER], [_dev_all, DEV_ALL]]:
		var b: Button = pair[0]
		b.set_pressed_no_signal(mine == pair[1])
		b.text = tr(StationCatalogue.name_key(pair[1]))
	if phone:
		_dev_all.text = TouchText.of("lobby.dev_short", "All (dev)")
	_captain.disabled = _ctx.crew.captain_seated(ship) and mine != CAPTAIN
	# Only when this game was started with --dev and the server offers it (#35 A7).
	_dev_all.visible = ClientSettings.dev_flag and not _ctx.crew.def_of(DEV_ALL).is_empty()


func refresh_summary() -> void:
	var text: Array[String] = selection_text()
	summary_name.text = text[0]
	summary_role.text = text[1]


## The selection's name and role, in the Info block (the coverage line joins it on a short
## screen, with no gap between them).
func _build_summary() -> void:
	info = VBoxContainer.new()
	info.name = "Info"
	info.add_theme_constant_override("separation", 0)
	var box: BoxContainer = BoxContainer.new()
	box.vertical = true
	box.name = "Summary"
	info.add_child(box)
	summary = box
	summary_name = _label("", "HeadingLabel")
	summary_name.name = "SummaryName"
	summary_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(summary_name)
	summary_role = _label("", "DimLabel")
	summary_role.name = "SummaryRole"
	summary_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(summary_role)


func _build_seats() -> void:
	seat_row = HBoxContainer.new()
	seat_row.name = "Seats"
	_captain = _seat_button(CAPTAIN)
	_viewer = _seat_button(VIEWER)
	_dev_all = _seat_button(DEV_ALL)


func _seat_button(id: String) -> Button:
	var b: Button = Button.new()
	b.name = "Seat_" + id
	b.text = ""
	b.pressed.connect(tap_seat.bind(id))
	b.toggle_mode = true
	b.theme_type_variation = "TouchButton"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_row.add_child(b)
	return b


static func _clear(box: Container) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
