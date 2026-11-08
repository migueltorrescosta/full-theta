class_name LobbyScreen
extends Control
## The lobby as the station grid (D216, FT-NET-015, FT-NET-017, FT-NET-032, FT-STN-015, FT-JNT-006):
## the six crew stations as cells, 3 columns by 2 rows in landscape and 2 by 3 in portrait on every
## device, each with its name, its role description, the names of the crewmates who picked it and a
## border in its load colour; a one-line legend under the grid (compact, D257: about half the old
## height, no Take button, the cell takes or leaves the seat; the role summary wraps to
## LobbySeatGrid.ROLE_LINES lines, P28-Lobby). Tapping cells multi-selects up to two stations (two
## make the joint view of that pair) and the pick goes to the server on each tap; with two picked
## the other cells grey out; tapping a picked cell deselects it. Under the grid the selection's name
## and summary show. Captain and Viewer are two buttons below (each clears the picks). The host's
## difficulty is one line with Customise, which opens a dialog of the data-shortcut toggles
## (FT-PAIR-017, FT-STN-016; read-only for the others); Start is the confirm. Nothing scrolls: the
## whole lobby fits the screen. Picks go to the server (ShipIntents.pick); the screen shows what the
## events say. The host's lobby also has a "How to join" dialog (FT-NET-013): the browser URL with a
## QR code and the desktop address; while the ship's seats are open the QR code and the address in
## large type also sit under the title row (#35 A6), smaller on a phone upright and left to the
## dialog on a short screen. A player with no name of their own (a phone that joined by QR code)
## gets a one-field name prompt at the top (#35 A5).
##
## Multi-ship sessions (#11, M4-Q3, M4-Q4, M4-Q6): the ship row lists the `fleet` ships
## (with their team in TEAMS and HOLDOUT) and a New ship button while there is room (any
## player, up to 6); a crew puts its ship on team A or B; the host's mode and options sit
## behind the Mode button (read-only for the others); Start is pressed per ship and then
## names the ships still to press it, since the universe starts all together.
##
## Phones (#28): in landscape (a short window) the ship row stays its own row and Start,
## Mode and the difficulty join the seat row; the legend and the selection (its name and
## role on one line) sit together between the grid and the seat row. Upright, Start joins
## the difficulty row and the selection's text is smaller. On a phone the wide buttons of
## the seat and bottom rows trim their text rather than overflow. Every tap target is at least
## TOUCH_PRIMARY px tall with TOUCH_GAP px between them.
##
## The seats are LobbySeatGrid, the mode and difficulty LobbyGameSetup, and the join strip and
## name prompt live in LobbyJoinPanel; this screen places them, lays them out and refreshes them.

## The player wants out of the session (Main menu): the shell leaves, and the host's
## menu also stops its server.
signal menu_requested

const LANDSCAPE_COLUMNS: int = 3
## A window shorter than this (a phone in landscape) merges the header rows and puts the
## difficulty line on the seat row, so Start stays on screen.
const SHORT_HEIGHT: float = 500.0
## A window narrower than this (a phone upright) shortens the mode button to "Mode: Teams".
const NARROW_WIDTH: float = 700.0
const PORTRAIT_COLUMNS: int = 2
## Font sizes of the selection line on a short screen (its name, then its role).
const SHORT_NAME_SIZE: int = 15
const SHORT_ROLE_SIZE: int = 13
## The Start text's size when it wraps to two lines in a 48 px row.
const START_WRAP_SIZE: int = 13
## The top margin of a short screen, in px.
const SHORT_TOP: int = 0
## Added to each wide button's natural width when sharing a phone row (short names first).
const WEIGH_SLACK: float = 12.0
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
## Forward for tools/l4/l4_ui.gd.
const DEV_ALL: String = LobbySeatGrid.DEV_ALL

var ctx: StationContext
## The ship whose stations are shown (the seat grid shows the same).
var ship: int = -1:
	set(value):
		ship = value
		if _seats != null:
			_seats.ship = value

## The ship row: a button per ship, then New ship, the team buttons and Back to ships; it
## wraps on a narrow screen.
var _ships: HFlowContainer
## On a phone (#28 follow-up) the ship buttons and New ship scroll sideways in one row
## (LobbyShipStrip) and upright the team buttons and Back to ships take the row under it.
var _strip: LobbyShipStrip
var _ship_tools: HFlowContainer
var _new_ship: Button
var _teams: HBoxContainer
var _team_buttons: Array[Button] = []
## The seat grid (LobbySeatGrid) and the game setup (LobbyGameSetup); the nodes below of
## theirs that the layout moves and styles are theirs too.
var _seats: LobbySeatGrid
var _game_setup: LobbyGameSetup
## The name of the ship this player just added: chosen once the `fleet` event lists it.
var _added: String = ""
## Why the server refused the last request, shown under the grid until the next change.
var _refusal: String = ""
var _head: HBoxContainer
var _fullscreen: FullscreenToggle
var _outer: VBoxContainer
var _margin: MarginContainer
var _short: bool = false
## The lobby is on a phone (LayoutMode PHONE): cells and buttons take phone sizes.
var _phone: bool = false
var _start: Button
var _title: Label
var _leave: Button
var _menu: Button
var _end_dialog: ConfirmationDialog
var _body: Control
var _join_button: Button
var _join_dialog: AcceptDialog
var _join_panel: LobbyJoinPanel
## The host's QR code and address while seats are open; null off the host or on loopback.
var _join_strip: LobbyJoinPanel.Strip
## The name prompt (#35 A5) and its field.
var _name_row: LobbyJoinPanel.NamePrompt
var _name_field: LineEdit
## After "Back to ships": no ship is chosen until the player picks one.
var _browsing: bool = false
## The ship ids whose buttons exist; a refresh rebuilds only when they change.
var _ship_ids: Array = []


func setup(context: StationContext) -> void:
	ctx = context
	_build()
	PadFocus.attach(self)
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
	var box: Container = _strip.row if _strip.visible else _ships
	if ship_ids != _ship_ids:
		_ship_ids = ship_ids
		for c: Node in box.get_children():
			if str(c.name).begins_with("Ship_"):
				box.remove_child(c)
				c.queue_free()
		for i: int in ships.size():
			var b: Button = Button.new()
			b.name = "Ship_%d" % int(ships[i]["ship"])
			b.toggle_mode = true
			b.pressed.connect(_choose_ship.bind(int(ships[i]["ship"])))
			LobbyShipStrip.adopt(b, _strip.visible)
			box.add_child(b)
			box.move_child(b, i)
	for i: int in ships.size():
		var b: Button = box.get_child(i) as Button
		b.text = ship_label(ships[i])
		b.set_pressed_no_signal(int(ships[i]["ship"]) == ship)
	var state: Dictionary = ctx.crew.ship_state(ship)
	_seats.refresh_cells(state)
	_apply_columns()
	_seats.refresh_seats(_phone)
	_weigh_buttons()
	_seats.refresh_summary()
	_refresh_fleet()
	_start.disabled = not (
		ctx.crew.is_crew() and ctx.crew.ship == ship and bool(state.get("ready", false))
	)
	_start.text = tr("lobby.start")
	if _start.disabled:
		# A greyed Start says what it waits for, on every form (R24-6, R26-3).
		_start.text = start_blocker(state)
	if ctx.crew.waiting_for_others(ship):
		_start.disabled = true
		_start.text = tr("lobby.waiting") % ", ".join(ctx.crew.waiting_names())
	_fit_start()
	_start.visible = (
		not _browsing
		and (not bool(state.get("started", false)) or ctx.crew.waiting_for_others(ship))
	)
	_body.visible = not _browsing
	_leave.visible = not _browsing
	_show_join_strip()
	_menu.text = tr("lobby.end_game" if ctx.crew.host else "lobby.menu")
	_fit_strip.call_deferred()
	_refresh_data()
	if _refusal != "":
		_seats.summary_role.text = _refusal
	if _browsing:
		_seats.summary_name.text = tr("lobby.pick_ship")
		_seats.summary_role.text = ""
		_body.visible = false


## A Start text too long for one line ("Falta: Retransmissão, Comunicações" in a phone's
## row) wraps to two lines in a smaller font, so it is never cut and the row keeps its height.
func _fit_start() -> void:
	_start.remove_theme_font_size_override("font_size")
	var font: Font = _start.get_theme_font("font")
	var fs: int = _start.get_theme_font_size("font_size")
	var room: float = _start.size.x - _start.get_theme_stylebox("normal").get_minimum_size().x
	var wide: float = font.get_string_size(_start.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var long: bool = room > 0.0 and wide > room
	_start.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if long else TextServer.AUTOWRAP_OFF
	if long:
		_start.add_theme_font_size_override("font_size", START_WRAP_SIZE)


## Why Start is greyed on the shown ship: "Pick a station", "Need Relay, Comms" or
## "Need 1 more player"; "Start" when nothing blocks it.
func start_blocker(state: Dictionary) -> String:
	if ctx.crew.ship != ship or not ctx.crew.is_crew():
		return tr("lobby.need_seat")
	if bool(state.get("ready", false)):
		return tr("lobby.start")
	var uncovered: Array = state.get("uncovered", [])
	if not uncovered.is_empty():
		var names: PackedStringArray = []
		for st: Variant in uncovered:
			names.append(tr("station." + str(st)))
		return tr("lobby.need_stations") % ", ".join(names)
	var missing: int = maxi(1, int(state.get("min_crew", 3)) - int(state.get("crew", 0)))
	if missing == 1:
		return tr("lobby.need_players_one")
	return tr("lobby.need_players") % missing


## A ship button's text: its name, and its team in TEAMS and HOLDOUT ("Heron (B)").
func ship_label(row: Dictionary) -> String:
	var text: String = str(row.get("name", ""))
	if ctx.crew.has_teams():
		text = tr("lobby.ship_team") % [text, TEAM_LETTERS[clampi(int(row.get("team", 0)), 0, 1)]]
	return text


## The mode button's text (LobbyGameSetup.mode_text): just the mode's name on a narrow or
## short screen.
func mode_text() -> String:
	return _game_setup.mode_text(_short or size.x < NARROW_WIDTH)


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
	_game_setup.refresh_mode(mode_text())


## The columns of the grid for a lobby of this size: 3 in landscape, 2 in portrait.
static func columns_for(size: Vector2) -> int:
	return PORTRAIT_COLUMNS if size.x < size.y else LANDSCAPE_COLUMNS


## The catalogue entry covering exactly these stations (LobbySeatGrid.entry_for).
func entry_for(stations: Array[String]) -> String:
	return _seats.entry_for(stations)


## A tap on a station cell (LobbySeatGrid.tap_station).
func tap_station(id: String) -> void:
	_seats.tap_station(id)


## A tap on Captain, Viewer or the dev entry (LobbySeatGrid.tap_seat).
func tap_seat(id: String) -> void:
	_seats.tap_seat(id)


static func _label(text: String, variation: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _apply_columns() -> void:
	if _seats != null:
		_seats.grid.columns = columns_for(size)
		if size.y > 0.0:
			_arrange(size.y < SHORT_HEIGHT)
			_game_setup.mode_button.text = mode_text()
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
	var gap: int = PHONE_GAP if phone else LobbySeatGrid.GRID_GAP
	for box: Control in [_seats.grid, _ships, _ship_tools]:
		box.add_theme_constant_override("h_separation", gap)
		box.add_theme_constant_override("v_separation", gap)
	_use_strip(phone)
	for box: Control in [_head, _seats.seat_row, _game_setup.row, _teams, _body, _strip.row]:
		box.add_theme_constant_override("separation", gap if phone else 4)
	_outer.add_theme_constant_override("separation", PHONE_GAP if phone else (3 if _short else 6))
	for b: Node in find_children("*", "BaseButton", true, false):
		var button: BaseButton = b as BaseButton
		if button is FullscreenToggle:
			continue
		if not str(button.name).begins_with("Entry_") or button.get_parent() == _seats.seat_row:
			button.custom_minimum_size = Vector2.ONE * (PHONE_TARGET if phone else 0.0)
	_seats.grid.set_meta(&"phone", phone)
	_name_field.custom_minimum_size.y = PHONE_TARGET if phone else 0.0
	if phone != _phone:
		if _join_strip != null:
			_join_strip.fit(phone)
		_seats.fit_cells()
	_phone = phone
	_style_summary(_short, phone)
	# A phone upright shows the labelled mode and the preset on the difficulty row ("Mode:
	# Teams", "Difficulty: Easy"), with Start under it on its own row (R24-5, R24-6).
	if not _short:
		_game_setup.difficulty.visible = not phone
		_reparent(_start, _outer, -1)
	_game_setup.label_customise(_short or phone)


## Lays the rows out for the window: normal, or short (a phone in landscape, #28), where
## the title row goes: the coverage joins the legend line, the team buttons and Back to
## ships the seat row, and the mode, difficulty, How to join, Main menu and Start one
## bottom row; the legend and the selection share one block, the selection's name and
## role on one line (the role trimmed to fit).
func _arrange(short: bool) -> void:
	if short == _short:
		return
	_short = short
	var pad: int = 6 if short else 12
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, pad)
	# A phone keeps a floor of safe margin on top already (SafeArea.FLOOR).
	_margin.add_theme_constant_override("margin_top", SHORT_TOP if short else pad)
	_head.visible = not short
	_game_setup.difficulty.visible = not short
	_seats.summary.vertical = not short
	_seats.coverage.theme_type_variation = "CaptionLabel" if short else "DimLabel"
	_seats.summary.add_theme_constant_override("separation", 6 if short else 0)
	_seats.summary_role.clip_text = short and _phone
	_seats.summary_role.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if short else Control.SIZE_FILL
	)
	_style_summary(short, _phone)
	_show_join_strip()


## On a phone or a short screen, shares a row's room among its wide buttons by their
## natural width (text and padding), so each shows whole while the row fits; elsewhere
## they share it evenly.
func _weigh_buttons() -> void:
	for row: Control in [_seats.seat_row, _game_setup.row]:
		for c: Node in row.get_children():
			var b: Button = c as Button
			if b == null or not b.size_flags_horizontal & Control.SIZE_EXPAND:
				continue
			var w: float = 1.0
			if _short or _phone:
				var font_size: int = b.get_theme_font_size("font_size")
				var text: Vector2 = b.get_theme_font("font").get_string_size(
					b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
				)
				w = text.x + b.get_theme_stylebox("normal").get_minimum_size().x + WEIGH_SLACK
			b.size_flags_stretch_ratio = maxf(1.0, w)


## The selection's name and role: on a short screen one line, the role trimmed; on a phone
## upright smaller, the role at most LobbySeatGrid.ROLE_LINES lines; elsewhere the heading and
## the whole role, centred. On a phone or a short screen the seat and bottom rows' wide buttons
## (Captain, Viewer, the dev seat, Start) trim their text rather than push the row off
## the screen (longer languages).
func _style_summary(short: bool, phone: bool) -> void:
	var small: bool = short or phone
	for row: Control in [_seats.seat_row, _game_setup.row]:
		for c: Node in row.get_children():
			if c is Button and (c as Button).size_flags_horizontal & Control.SIZE_EXPAND:
				# (upright the seats show whole: Capitão, Espectador)
				(c as Button).clip_text = short if row == _seats.seat_row else small
				(c as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_weigh_buttons()
	for pair: Array in [
		[_seats.summary_name, SHORT_NAME_SIZE], [_seats.summary_role, SHORT_ROLE_SIZE]
	]:
		var label: Label = pair[0]
		if small:
			label.add_theme_font_size_override("font_size", pair[1])
		else:
			label.remove_theme_font_size_override("font_size")
		var one: bool = short and (phone or label == _seats.summary_name)  # (T3: a short desktop wraps)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF if one else TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if short else HORIZONTAL_ALIGNMENT_CENTER
		)
	_seats.summary_role.max_lines_visible = LobbySeatGrid.ROLE_LINES if small else -1
	_seats.summary_role.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS if small else TextServer.OVERRUN_NO_TRIMMING
	)
	_seats.coverage.size_flags_horizontal = Control.SIZE_EXPAND_FILL if short else Control.SIZE_FILL
	# A long coverage line (pt_PT, it) wraps upright and trims on its side, never widening
	# the lobby past a phone's screen.
	_seats.coverage.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART if phone and not short else TextServer.AUTOWRAP_OFF
	)
	_seats.coverage.clip_text = phone and short
	_seats.coverage.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if short:
		_reparent(_seats.legend, _body.get_node("Info"), 0)
		_reparent(_seats.coverage, _seats.legend, 0)
		_reparent(_teams, _seats.seat_row, -1)
		_reparent(_leave, _seats.seat_row, -1)
		for c: Control in [_join_button, _menu, _start, _fullscreen]:
			_reparent(c, _game_setup.row, -1)
	else:
		_reparent(_seats.legend, _body, _seats.grid.get_index() + 1)
		_reparent(_seats.coverage, _outer, _ship_tools.get_index() + 1)
		_reparent(_teams, _ship_tools if _phone else _ships, -1)
		_reparent(_leave, _ship_tools if _phone else _ships, -1)
		_reparent(_join_button, _head, 1)
		_reparent(_menu, _head, 2)
		_reparent(_fullscreen, _head, 3)
		_reparent(_start, _outer, -1)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _reparent(node: Control, parent: Node, index: int) -> void:
	if node.get_parent() != parent:
		node.get_parent().remove_child(node)
		parent.add_child(node)
	parent.move_child(node, index)


## The phone's ship strip (LobbyShipStrip) or the flow, and where the team buttons and Back
## to ships go: the row under the strip upright, the flow off a phone.
func _use_strip(phone: bool) -> void:
	if _strip.visible != phone:
		_strip.use(phone, _ships, _new_ship)
		if not _short:
			_reparent(_teams, _ship_tools if phone else _ships, -1)
			_reparent(_leave, _ship_tools if phone else _ships, -1)
		_fit_strip.call_deferred()
	_ships.visible = not phone
	_ship_tools.visible = phone and not _short


func _fit_strip() -> void:
	_strip.fit(_outer.size.x)


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
	_menu = _button("MainMenu", tr("lobby.menu"), _on_menu_pressed)
	head.add_child(_menu)
	# Full screen: an icon at the right of the title row, where the device offers it (D323).
	_fullscreen = FullscreenToggle.new()
	head.add_child(_fullscreen)
	_name_row = LobbyJoinPanel.NamePrompt.new(ctx)
	_name_field = _name_row.field
	outer.add_child(_name_row)
	_join_strip = LobbyJoinPanel.Strip.for_host(ctx)
	if _join_strip != null:
		outer.add_child(_join_strip)
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
	_strip = LobbyShipStrip.new()
	outer.add_child(_strip)
	_ship_tools = HFlowContainer.new()
	_ship_tools.name = "ShipTools"
	_ship_tools.visible = false
	outer.add_child(_ship_tools)
	_seats = LobbySeatGrid.new(ctx)
	_seats.ship = ship
	_seats.changed.connect(refresh)
	outer.add_child(_seats.coverage)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_body)
	_body.add_child(_seats.grid)
	_body.add_child(_seats.legend)
	_body.add_child(_seats.info)
	_body.add_child(_seats.seat_row)
	_game_setup = LobbyGameSetup.new(ctx)
	_game_setup.refresh_needed.connect(_refresh_data)
	_body.add_child(_game_setup.row)
	_start = _button("Start", tr("lobby.start"), func() -> void: ctx.intents.start())
	_start.theme_type_variation = "TouchButton"
	_start.clip_text = true
	_start.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_start.resized.connect(_fit_start)
	outer.add_child(_start)
	_build_dialogs()


## The join strip shows while the ship's seats are open (not started); a short screen (a phone
## on its side) has no row to spare, and How to join holds it there.
func _show_join_strip() -> void:
	if _join_strip != null:
		var started: bool = bool(ctx.crew.ship_state(ship).get("started", false))
		_join_strip.visible = not _short and not started


func _button(node_name: String, text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.pressed.connect(handler)
	return b


## The dialogs: the difficulty toggles and the mode, the end of the game and, on the host,
## how to join.
func _build_dialogs() -> void:
	_game_setup.add_dialogs(self)
	_end_dialog = ConfirmationDialog.new()
	_end_dialog.name = "EndDialog"
	_end_dialog.title = tr("lobby.end_title")
	_end_dialog.dialog_text = tr("lobby.end_text")
	_end_dialog.ok_button_text = tr("lobby.end_game")
	_end_dialog.cancel_button_text = tr("lobby.end_keep")
	_end_dialog.confirmed.connect(menu_requested.emit)
	add_child(_end_dialog)
	_join_dialog = AcceptDialog.new()
	_join_dialog.name = "JoinDialog"
	_join_dialog.title = tr("lobby.join_title")
	_join_dialog.ok_button_text = tr("lobby.done")
	add_child(_join_dialog)
	if ctx.host_bind != "":
		_join_panel = LobbyJoinPanel.new(ctx)
		_join_dialog.add_child(_join_panel)


## Leave for a player; the host's button ends the game for everyone, so it asks first (R24-2).
func _on_menu_pressed() -> void:
	if ctx.crew.host:
		_end_dialog.popup_centered()
	else:
		menu_requested.emit()


func _open_join() -> void:
	_join_dialog.popup_centered_clamped(Vector2i(360, 320), 0.9)


## The game setup's difficulty line and dialog (LobbyGameSetup.refresh).
func _refresh_data() -> void:
	_game_setup.refresh(_short or _phone)


## A language switch retranslates the whole lobby.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and ctx != null:
		_title.text = tr("lobby.title")
		_start.text = tr("lobby.start")
		_menu.text = tr("lobby.end_game" if ctx.crew.host else "lobby.menu")
		_end_dialog.title = tr("lobby.end_title")
		_end_dialog.dialog_text = tr("lobby.end_text")
		_end_dialog.ok_button_text = tr("lobby.end_game")
		_end_dialog.cancel_button_text = tr("lobby.end_keep")
		_leave.text = tr("lobby.leave_pick")
		_join_button.text = tr("lobby.join_title")
		_name_field.placeholder_text = tr("menu.name")
		if _join_strip != null:
			(_join_strip.find_child("JoinStripCaption", true, false) as Label).text = tr(
				"lobby.join_scan"
			)
		_join_dialog.title = tr("lobby.join_title")
		_join_dialog.ok_button_text = tr("lobby.done")
		_game_setup.retranslate()
		if _join_panel != null:
			_join_dialog.remove_child(_join_panel)
			_join_panel.queue_free()
			_join_panel = LobbyJoinPanel.new(ctx)
			_join_dialog.add_child(_join_panel)
		refresh()


## The server refused a request: the screen goes back to what the server holds, and a
## refused lobby request (a full fleet, a closed lobby, a bad team) says why under the grid.
func _on_refused(key: String, args: Dictionary) -> void:
	_seats.answered()
	_refusal = tr(key).format(args) if TranslationServer.translate(key) != key else ""
	refresh()


func _on_crew_changed(what: StringName) -> void:
	if what == &"picked":
		_seats.answered()
	if what in [&"picked", &"fleet"]:
		_refusal = ""
	if what == &"lobby":
		_game_setup.push_saved_toggles()
	if what in KINDS or what == &"toggles":
		refresh()
