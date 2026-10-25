## Station widgets for the L5 harness (#7): builds tests/stations/station_fixture.gd's
## context and shows one view of it, set from shots.json: "screen" (the StationScreen
## of `entry`), "lobby", "menu" or "menu_web" (the main menu, with or without the Host
## section), or "radar" (the disc radar alone, large). Extras: `selected`
## (a contact id, -1 none), `ping` (a contact id pinged a second ago, -1 none),
## `overlay` (the menu on its Controls tab), `menu_tab` (the menu on that tab), `tooltip`
## (the first visit: it opens by itself), `strip` (the radar's side strip) and
## `ui_scale` (the window's content scale, FT-STN-013; reset on exit), `claim` (a
## claim item the player holds, e.g. "mount:0") and `events` (sim events fed to the
## crew model 2 s before the shot, after the screen is built; a payload `vector` given
## as [x, y, z] becomes a Vector3), `focus` (the focused panel of a joint view, F1 = 0),
## `science` (a Science block with the cards, a scan or a hack open) and `touch` (the touch
## layout whatever the pointer; a viewport under 600 px is a phone anyway, D195).
extends Control

var view: String = "screen"
var entry: String = "science"
var selected: int = StationFixture.H2
var ping: int = -1
var overlay: bool = false
var tooltip: bool = false
## A menu tab to open (SettingsScreen.TAB_SETTINGS), "" for none.
var menu_tab: String = ""
var strip: bool = false
var ui_scale: float = 1.0
var claim: String = ""
var events: Array = []
var focus: int = 0
## Force the touch layout (a tablet-sized shot has no touch screen under Xvfb).
var touch: bool = false
## A SCIENCE block for the shot ("cards", "scan" or "hack", ScienceShotBlocks); "" none.
var science: String = ""

var _ctx: StationContext


func _ready() -> void:
	LayoutMode.forced = LayoutMode.Kind.TOUCH if touch else -1
	I18n.apply("en")
	LayoutMode.apply(get_tree().root)
	get_tree().root.content_scale_factor = ui_scale
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ctx = StationFixture.context(entry, "user://l5_station_shot.cfg")
	if science != "":
		_ctx.view.blocks[StationViews.Section.SCIENCE] = ScienceShotBlocks.block(science)
	if tooltip:
		_ctx.settings.reset_tooltips()
	if claim != "":
		_ctx.crew.claims[claim] = {"session": StationFixture.SESSION, "name": "Ana"}
	if selected >= 0:
		_ctx.crew.select("contact", selected)
	if ping >= 0:
		var p: Dictionary = {"ship": 0, "kind": "contact", "id": ping, "site": 0, "by": "Bo"}
		_ctx.crew.handle_event({"type": "ping", "payload": p}, StationFixture.NOW_MS - 1000)
	match view:
		"menu", "menu_web":
			var m: MainMenu = MainMenu.new()
			m.web = view == "menu_web"
			m.settings = ClientSettings.new("user://l5_menu.cfg")
			m.settings.player_name = "Ana"
			m.token_path = "user://l5_menu_none.token"
			m.pid_path = "user://l5_menu_none.pid"
			add_child(m)
		"lobby":
			_ctx.crew.lobby[0]["started"] = false
			_ctx.crew.lobby[0]["ready"] = false
			_ctx.crew.lobby[0]["crew"] = 2
			_ctx.crew.lobby[0]["uncovered"] = ["relay", "comms"]
			var l: LobbyScreen = LobbyScreen.new()
			l.setup(_ctx)
			add_child(l)
		"radar":
			var bg: ColorRect = ColorRect.new()
			bg.color = Palette.color("background")
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(bg)
			var r: DiscRadar = DiscRadar.new()
			r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			r.side_strip = strip
			r.set_picture(_ctx.picture(), _ctx.crew.selection)
			add_child(r)
		_:
			var s: StationScreen = StationScreen.new()
			s.setup(_ctx)
			var menu: SettingsScreen = SettingsScreen.new()
			menu.visible = false
			s.help_requested.connect(
				func() -> void:
					menu.set_controls(
						_ctx.settings.bindings, s.stations, _ctx.matcher.device, _ctx.crew.entry
					)
					menu.open(SettingsScreen.TAB_CONTROLS)
			)
			add_child(menu)
			menu.setup(_ctx.settings, true)
			add_child(s)
			move_child(menu, -1)
			s.focus(focus)
			s.radar.side_strip = strip
			if overlay:
				s.help_requested.emit()
			if menu_tab != "":
				menu.open(menu_tab)
			for e: Dictionary in events:
				var p: Dictionary = e.get("payload", {})
				if p.get("vector") is Array:
					var v: Array = p["vector"]
					p["vector"] = Vector3(v[0], v[1], v[2])
				_ctx.crew.handle_event(e, StationFixture.NOW_MS - 2000)


func _exit_tree() -> void:
	LayoutMode.forced = -1
	get_tree().root.content_scale_factor = 1.0
