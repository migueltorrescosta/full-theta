class_name LobbyScreen
extends Control
## The lobby (FT-NET-019-021, D126, D129, FT-STN-015, FT-JNT-006): the ship list, the
## catalogue of the chosen ship with each entry's load as the colour of its name (D187),
## a legend above it and, for joint views, the pair it makes solo and its role summary;
## the coverage state
## from `lobby` events;
## the player's pick; and Start, which any crew player of a covered ship presses. Picks
## go to the server (ShipIntents.pick); the screen shows what the events say. The host's
## lobby also shows how to join (FT-NET-013): the browser URL with a QR code and the
## desktop address.

## The player wants out of the session (Main menu): the shell leaves, and the host's
## menu also stops its server.
signal menu_requested

## The load tags, in legend order, and the colour word the legend names them with.
const LOAD_TAGS: Array[String] = ["intense", "busy", "light"]
## Every Button font colour a pick button shows (normal, hover, pressed, focus, ...).
const BUTTON_COLORS: Array[String] = [
	"font_color",
	"font_hover_color",
	"font_pressed_color",
	"font_hover_pressed_color",
	"font_focus_color",
]
## The crew changes the lobby depends on.
const KINDS: Array[StringName] = [&"catalogue", &"lobby", &"picked"]

var ctx: StationContext
## The ship whose catalogue is shown.
var ship: int = -1

var _ships: HBoxContainer
var _entries: VBoxContainer
var _coverage: Label
var _legend: HBoxContainer
var _pick: Label
var _start: Button
var _title: Label
var _leave: Button
var _menu: Button
var _join_panel: VBoxContainer
## After "Back to ships": no ship is chosen until the player picks one.
var _browsing: bool = false


func setup(context: StationContext) -> void:
	ctx = context
	_build()
	ctx.crew.changed.connect(_on_crew_changed)
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
	_build_legend()
	_clear(_entries)
	for def: Dictionary in ctx.crew.catalogue.get("entries", []):
		_entries.add_child(_entry_row(def))
	var state: Dictionary = ctx.crew.lobby.get(ship, {})
	_coverage.text = coverage_text(state)
	_pick.text = (
		tr("lobby.your_pick") % tr("station." + ctx.crew.entry)
		if ctx.crew.entry != "" and ctx.crew.ship == ship
		else tr("lobby.no_pick")
	)
	_start.disabled = not (
		ctx.crew.is_crew() and ctx.crew.ship == ship and bool(state.get("ready", false))
	)
	_start.visible = not _browsing and not bool(state.get("started", false))
	_entries.visible = not _browsing
	_legend.visible = not _browsing
	if _browsing:
		_pick.text = tr("lobby.pick_ship")


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


## The pick button's text: the entry's name, and for a joint view its pair on a second
## line (FT-JNT-006, D186), e.g. "Tactical\nHelm + Weapons".
static func entry_label(def: Dictionary) -> String:
	var name: String = TranslationServer.translate("station." + str(def["id"]))
	var pair: String = joint_hint(def)
	return name if pair == "" else name + "\n" + pair


## The one-line legend above the seat list: "Red: intense · Yellow: busy · Green: light",
## each part in its colour (D187).
func _build_legend() -> void:
	_clear(_legend)
	for i: int in LOAD_TAGS.size():
		if i > 0:
			_legend.add_child(_label("·"))
		var tag: String = LOAD_TAGS[i]
		var item: Label = _label(tr("lobby.legend_" + tag))
		item.name = "Legend_" + tag
		item.add_theme_color_override("font_color", load_color(tag))
		_legend.add_child(item)


## The colour of a seat's load tag (intense, busy, light); the normal text colour for
## no tag (the Viewer).
static func load_color(tag: String) -> Color:
	return Palette.color("load_" + tag if tag in LOAD_TAGS else "text")


static func _label(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	return l


func _entry_row(def: Dictionary) -> Control:
	var id: String = def["id"]
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Entry_" + id
	var pick: Button = Button.new()
	pick.name = "Pick"
	pick.text = entry_label(def)
	pick.custom_minimum_size = Vector2(180, 0)
	var tag: String = str(def.get("load_tag", ""))
	if tag != "":
		for c: String in BUTTON_COLORS:
			pick.add_theme_color_override(c, load_color(tag))
	pick.toggle_mode = true
	pick.button_pressed = id == ctx.crew.entry and ship == ctx.crew.ship
	pick.pressed.connect(func() -> void: ctx.intents.pick(ship, id))
	row.add_child(pick)
	var role: Label = Label.new()
	role.name = "Role"
	role.text = tr("role." + id)
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(role)
	return row


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


## The host's "How to join" panel: URL and QR code, the desktop address, or why nobody
## else can join.
func _build_join_panel(col: Container) -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "JoinPanel"
	col.add_child(panel)
	_join_panel = panel
	var head: Label = Label.new()
	head.text = tr("lobby.join_title")
	head.add_theme_font_size_override("font_size", 20)
	panel.add_child(head)
	if is_local_only(ctx.host_bind):
		var local: Label = Label.new()
		local.name = "JoinLocal"
		local.text = tr("lobby.join_local") % ctx.host_bind
		panel.add_child(local)
		return
	var url: String = join_url(ctx.host_bind, ctx.host_port)
	var browser: Label = Label.new()
	browser.name = "JoinUrl"
	browser.text = tr("lobby.join_browser") % url
	panel.add_child(browser)
	var desktop: Label = Label.new()
	desktop.name = "JoinDesktop"
	desktop.text = tr("lobby.join_desktop") % ctx.host_bind
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
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	_title = Label.new()
	_title.text = tr("lobby.title")
	_title.add_theme_font_size_override("font_size", 32)
	col.add_child(_title)
	_ships = HBoxContainer.new()
	col.add_child(_ships)
	_coverage = Label.new()
	_coverage.name = "Coverage"
	col.add_child(_coverage)
	_legend = HBoxContainer.new()
	_legend.name = "Legend"
	_legend.add_theme_constant_override("separation", 8)
	col.add_child(_legend)
	_entries = VBoxContainer.new()
	_entries.name = "Entries"
	col.add_child(_entries)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	_pick = Label.new()
	bottom.add_child(_pick)
	_start = Button.new()
	_start.name = "Start"
	_start.text = tr("lobby.start")
	_start.pressed.connect(func() -> void: ctx.intents.start())
	bottom.add_child(_start)
	_leave = Button.new()
	_leave.text = tr("lobby.leave_pick")
	_leave.name = "BackToShips"
	_leave.pressed.connect(_back_to_ships)
	bottom.add_child(_leave)
	_menu = Button.new()
	_menu.name = "MainMenu"
	_menu.text = tr("lobby.menu")
	_menu.pressed.connect(menu_requested.emit)
	bottom.add_child(_menu)
	if ctx.host_bind != "":
		_build_join_panel(col)


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
		if _join_panel != null:
			var col: Container = _join_panel.get_parent()
			var at: int = _join_panel.get_index()
			col.remove_child(_join_panel)
			_join_panel.queue_free()
			_build_join_panel(col)
			col.move_child(_join_panel, at)
		refresh()


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
