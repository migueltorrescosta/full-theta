class_name StationScreen
extends Control
## A station screen (§5.0, §5.9, FT-JNT-001, FT-JNT-007): the top bar, one disc radar and
## one or more StationPanels, one focused. A single station is a screen with one panel;
## a joint view is the same screen with two (the dev seat six). The focused panel
## fills the main area; the others sit docked, compact, under the radar. F1/F2, hold
## View + LB/RB, or a click on a docked panel moves the focus.
##
## Input: every InputEvent goes through ctx.matcher (input/), which knows the screen's
## stations and the focused one; each intent event goes to its target
## (IntentTable.target): "screen" for the common actions and the station-less live set,
## else the panel of that station (the focused one, or any for intents live on the
## device). The common actions act on the shared selection, marks and pings in
## ctx.crew (FT-STN-009, FT-STN-003).

## Menu (Esc / Menu): the shell opens the menu.
signal menu_requested
## The viewport changed form (a rotation, a resize past a phone's size; LayoutMode.Form):
## panels with phone layouts rearrange (#28).
signal form_changed(form: LayoutMode.Form)
## `?` / View, or the first visit to a station: the shell opens the menu on Controls.
signal help_requested
## The callout legend hint's tap (D369): the shell opens the callout card on Controls.
signal card_requested

## Intents that still reach the screen while it is blocked: they close what blocks it.
const UNBLOCKED: Array[String] = ["menu", "overlay"]

## Panel column width and radar size (before UI scale).
const SIDE_WIDTH: float = 340.0
const RADAR_HEIGHT: float = 300.0
## A short or narrow viewport (a 720p window at 150 % UI scale is 853 x 480) gets a
## smaller radar and a narrower column, so the share buttons fit under it and Relay's map
## keeps its width.
const SHORT_H: float = 560.0
const SHORT_RADAR: float = 220.0
const SHORT_SIDE_WIDTH: float = 280.0
const TOP_BAR_HEIGHT: float = 40.0
## The least gap (px) between the rows and the screen's bottom edge: the last row of a
## panel keeps its borders (#12).
const EDGE_GAP: float = 6.0
## The bar of the touch layouts: tap-sized alert chip and sound button (D194).
const TOUCH_BAR_HEIGHT: float = 52.0
## A phone's bar: the chip and sound button are primary targets (48 px, #28).
const PHONE_BAR_HEIGHT: float = 56.0
## The bar when it holds the full-screen icon (48 px and the bar's 8 px margins, D323).
const FULLSCREEN_BAR_HEIGHT: float = 56.0
## Under this width the top bar takes two rows (a phone, a tablet upright).
const COMPACT_WIDTH: float = 900.0
## Between a tablet's side rails the top bar takes two rows under this width.
const DOCK_COMPACT_WIDTH: float = 760.0
## A phone's smaller bar text fits one row down to this width.
const COMPACT_PHONE_WIDTH: float = 480.0
## The phone's radar column: a smaller disc (D195).
const PHONE_RADAR: float = 180.0
const PHONE_SIDE_WIDTH: float = 180.0
## Least height of a docked panel: top bar, radar and one docked panel fit 720p at
## 150 % UI scale (480 px), so the screen never grows past the window.
const DOCK_MIN_HEIGHT: float = 120.0
const SCROLL_BAR_WIDTH: float = 14.0
## More panels than this (the dev seat's six) get a tab strip; Shift + 1..9 picks a panel
## (the bare digits and Alt + digit belong to the stations' own keys).
const TABS_FROM: int = 3
const TAB_HINT_KEY: String = "dev_tabs"

var ctx: StationContext
## Station ids of the panels, in order (F1, F2, ...).
var stations: Array[String] = []
var panels: Array[StationPanel] = []
var focus_index: int = 0
var top_bar: TopBar
var radar: DiscRadar
var toasts: Toasts
var alerts: StationAlerts
var flash: AlertFlash
## The critical tier's banner (C5): hull critical, a fault, shields down, a missile lock.
var critical: CriticalBanner
var chip_strip: ChipStrip
var share_bar: ShareBar
var training: TrainingBanner
## The quiet gap's Ready card (gp-07).
var gap: GapBanner
## Makes the panel of a station; tests swap it (default StationRegistry.make).
var panel_factory: Callable = StationRegistry.make
## Controls of the shell that take the input while visible (Settings, the outcome card).
var blockers: Array[Control] = []
## The viewport's form (LayoutMode.Form), kept by the layout; panels read it.
var form: LayoutMode.Form = LayoutMode.Form.DESKTOP
## Show the "turn sideways" banner on a phone held upright (#28).
var rotate_prompt: bool = true
var rotate_banner: RotateBanner
## The station chip on a phone (#28 follow-up, P28-Joint, P28-Dev): a joint view's switch to
## its other station ("⇄ Weapons"), the dev seat's station button ("Helm ▾") that opens the
## six-station sheet. It leads the page tabs: in the top bar on its side, in the bottom tab
## bar upright. Null until a phone shows one.
var joint_switch: RailButton = null
## The phone frame (#28 follow-up, PhoneFrame): shown only on phones, so tablets and
## desktops keep their layout. `phone` is set by the layout.
var phone: bool = false
var frame: PhoneFrame = PhoneFrame.new()
## The focused panel's docked touch rails on a tablet (#32, TabletDock), or null. The panel
## makes and frees it; the screen reserves its room and places it.
var tablet_dock: TabletDock = null
## One-level choices: the selection, alert and dev-station sheets, and the panels' (Hack).
var sheet: ChoiceSheet

## The layout half and the common crew actions (R13-1); both keep a pointer back to this screen.
var layout: StationScreenLayout = StationScreenLayout.new(self)
var common: StationCommonActions = StationCommonActions.new(self)

var _rows: VBoxContainer
var _main: Control
var _dock: VBoxContainer
## The radar and the extras column (share buttons, docked panels): beside the main area
## in landscape, below it in portrait (D216); it hides for a lone full-screen panel.
var _side: BoxContainer
var _body: BoxContainer
var _extras: VBoxContainer
var _side_margin: MarginContainer
var _side_scroll: ScrollContainer
var _blocked: bool = false
var _extras_pad: Control
## The dev seat's station tabs (one button per panel) and its one-line hint; null when the
## screen holds one or two panels.
var _tabs: HFlowContainer
var _hint: Label
## The gesture band's height inside the main area on a phone on its side, where the view
## draws into the band (0 elsewhere); the side column keeps its controls above it.
var _band_h: float = 0.0
var _side_band: Control
## Seconds left of each share seen last frame (_push_notes), and the request chips' lapse rule.
var _share_left: Dictionary = {}
var _lapse: ChipLapse = ChipLapse.new()


## Builds the screen for the current pick (ctx.crew.seat_def()). Seats without
## functional stations (Captain, Viewer) get one panel of their own id.
func setup(context: StationContext) -> void:
	ctx = context
	# The matcher outlives screens: a screen freed while blocked (the outcome card before a
	# run reset) left it restricted.
	ctx.matcher.restrict([])
	var def: Dictionary = ctx.crew.seat_def()
	for s: Variant in def.get("stations", []):
		stations.append(str(s))
	if stations.is_empty():
		stations.append(ctx.crew.seat)
	layout.build()
	layout.relayout()
	for s: String in stations:
		var p: StationPanel = panel_factory.call(s)
		if p == null:
			# (an unknown id: StationRegistry.make has reported it; keep `panels` parallel to `stations`)
			p = StationPanel.new()
		p.sheet = sheet
		p.common_requested.connect(common.on_panel_common)
		p.setup(ctx, s)
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.gui_input.connect(_on_panel_input.bind(p))
		panels.append(p)
	ctx.crew.toast.connect(_on_toast)
	ctx.crew.pinged.connect(frame.on_pinged)
	critical = CriticalBanner.new()
	add_child(critical)
	alerts = StationAlerts.new()
	add_child(alerts)
	alerts.setup(ctx, stations, toasts, flash, critical)
	# the Shakedown's step banner and Next (FT-MIS-039).
	training = TrainingBanner.new()
	training.station = stations[0]
	add_child(training)
	training.setup(ctx)
	gap = GapBanner.new()
	add_child(gap)
	gap.setup(ctx)
	Input.joy_connection_changed.connect(_on_joy_changed)
	layout.build_tabs()
	focus(0)
	rotate_banner.settings = ctx.settings
	rotate_banner.refresh()


func _ready() -> void:
	get_viewport().size_changed.connect(layout.relayout)
	layout.relayout()
	_open_first_visit_help()


func focused_station() -> String:
	return stations[focus_index] if focus_index < stations.size() else ""


func focused_panel() -> StationPanel:
	return panels[focus_index] if focus_index < panels.size() else null


## Moves the focus to panel i (FT-JNT-001): it takes the main area and its station's
## bindings; the others dock.
func focus(i: int) -> void:
	if i < 0 or i >= panels.size():
		return
	# Held intents end on the panels that had them (a held fire doesn't stick).
	release_all()
	focus_index = i
	for j: int in panels.size():
		var p: StationPanel = panels[j]
		var parent: Control = _main if j == i else _dock
		if p.get_parent() != parent:
			if p.get_parent() != null:
				p.get_parent().remove_child(p)
			parent.add_child(p)
		if j == i:
			p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		else:
			p.custom_minimum_size = Vector2(0, DOCK_MIN_HEIGHT)
		p.set_mode(j == i, j != i)
	ctx.matcher.set_context(stations, focused_station())
	if training != null:
		training.station = focused_station()
	radar.orbitable = focused_panel().radar_orbitable()
	layout.raise_overlays()
	layout.apply_band()
	layout.show_side()
	if _tabs != null:
		layout.show_tabs()
	_open_first_visit_help()


## A panel built or dropped its phone pages after the screen laid out: binds the focused
## panel's tabs again (PageHost, `pages`).
func pages_changed() -> void:
	layout.show_side()


## Docks `dock` (a panel's tablet rails) over the screen's edges, or lets the old one go with
## null. The rows shrink by what it reserves; the panel keeps ownership of the node.
func set_tablet_dock(dock: TabletDock) -> void:
	if dock == tablet_dock:
		return
	if tablet_dock != null and tablet_dock.get_parent() == self:
		remove_child(tablet_dock)
	tablet_dock = dock
	if dock != null:
		add_child(dock)
	layout.relayout()


## Shift + 1..N focuses panel N while the tab strip exists.
func _tab_hotkey(event: InputEvent) -> bool:
	var k: InputEventKey = event as InputEventKey
	if (
		_tabs == null
		or k == null
		or not k.pressed
		or k.echo
		or not k.shift_pressed
		or k.alt_pressed
		or k.ctrl_pressed
	):
		return false
	var i: int = (k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode) - KEY_1
	if i < 0 or i >= panels.size():
		return false
	focus(i)
	return true


## Routes one intent event (InputMatcher's dictionary); true when something handled
## it. Public so tests can drive the screen without devices.
func dispatch(ev: Dictionary) -> bool:
	var target: String = str(ev.get("target", ""))
	if target == "screen":
		return common.run(ev)
	var i: int = stations.find(target)
	return i >= 0 and panels[i].handle_intent(ev)


## Feeds a device event through the matcher and dispatches what it completes. A select
## that found an item under the pointer consumes the batch, so the same click doesn't
## also fire a panel binding (LMB is select and Weapons fire, provisional).
func feed(event: InputEvent) -> void:
	_update_block()
	if not _blocked and _tab_hotkey(event):
		return
	if event is InputEventMouseMotion and not focused_panel().mouse_steers():
		return
	var batch: Array[Dictionary] = ctx.matcher.feed(event, ctx.now_ms())
	_dispatch_batch(batch)


func _input(event: InputEvent) -> void:
	if phone and frame.input(event):
		get_viewport().set_input_as_handled()
		return
	if _gui_owns(event):
		return
	feed(event)


func _process(delta: float) -> void:
	_update_block()
	_dispatch_batch(ctx.matcher.update(ctx.now_ms(), delta))
	var now: int = ctx.now_ms()
	top_bar.can_set_alert = ctx.crew.is_crew()
	var status: Dictionary = ctx.snap.blocks.get(StationCatalogue.Section.STATUS, {})
	var captain: Dictionary = ctx.snap.blocks.get(StationCatalogue.Section.CAPTAIN, {})
	top_bar.show_goal(StatusView.goal_text(captain, status), StatusView.goal_short(captain, status))
	top_bar.show_state(
		ctx.crew.ship_name(),
		status,
		ctx.crew.alert,
		stations,
		ctx.crew.mission_seconds(ctx.snap.tick),
		focused_station(),
		_maxes(),
		ctx.crew.summaries(status, ctx.ship_def())
	)
	radar.set_picture(ctx.picture(), ctx.crew.selection, ctx)
	radar.blip_scale = focused_panel().blip_scale()
	toasts.update(now)
	flash.update(now)
	critical.update(now)
	var card: FirstSeatCard = first_seat_card()
	if card != null:
		# Over the focused panel's view, clear of its rails and the rest of the HUD columns,
		# and on a phone under the frame's view-top row (the selection chip, Ask).
		var p: StationPanel = focused_panel()
		var view: Rect2 = p.view_rect()
		view.position += p.global_position - global_position
		if frame.framed():
			view = view.grow_side(SIDE_TOP, -p.top_reserve)
		card.bounds = view
	var spot: Rect2 = _notice_rect()
	toasts.place(spot)
	if critical.visible:
		critical.place(spot)
	var left: Dictionary = ctx.crew.shares_left(now)
	# A phone shows request chips only at the top of the view (ux-13); elsewhere, the strip.
	if phone:
		frame.process(now)
		chip_strip.visible = false
	else:
		frame.view_top.visible = false
		chip_strip.show_chips(
			ChipsReader.incoming(ctx.snap, stations),
			ChipsReader.outgoing(ctx.snap, stations),
			ctx.snap
		)
	_push_notes(now, left)
	# A phone panel with its shares on its Crew page shows no second set beside the radar.
	var none: Array[StringName] = []
	var own: bool = phone and focused_panel().shows_shares
	share_bar.show_features(none if own else common.shareable(), left)


## Where the toasts and the critical banner show (C5, D319), in the screen's coordinates: the
## top bar's free stretch on a desktop or a tablet (TopBar.notice_rect), so the ship's name,
## hull, shields and power stay in view. A phone's bar has no stretch to spare: its glance
## and the room after it, up to the page tabs or the alert chip, for the few seconds a notice
## shows.
func _notice_rect() -> Rect2:
	var origin: Vector2 = get_global_rect().position
	var spot: Rect2 = top_bar.notice_rect()
	if phone:
		var end: float = INF
		for c: Control in [top_bar.tabs, top_bar.chip]:
			var r: Rect2 = c.get_global_rect()
			var empty: bool = c == top_bar.tabs and not top_bar.tabs.has_content()
			if c.is_visible_in_tree() and not empty and r.position.x > spot.position.x:
				end = minf(end, r.position.x - UiTheme.TOUCH_GAP)
		if end < INF:
			spot.size.x = maxf(spot.size.x, end - spot.position.x)
		# The bar's height, as its menu button's, so a toast has room for two lines.
		var row: Rect2 = top_bar.menu_button.get_global_rect()
		spot.position.y = row.position.y
		spot.size.y = row.size.y
	spot = spot.intersection(get_global_rect())
	return Rect2(spot.position - origin, spot.size)


## The notes of the toast queue (C5, ux-14): a partner's shared data when its share starts or
## is renewed (the seconds count down while the toast shows), and a request chip that lapsed
## unanswered.
func _push_notes(now: int, left: Dictionary) -> void:
	var lines: Dictionary[StringName, String] = ShareBar.incoming(stations, left)
	var seen: Dictionary = {}
	for id: StringName in lines:
		var key: String = "share:" + String(id)
		var seconds: float = float(left[id])
		if seconds > float(_share_left.get(id, 0.0)) + 0.5 or toasts.has_key(key):
			toasts.push(lines[id], "note", now, key)
		seen[id] = seconds
	_share_left = seen
	if not ctx.crew.is_crew():
		return
	var open: Array = []
	for c: Dictionary in ChipsReader.incoming(ctx.snap, stations):
		open.append(
			{"id": c["id"], "text": ChipStrip.asker(c), "left": ChipsReader.time_left(ctx.snap, c)}
		)
	for note: String in _lapse.update(open):
		toasts.push(note, "note", now)


## The own ship's hull and shield maxima (J), for the top bar's percentages.
func _maxes() -> Dictionary:
	var def: ShipDef = ctx.ship_def()
	if def == null:
		return {}
	return {
		"hull": def.hull_max, "shields": def.shields.max_strength if def.shields != null else 0.0
	}


## Releases every held and toggled intent where it was held (focus loss, a pad coming
## or going, a popup).
func release_all() -> void:
	_dispatch_batch(ctx.matcher.release_all())


## A pad came or went: forget its sticks and buttons.
func _on_joy_changed(_pad: int, _connected: bool) -> void:
	release_all()


func _notification(what: int) -> void:
	if (
		ctx != null
		and what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]
	):
		release_all()


## True while the menu, the outcome card or the alert picker is up.
func blocked() -> bool:
	return top_bar.picker.visible or blockers.any(func(c: Control) -> bool: return c.visible)


## On blocking: release everything and keep only UNBLOCKED active; on unblocking, all.
func _update_block() -> void:
	if blocked() == _blocked:
		return
	_blocked = not _blocked
	release_all()
	ctx.matcher.restrict(UNBLOCKED if _blocked else [])


func _dispatch_batch(batch: Array[Dictionary]) -> void:
	var consumed: bool = false
	for ev: Dictionary in batch:
		if consumed and ev.get("target", "") != "screen":
			# The press never reached its panel: undo its hold or toggle flip.
			ctx.matcher.cancel(ev["id"])
			continue
		if dispatch(ev) and ev["id"] == "select":
			consumed = true


# --- Common actions (StationCommonActions, §5.0). ---

# --- The phone frame (#28 follow-up, PhoneFrame). ---


## True when the screen uses the phone frame: a phone-sized viewport (LayoutMode PHONE, as
## the stations' phone layouts), either way up.
func phone_frame() -> bool:
	return is_inside_tree() and LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE


## The menu button: the shell opens the menu, as Esc does.
func _open_menu() -> void:
	if sheet.is_open():
		sheet.cancel()
	menu_requested.emit()
	_update_block()


## A player's first seat at a station shows its first-seat card (FirstSeatCard, C7): the
## station's three core lesson actions in the device's words and a pointer to Training ›
## Callouts, until the player closes it; once per client and station (amends FT-STN-012,
## D185, D369). Help never opens by itself: the card's Controls button opens the menu's
## Controls tab. Settings re-enables it. A joint view's other station gets its own card on its
## first focus, in place of the first one. The first station waits for the screen to enter
## the tree, so the shell has connected `help_requested` by then.
func _open_first_visit_help() -> void:
	if not is_inside_tree():
		return
	var touch: bool = LayoutMode.is_touch(LayoutMode.kind_of(self))
	if not ctx.settings.hint_seen(focused_station()):
		var old: FirstSeatCard = first_seat_card()
		if old != null:
			remove_child(old)
			old.queue_free()
	var card: FirstSeatCard = FirstSeatCard.show_once(
		self, ctx.settings, focused_station(), ctx.matcher.device, touch
	)
	if card == null:
		return
	card.controls_requested.connect(
		func() -> void:
			card.dismiss()
			help_requested.emit()
	)


## The open first-seat card, or null.
func first_seat_card() -> FirstSeatCard:
	for c: Node in get_children():
		if c is FirstSeatCard and not c.is_queued_for_deletion():
			return c
	return null


func _on_toast(key: String, args: Dictionary) -> void:
	var text: String = tr(key)
	if text == key:
		text = tr("toast.rejected") % key.trim_prefix("toast.")
	var kind: String = "info" if key in ["toast.rate_limited", "toast.priority"] else "warn"
	toasts.push(text.format(args), kind, ctx.now_ms())


## A click on a docked panel focuses it (FT-JNT-001: "tap the panel").
func _on_panel_input(event: InputEvent, p: StationPanel) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and p.docked:
		focus(panels.find(p))
		accept_event()


## Events a GUI widget owns: typing in a text field and clicks on buttons.
func _gui_owns(event: InputEvent) -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	if event is InputEventKey and vp.gui_get_focus_owner() is LineEdit:
		return true
	# A finger on a rail, stick or drawer (and the mouse Godot makes from it, #28).
	if TouchInput.owns(get_tree(), event):
		return true
	if event is InputEventMouseButton:
		var hovered: Control = vp.gui_get_hovered_control()
		return hovered is BaseButton
	return false
