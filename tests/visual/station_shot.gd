## Station widgets for the L5 harness (#7): builds tests/stations/station_fixture.gd's
## context and shows one view of it, set from shots.json: "screen" (the StationScreen
## of `seat`), "lobby", "menu" or "menu_web" (the main menu, with or without the Host
## section), "training" (the Training picker), "callouts" (its Callouts quiz; `quiz_pick`
## answers the first question) or "radar" (the disc radar alone, large). Extras: `selected`
## (a contact id, -1 none), `ping` (a contact id pinged a second ago, -1 none),
## `overlay` (the menu on its Controls tab; `controls_view` picks its view, a ControlsPane.VIEW_),
## `menu_tab` (the menu on that tab), `tooltip` (the first visit: it
## opens by itself), `strip` (the radar's side strip) and
## `ui_scale` (the window's content scale, FT-STN-013; reset on exit), `claim` (a
## claim item the player holds, e.g. "mount:0") and `events` (sim events fed to the
## crew model 2 s before the shot, after the screen is built; a payload `vector` given
## as [x, y, z] becomes a Vector3), `focus` (the focused panel of a joint view, F1 = 0),
## `science` (a Science block with the cards, a scan or a hack open) and `touch` (the touch
## layout whatever the pointer; a viewport under 600 px is a phone anyway, D195) and `comms`
## (CommsFixture's COMMS block is on every shot; "trade" also opens Kappa's offer card,
## "conversation" the hail, "off" leaves the block out). Phones (#28): `insets` simulates a
## device's safe-area insets [left, top, right, bottom] in px (SafeArea.simulate; the
## mockups' iPhone: [47, 0, 47, 21] in landscape, [0, 47, 0, 34] upright) and draws them
## with the gesture band in translucent red; `fullscreen` forces the fullscreen button
## (1 shown, 0 hidden); `audit` writes TapAudit.check of the shot as JSON to that path.
## The lobby's `host_bind` makes it the host's (its join strip and dialog, #35 A6), and
## `player` sets the player's saved name ("" shows the name prompt, #35 A5).
## `render_3d` sets the 3D resolution setting (a RenderQuality mode, default "full").
## `comfort` turns the comfort switch on, `advanced` opens its Advanced group, `menu_scroll`
## scrolls the menu's tab to a node (e.g. "ChangeKeys").
## The "touch_kit" view shows the shared touch widgets (presentation/touch/) on a radar:
## overlay rails with a throttle, sticks, tabs and an open drawer; `docked` docks them.
extends Control

## The lesson step each station shows in a lesson shot: [intent, text].
const LESSON_STEPS: Dictionary = {
	"helm": ["face", "Face the drone."],
	"weapons": ["fire", "Fire at the drone."],
	"engineering": ["pip_add", "Add a power pip."],
	"science": ["sci_scan", "Scan the drone."],
	"relay": ["probe_launch", "Launch a probe."],
	"comms": ["comms_hail", "Hail the drone."],
	"captain": ["captain_view_2", "Show view 2 on the main screen."],
}

var view: String = "screen"
var seat: String = "science"
var selected: int = StationFixture.H2
var ping: int = -1
var overlay: bool = false
var controls_view: String = ""
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
var comms: String = "board"
## Simulated safe-area insets [l, t, r, b] in px; [] none.
var insets: Array = []
## FullscreenButton.forced for the shot.
var fullscreen: int = 0
## Where to write the TapAudit report (JSON); "" none.
var audit: String = ""
## The touch_kit view's rails are docked.
var docked: bool = false

## The game was started with --dev (ClientSettings.dev_flag): the menu's Dev checkbox and the
## lobby's dev seat show (#35 A7).
var dev: bool = false
## The host's bind address in the lobby ("" a joined player's lobby).
var host_bind: String = ""
## The player's saved name.
var player: String = "Ana"

## A Shakedown step on the focused station's banner (a solo lesson step, D303).
var lesson: bool = false
## The intent of the lesson step ("" the station's default one), e.g. "align" (D1).
var lesson_intent: String = ""
## The device the player last used: "" the fixture's, "pad" or "kbm" (the banner and the chip
## follow it, D1, D4).
var device: String = ""
var render_3d: String = "full"
## The menu's comfort switch is on; `advanced` also opens its Advanced group (ux-17).
var comfort: bool = false
var advanced: bool = false
## A node of the open menu tab to scroll into view, e.g. "ChangeKeys" (ux-18); "" none.
var menu_scroll: String = ""
## The "callouts" view (the Training picker's Callouts quiz): the option picked on its first
## question, -1 none.
var quiz_pick: int = -1

var _ctx: StationContext


func _ready() -> void:
	LayoutMode.forced = LayoutMode.Kind.TOUCH if touch else -1
	SafeArea.simulate(insets)
	FullscreenButton.forced = fullscreen
	ClientSettings.dev_flag = dev
	RotateBanner.dismissed_here = false
	I18n.apply("en")
	LayoutMode.apply(get_tree().root)
	get_tree().root.content_scale_factor = ui_scale
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ctx = StationFixture.context(seat, "user://l5_station_shot.cfg")
	_ctx.settings.render_3d = render_3d
	RenderQuality.apply(_ctx.settings, LayoutMode.is_touch(LayoutMode.kind_of(self)), get_tree())
	if lesson:
		var step: Array = LESSON_STEPS.get(seat, ["face", "Face the drone."])
		if lesson_intent != "":
			step = [lesson_intent, "Align a mount to the target."]
		_ctx.training[seat] = {
			"line": "shakedown.%s.%s" % [seat, step[0]],
			"intent": step[0],
			"text": "%s {binding:%s}" % [step[1], step[0]],
			"example": "train.ex." + step[0],
			"done": false,
		}
	if device != "":
		_ctx.matcher.device = device
	if science != "":
		_ctx.snap.blocks[StationCatalogue.Section.SCIENCE] = ScienceShotBlocks.block(science)
	if comms != "off":
		CommsFixture.install(_ctx)
	if tooltip:
		_ctx.settings.reset_hints()
	if claim != "":
		_ctx.crew.claims[claim] = {"session": StationFixture.SESSION, "name": "Ana"}
	if selected >= 0:
		_ctx.crew.select("contact", selected)
	if ping >= 0:
		var p: Dictionary = {"ship": 0, "kind": "contact", "id": ping, "by": "Bo"}
		_ctx.crew.handle_event({"type": "ping", "payload": p}, StationFixture.NOW_MS - 1000)
	match view:
		"menu", "menu_web":
			var m: MainMenu = MainMenu.new()
			m.web = view == "menu_web"
			m.binds = MainMenu.order_binds(["192.168.1.20"])
			m.settings = ClientSettings.new("user://l5_menu.cfg")
			m.settings.player_name = "Ana"
			m.token_path = "user://l5_menu_none.token"
			m.pid_path = "user://l5_menu_none.pid"
			add_child(m)
		"training", "callouts":
			var picker_menu: MainMenu = MainMenu.new()
			picker_menu.web = true
			picker_menu.settings = ClientSettings.new("user://l5_menu_training.cfg")
			picker_menu.settings.player_name = "Ana"
			picker_menu.settings.lessons_done = {"weapons": true, "science": true}
			picker_menu.token_path = "user://l5_menu_none.token"
			picker_menu.pid_path = "user://l5_menu_none.pid"
			add_child(picker_menu)
			picker_menu.open_training()
			if view == "callouts":
				picker_menu.open_callouts()
				if quiz_pick >= 0:
					picker_menu._quiz.pick(quiz_pick)
		"lobby":
			_ctx.crew.lobby[0]["started"] = false
			_ctx.crew.lobby[0]["ready"] = false
			_ctx.crew.lobby[0]["crew"] = 2
			_ctx.crew.lobby[0]["uncovered"] = ["relay", "comms"]
			_ctx.crew.lobby[0]["seats"] = [
				{"seat": "helm", "name": "Ana"},
				{"seat": "weapons", "name": "Bo"},
				{"seat": "systems", "name": "Cy"},
			]
			if seat == StationCatalogue.ALL:
				# The dev seat covers every station and needs no other crew (FT-NET-029).
				_ctx.crew.lobby[0]["uncovered"] = []
				_ctx.crew.lobby[0]["ready"] = true
			_ctx.host_bind = host_bind
			# The host's lobby: its join strip and its End game button (C1, D353).
			_ctx.crew.host = host_bind != ""
			_ctx.host_port = NetProtocol.DEFAULT_WS_PORT
			_ctx.settings.player_name = player
			var l: LobbyScreen = LobbyScreen.new()
			l.setup(_ctx)
			add_child(l)
		"touch_kit":
			_touch_kit()
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
						_ctx.settings.bindings, s.stations, _ctx.matcher.device, _ctx.crew.seat
					)
					menu.open(SettingsScreen.TAB_CONTROLS)
			)
			s.card_requested.connect(
				func() -> void:
					s.help_requested.emit()
					menu.controls_pane.show_view(ControlsPane.VIEW_CARD)
			)
			add_child(menu)
			_ctx.settings.comfort = comfort
			menu.setup(_ctx.settings, true)
			add_child(s)
			move_child(menu, -1)
			s.focus(focus)
			if comms in ["trade", "conversation"]:
				var panel: CommsPanel = s.panels[s.stations.find("comms")] as CommsPanel
				panel.open_card(CommsFixture.OFFER if comms == "trade" else CommsFixture.HAIL)
			s.radar.side_strip = strip
			if overlay:
				s.help_requested.emit()
				if controls_view != "":
					menu.controls_pane.show_view(controls_view)
			if menu_tab != "":
				# As ClientShell.open_menu: the Controls tab is set for the screen's seat.
				menu.set_controls(
					_ctx.settings.bindings, s.stations, _ctx.matcher.device, _ctx.crew.seat
				)
				menu.open(menu_tab)
				if advanced:
					(menu.find_child("Advanced", true, false) as Button).button_pressed = true
				if menu_scroll != "":
					_scroll_menu.call_deferred(menu)
			for e: Dictionary in events:
				var p: Dictionary = e.get("payload", {})
				if p.get("vector") is Array:
					var v: Array = p["vector"]
					p["vector"] = Vector3(v[0], v[1], v[2])
				_ctx.crew.handle_event(e, StationFixture.NOW_MS - 2000)
	if not insets.is_empty():
		var shade: InsetShade = InsetShade.new()
		shade.insets = insets
		add_child(shade)
	if audit != "":
		_write_audit.call_deferred()


## Scrolls the menu's open tab so `menu_scroll` is at its top.
func _scroll_menu(menu: SettingsScreen) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var tab: ScrollContainer = menu.tabs.get_current_tab_control() as ScrollContainer
	var target: Control = menu.find_child(menu_scroll, true, false) as Control
	if tab != null and target != null:
		tab.scroll_vertical = int(target.global_position.y - tab.global_position.y)


## The touch widgets in the three rail patterns' parts (#28): a radar as the view, a
## throttle, All stop, Approach and a Radar drawer on the left, Nav / Shield tabs and a
## stick on the right.
func _touch_kit() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var frame: Control = Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var m: Vector4 = SafeArea.margins(self)
	frame.offset_left = m.x
	frame.offset_top = m.y
	frame.offset_right = -m.z
	frame.offset_bottom = -m.w
	var layout: RailLayout = RailLayout.new()
	layout.docked = docked
	frame.add_child(layout)
	var r: DiscRadar = DiscRadar.new()
	r.set_picture(_ctx.picture(), _ctx.crew.selection)
	layout.set_content(r)
	var left: TouchRail = layout.rail(SIDE_LEFT)
	var throttle: ThrottleSlider = ThrottleSlider.new()
	throttle.value = 0.8
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(RailButton.make("All stop", RailButton.Role.DANGER))
	col.add_child(RailButton.make("Approach"))
	var opener: RailButton = RailButton.make("Radar")
	col.add_child(opener)
	var row: HBoxContainer = left.add_row([throttle, col])
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	throttle.size_flags_horizontal = Control.SIZE_FILL
	left.custom_minimum_size.x = 176.0
	var drawer: TouchDrawer = layout.add_drawer(TouchDrawer.new("Contacts", SIDE_LEFT))
	var list: Label = Label.new()
	list.text = "U3  8.0 km\nKappa  4.7 km"
	drawer.body.add_child(list)
	drawer.bind_opener(opener)
	drawer.open()
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.add(FullscreenButton.new())
	right.add_spacer()
	var stick: VirtualStick = VirtualStick.new()
	stick.label = "Slide"
	right.add(stick)
	right.custom_minimum_size.x = 136.0


## Writes the TapAudit report once the layout has settled (rects as [x, y, w, h]).
func _write_audit() -> void:
	for i: int in 3:
		await get_tree().process_frame
	var report: Dictionary = TapAudit.check(self)
	var rows: Array = []
	for t: Dictionary in report["targets"]:
		var r: Rect2 = t["rect"]
		rows.append(
			{
				"kind": t["kind"],
				"text": t["text"],
				"rect": [r.position.x, r.position.y, r.size.x, r.size.y]
			}
		)
	report["targets"] = rows
	var f: FileAccess = FileAccess.open(audit, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))


## The simulated insets and the gesture band, drawn over the shot (translucent red).
class InsetShade:
	extends Control
	var insets: Array = []

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 100

	func _draw() -> void:
		var tint: Color = Color(1.0, 0.25, 0.25, 0.12)
		var l: float = insets[0]
		var t: float = insets[1]
		var r: float = insets[2]
		var b: float = insets[3]
		draw_rect(Rect2(0, 0, l, size.y), tint)
		draw_rect(Rect2(size.x - r, 0, r, size.y), tint)
		draw_rect(Rect2(0, 0, size.x, t), tint)
		var band: float = SafeArea.tap_band(self)
		draw_rect(Rect2(0, size.y - band, size.x, band), tint)


func _exit_tree() -> void:
	SafeArea.simulate([])
	ClientSettings.dev_flag = false
	FullscreenButton.forced = -1
	LayoutMode.forced = -1
	get_tree().root.content_scale_factor = 1.0
