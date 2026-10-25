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
const KINDS: Array[StringName] = [&"catalogue", &"lobby", &"picked", &"toggles"]

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
## The data-shortcut section (strand G): preset buttons, the current name, the Customise
## button and the toggle rows behind it.
var _data_box: VBoxContainer
var _preset_buttons: Dictionary = {}
var _preset_name: Label
var _customise: Button
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
	_data_box.visible = not _browsing
	_refresh_data()
	if _browsing:
		_pick.text = tr("lobby.pick_ship")


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
	# The seat list and the host's join panel scroll on short screens; the bottom bar
	# (pick, Start, Back to ships, Main menu) stays in view below them.
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)
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
	_build_data_box(col)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	outer.add_child(bottom)
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


## The data-shortcut section (FT-PAIR-017, FT-STN-016): the three presets and the name of
## the set, then "Customise", behind which each toggle has a one-line description naming
## both stations, its value and, for the two Comms toggles, that it arrives in M3 (D190).
func _build_data_box(col: Container) -> void:
	_data_box = VBoxContainer.new()
	_data_box.name = "DataShortcuts"
	_data_box.add_theme_constant_override("separation", 6)
	col.add_child(_data_box)
	var head: Label = Label.new()
	head.name = "DataTitle"
	head.text = tr("lobby.data")
	head.add_theme_font_size_override("font_size", 20)
	_data_box.add_child(head)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Presets"
	row.add_theme_constant_override("separation", 8)
	_data_box.add_child(row)
	for preset: String in DataToggles.PRESETS:
		var b: Button = Button.new()
		b.name = "Preset_" + preset
		b.toggle_mode = true
		b.pressed.connect(_choose_preset.bind(preset))
		_preset_buttons[preset] = b
		row.add_child(b)
	_preset_name = Label.new()
	_preset_name.name = "PresetName"
	row.add_child(_preset_name)
	_customise = Button.new()
	_customise.name = "Customise"
	_customise.toggle_mode = true
	_customise.text = tr("lobby.customise")
	_customise.toggled.connect(func(on: bool) -> void: _toggle_rows.visible = on)
	row.add_child(_customise)
	_toggle_note = Label.new()
	_toggle_note.name = "ToggleNote"
	_data_box.add_child(_toggle_note)
	_toggle_rows = VBoxContainer.new()
	_toggle_rows.name = "Toggles"
	_toggle_rows.visible = false
	_toggle_rows.add_theme_constant_override("separation", 4)
	_data_box.add_child(_toggle_rows)
	for def: DataToggleDef in DataToggles.def().toggles:
		_toggle_rows.add_child(_toggle_row(def))


func _toggle_row(def: DataToggleDef) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Toggle_" + String(def.id)
	row.add_theme_constant_override("separation", 12)
	var name: Label = Label.new()
	name.name = "Name"
	name.custom_minimum_size = Vector2(200, 0)
	row.add_child(name)
	var value: OptionButton = OptionButton.new()
	value.name = "Value"
	value.item_selected.connect(func(i: int) -> void: _set_value(def.id, value.get_item_id(i)))
	row.add_child(value)
	var desc: Label = Label.new()
	desc.name = "Desc"
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)
	return row


## Shows the session's set: the current name, the pressed preset, every toggle's text and
## value, and whether the host can still change them.
func _refresh_data() -> void:
	var toggles: DataToggles = ctx.crew.toggles
	var editable: bool = can_edit_toggles()
	_data_box.get_node("DataTitle").text = tr("lobby.data")
	_customise.text = tr("lobby.customise")
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
		row.get_node("Name").text = text
		row.get_node("Desc").text = tr("lobby.toggle.%s.desc" % def.id)
		var value: OptionButton = row.get_node("Value")
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
		if _join_panel != null:
			var col: Container = _join_panel.get_parent()
			var at: int = _join_panel.get_index()
			col.remove_child(_join_panel)
			_join_panel.queue_free()
			_build_join_panel(col)
			col.move_child(_join_panel, at)
		refresh()


func _on_crew_changed(what: StringName) -> void:
	if what == &"lobby":
		_push_saved_toggles()
	if what in KINDS or what == &"toggles":
		refresh()
