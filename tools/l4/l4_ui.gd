extends RefCounted
## The real client UI for `l4_client.gd --client ui` (T058, FT-TST-011): the MainMenu
## (app/), its ClientShell, lobby, outcome card and StationScreen (stations/), driven
## like a player. Buttons are pressed by node name, intents arrive as the KB/M input
## events of the player's bindings (pushed into the viewport, so they pass the screen's
## InputMatcher and routing), and state() reads the shell back for `ui_expect`.

## The mouse buttons a KB/M binding may name.
const MOUSE: Dictionary = {"LMB": MOUSE_BUTTON_LEFT, "RMB": MOUSE_BUTTON_RIGHT, "MMB": 3}

var menu: MainMenu
var _root: Window


## Builds the menu with its settings, token and pid files in the run folder, so clients
## on one machine don't share user://.
func _init(root: Window, run_dir: String, player: String, token_path: String) -> void:
	_root = root
	menu = MainMenu.new()
	menu.settings = ClientSettings.new(run_dir.path_join(player + ".settings.cfg"))
	menu.settings.player_name = player
	# Scripted clients skip the first-visit help overlay (FT-STN-012), which would block
	# their input; tests/stations/test_first_visit_help.gd covers it.
	for station: Variant in StationViews.STATIONS:
		menu.settings.mark_tooltip_seen(str(station))
	menu.settings.save()
	menu.token_path = token_path
	menu.pid_path = run_dir.path_join(player + ".pid.json")
	root.add_child(menu)


## The client the menu joins with, hosts with or the shell runs; null before any.
func client() -> NetClient:
	if menu.shell != null:
		return menu.shell.ctx.client
	if menu.joining != null:
		return menu.joining
	return menu.host_session.client if menu.host_session != null else null


## Types the address into the menu and presses Join; "" or why not.
func join(address: String) -> String:
	var field: LineEdit = menu.find_child("Address", true, false)
	field.text = address
	return press(menu, "Join")


## The menu's status line (why a join failed).
func status() -> String:
	var label: Label = menu.find_child("Status", true, false)
	return label.text


## Taps the lobby's cells (or seat button) of an entry; "" or why not (yet).
func pick(entry: String) -> String:
	if menu.shell == null or menu.shell.lobby == null:
		return "no lobby"
	var lobby: LobbyScreen = menu.shell.lobby
	if (
		lobby.find_child("Entry_" + entry, true, false) == null
		and lobby.ctx.crew.def_of(entry).is_empty()
	):
		return "no entry %s in the lobby" % entry
	# The grid has the six stations; a joint view is a tap on each of its two.
	var stations: Array = lobby.ctx.crew.def_of(entry).get("stations", [])
	if stations.is_empty() or entry == LobbyScreen.DEV_ALL:
		lobby.tap_seat(entry)
	else:
		for st: Variant in stations:
			lobby.tap_station(str(st))
	return ""


## Presses the visible, enabled button `node_name` under `under` (the shell when null):
## Start, Vote, RunAgain; "" or why not (yet).
func press(under: Node, node_name: String) -> String:
	if under == null:
		under = menu.shell
	if under == null:
		return "no shell"
	for n: Node in under.find_children(node_name, "BaseButton", true, false):
		var b: BaseButton = n
		if b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return ""
	return "no visible enabled button %s" % node_name


## Sends intent `id` as its first KB/M binding pressed or released (modifiers as event
## flags; mouse buttons at pointer()); "" or why not.
func intent(id: String, pressed: bool) -> String:
	var screen: StationScreen = menu.shell.screen if menu.shell != null else null
	if screen == null:
		return "no station screen"
	var list: PackedStringArray = menu.settings.bindings.bindings(id, IntentTable.KBM)
	if list.is_empty() or list[0].contains(",") or list[0].begins_with("long "):
		return "intent %s has no plain KB/M binding" % id
	var parts: PackedStringArray = list[0].split("+")
	var main: String = parts[parts.size() - 1]
	var ev: InputEventWithModifiers
	if MOUSE.has(main):
		var at: Vector2 = pointer(screen)
		var move: InputEventMouseMotion = InputEventMouseMotion.new()
		move.position = at
		move.global_position = at
		_root.push_input(move)
		var mb: InputEventMouseButton = InputEventMouseButton.new()
		mb.button_index = MOUSE[main]
		mb.position = at
		mb.global_position = at
		ev = mb
	else:
		var code: Key = OS.find_keycode_from_string(main)
		if code == KEY_NONE:
			return "intent %s: no key %s" % [id, main]
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = code
		key.keycode = code
		ev = key
	ev.set("pressed", pressed)
	ev.shift_pressed = parts.has("Shift")
	ev.alt_pressed = parts.has("Alt")
	ev.ctrl_pressed = parts.has("Ctrl")
	_root.push_input(ev)
	return ""


## Where mouse buttons go: the radar box's top-right corner, outside the disc, where nothing
## is under the pointer (the top-left one is under the share bar in a small headless window),
## so ping and mark fall back to the selection (§5.0) and LMB falls through to the focused
## panel.
static func pointer(screen: StationScreen) -> Vector2:
	var r: Rect2 = screen.radar.get_global_rect()
	return Vector2(r.end.x - 2.0, r.position.y + 2.0)


## What the player sees, for `ui_expect`: shown (menu, lobby, station), ship, entry,
## host, focused station, selection, marks, claims, contacts, started, card (the
## outcome card is visible) and run_over (its outcome, time_s, hull, voters, needed).
func state() -> Dictionary:
	var shell: ClientShell = menu.shell
	if shell == null:
		return {"shown": "menu"}
	var crew: CrewState = shell.ctx.crew
	return {
		"shown": "station" if shell.screen != null else "lobby",
		"ship": crew.ship,
		"entry": crew.entry,
		"host": crew.host,
		"focused": shell.screen.focused_station() if shell.screen != null else "",
		"selection": crew.selection,
		"marks": crew.marks,
		"claims": crew.claims,
		"contacts": Array(shell.ctx.interp.contact_ids()),
		"started": crew.is_started(),
		"card": shell.outcome_card.visible,
		"run_over": crew.run_over.get(crew.ship, {}),
	}
