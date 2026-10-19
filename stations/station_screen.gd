class_name StationScreen
extends Control
## A station screen (§5.0, §5.9, FT-JNT-001, FT-JNT-007): the top bar, one disc radar and
## one or more StationPanels, one focused. A single station is a screen with one panel;
## a joint view is the same screen with two (the dev entry six). The focused panel
## fills the main area; the others sit docked, compact, under the radar. F1/F2, hold
## View + LB/RB, or a click on a docked panel moves the focus.
##
## Input: every InputEvent goes through ctx.matcher (input/), which knows the screen's
## stations and the focused one; each intent event goes to its target
## (IntentTable.target): "screen" for the common actions and the station-less live set,
## else the panel of that station (the focused one, or any for intents live on the
## device). The common actions act on the shared selection, marks and pings in
## ctx.crew (FT-STN-009, FT-STN-003).

## Menu (Esc / Menu): the shell opens Settings.
signal menu_requested

## Panel column width and radar size (before UI scale).
const SIDE_WIDTH: float = 340.0
const RADAR_HEIGHT: float = 300.0
const TOP_BAR_HEIGHT: float = 40.0
## Least height of a docked panel: top bar, radar and one docked panel fit 720p at
## 150 % UI scale (480 px), so the screen never grows past the window.
const DOCK_MIN_HEIGHT: float = 120.0

var ctx: StationContext
## Station ids of the panels, in order (F1, F2, ...).
var stations: Array[String] = []
var panels: Array[StationPanel] = []
var focus_index: int = 0
var top_bar: TopBar
var radar: DiscRadar
var toasts: Toasts
var overlay: ControlsOverlay
var tooltip: FirstRunTooltip
var alerts: StationAlerts
var flash: AlertFlash
## Makes the panel of a station; tests swap it (default StationRegistry.make).
var panel_factory: Callable = StationRegistry.make

var _main: Control
var _dock: VBoxContainer
var _side: VBoxContainer


## Builds the screen for the current pick (ctx.crew.entry_def()). Entries without
## functional stations (Captain, Viewer) get one panel of their own id.
func setup(context: StationContext) -> void:
	ctx = context
	var def: Dictionary = ctx.crew.entry_def()
	for s: Variant in def.get("stations", []):
		stations.append(str(s))
	if stations.is_empty():
		stations.append(ctx.crew.entry)
	_build()
	for s: String in stations:
		var p: StationPanel = panel_factory.call(s)
		p.setup(ctx, s)
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		p.gui_input.connect(_on_panel_input.bind(p))
		panels.append(p)
	ctx.crew.toast.connect(_on_toast)
	alerts = StationAlerts.new()
	add_child(alerts)
	alerts.setup(ctx, stations, toasts, flash)
	ctx.settings.bindings.changed.connect(_refresh_overlay)
	focus(0)


func focused_station() -> String:
	return stations[focus_index] if focus_index < stations.size() else ""


func focused_panel() -> StationPanel:
	return panels[focus_index] if focus_index < panels.size() else null


## Moves the focus to panel i (FT-JNT-001): it takes the main area and its station's
## bindings; the others dock.
func focus(i: int) -> void:
	if i < 0 or i >= panels.size():
		return
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
	ctx.matcher.release_all()
	ctx.matcher.set_context(stations, focused_station())
	radar.orbitable = focused_panel().radar_orbitable()
	_side.visible = not (panels.size() == 1 and focused_panel().full_screen())
	_show_tooltip()
	_refresh_overlay()


## Routes one intent event (InputMatcher's dictionary); true when something handled
## it. Public so tests can drive the screen without devices.
func dispatch(ev: Dictionary) -> bool:
	var target: String = str(ev.get("target", ""))
	if target == "screen":
		return _common(ev)
	var i: int = stations.find(target)
	return i >= 0 and panels[i].handle_intent(ev)


## Feeds a device event through the matcher and dispatches what it completes. A select
## that found an item under the pointer consumes the batch, so the same click doesn't
## also fire a panel binding (LMB is select and Weapons fire, provisional).
func feed(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not focused_panel().mouse_steers():
		return
	var batch: Array[Dictionary] = ctx.matcher.feed(event, ctx.now_ms())
	_dispatch_batch(batch)


func _input(event: InputEvent) -> void:
	if _gui_owns(event):
		return
	feed(event)


func _process(delta: float) -> void:
	_dispatch_batch(ctx.matcher.update(ctx.now_ms(), delta))
	var now: int = ctx.now_ms()
	top_bar.can_set_alert = ctx.crew.is_crew()
	top_bar.show_state(
		ctx.crew.ship_name(),
		ctx.view.blocks.get(StationViews.Section.STATUS, {}),
		ctx.crew.alert,
		stations,
		ctx.crew.mission_seconds(ctx.view.tick),
		focused_station()
	)
	radar.set_items(ContactPicture.build(ctx), ctx.crew.selection)
	toasts.update(now)
	flash.update(now)


func _dispatch_batch(batch: Array[Dictionary]) -> void:
	var consumed: bool = false
	for ev: Dictionary in batch:
		if consumed and ev.get("target", "") != "screen":
			continue
		if dispatch(ev) and ev["id"] == "select":
			consumed = true


# --- Common actions (§5.0). ---


func _common(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)):
		return false
	var id: String = ev["id"]
	var device: String = str(ev.get("device", IntentTable.KBM))
	var handled: bool = true
	match id:
		"select":
			handled = _select(device)
		"cycle_target":
			ctx.crew.cycle("contact", contacts_by_range())
		"select_pinged":
			handled = ctx.crew.select_pinged(ctx.now_ms())
		"ping":
			_ping(device)
		"mark":
			_mark(device)
		"accept", "decline":
			handled = focused_panel().handle_intent(ev)
		"request":
			handled = focused_panel().has_request_chip()
			if handled:
				focused_panel().send_request()
		"radar_strip":
			radar.toggle_strip()
		"claim":
			_claim()
		"overlay":
			overlay.visible = not overlay.visible
			_refresh_overlay()
		"menu":
			menu_requested.emit()
		_:
			handled = _live(id)
	return handled


## Select under the pointer; false over nothing, so the click falls through to the
## panel (owner decision in #7: LMB fires in the turret).
func _select(device: String) -> bool:
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty() or item["kind"] == "point":
		return false
	ctx.crew.select(item["kind"], item["id"])
	return true


func _live(id: String) -> bool:
	match id:
		"alert_cycle":
			_set_alert((ctx.crew.alert + 1) % CrewState.ALERT_LEVELS)
		"alert_red":
			_set_alert(CrewState.ALERT_RED)
		"alert_yellow":
			_set_alert(CrewState.ALERT_YELLOW)
		"alert_normal":
			_set_alert(CrewState.ALERT_NORMAL)
		"focus_1", "focus_2":
			var n: int = panels.size()
			if n <= 2:
				focus(0 if id == "focus_1" else 1)
			else:
				focus((focus_index + (n - 1 if id == "focus_1" else 1)) % n)
		_:
			return false
	return true


## The item under the pointer (KB/M: the radar if the mouse is over it, else the focused
## panel at the mouse) or, on a controller, under the focused panel's reticle (its
## centre unless it says otherwise).
func item_under_cursor(device: String) -> Dictionary:
	var p: StationPanel = focused_panel()
	if device == IntentTable.PAD:
		return p.item_at(p.cursor_pos())
	var mouse: Vector2 = get_global_mouse_position()
	if radar.is_visible_in_tree() and radar.get_global_rect().has_point(mouse):
		return radar.item_at(mouse - radar.global_position)
	for q: StationPanel in panels:
		if q.is_visible_in_tree() and q.get_global_rect().has_point(mouse):
			return q.item_at(mouse - q.global_position)
	return {}


## Contact ids but the own ship (snapshots list it too), nearest first (cycle target).
func contacts_by_range() -> Array:
	var ids: Array = Array(ctx.interp.contact_ids())
	ids.erase(ctx.crew.ship)
	var dist: Callable = func(id: int) -> float:
		return ctx.interp.offset_to(ctx.interp.contact_position(id)).length()
	ids.sort_custom(func(a: int, b: int) -> bool: return dist.call(a) < dist.call(b))
	return ids


## Crew only (FT-STN-008); the server refuses others too.
func _set_alert(level: int) -> void:
	if ctx.crew.is_crew():
		ctx.intents.set_alert(level)


## Ping under the cursor, else the selection (FT-SPA-016).
func _ping(device: String) -> void:
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty():
		item = ctx.crew.selection
	if item.is_empty():
		return
	if item["kind"] == "point":
		ctx.intents.ping("point", -1, int(item.get("site", 0)), item["pos"])
	else:
		ctx.intents.ping(item["kind"], int(item["id"]), _site(), Vector3.ZERO)


## Mark at the cursor, or on the selection (FT-SPA-013, FT-SPA-022): refused with a
## toast when the ship has 8 marks, unless the focused panel replaces one (Relay).
func _mark(device: String) -> void:
	if ctx.crew.entry == StationViews.VIEWER:
		return
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty():
		item = ctx.crew.selection
	if item.is_empty():
		return
	if ctx.crew.marks.size() >= CrewState.MAX_MARKS:
		if not focused_panel().replace_mark(item):
			_on_toast("toast.marks_full", {})
		return
	match item["kind"]:
		"contact":
			ctx.intents.place_mark(-1, "", int(item["id"]), _site(), Vector3.ZERO)
		"point":
			ctx.intents.place_mark(-1, "", -1, int(item.get("site", _site())), item["pos"])


## Claim or release the focused panel's claim item.
func _claim() -> void:
	var item: String = focused_panel().claim_item()
	if item == "":
		return
	var holder: Dictionary = ctx.crew.claims.get(item, {})
	if int(holder.get("session", -1)) == ctx.crew.session:
		ctx.intents.release_claim(item)
	else:
		ctx.intents.claim(item)


func _site() -> int:
	return int(ctx.view.kin.get("site", 0))


# --- Layout and widgets. ---


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)
	top_bar = TopBar.new()
	top_bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
	top_bar.alert_picked.connect(_set_alert)
	rows.add_child(top_bar)
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	_main = Control.new()
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main.clip_contents = true
	body.add_child(_main)
	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	body.add_child(side)
	_side = side
	radar = DiscRadar.new()
	radar.custom_minimum_size = Vector2(SIDE_WIDTH, RADAR_HEIGHT)
	side.add_child(radar)
	_dock = VBoxContainer.new()
	_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_dock)
	toasts = Toasts.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# Top-right of the screen (§5.0), over the radar's empty corner, not the panel.
	toasts.offset_left = -16.0
	toasts.offset_right = -16.0
	toasts.offset_top = TOP_BAR_HEIGHT + 8.0
	toasts.offset_bottom = TOP_BAR_HEIGHT + 8.0
	toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)
	flash = AlertFlash.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	tooltip = FirstRunTooltip.new()
	tooltip.visible = false
	tooltip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tooltip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tooltip.position += Vector2(16, -16)
	tooltip.dismissed.connect(_on_tooltip_dismissed)
	add_child(tooltip)
	overlay = ControlsOverlay.new()
	overlay.visible = false
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)


func _refresh_overlay() -> void:
	if overlay.visible:
		overlay.build(ctx.settings.bindings, stations, ctx.matcher.device)


## First-run tip of the focused station, once per client and station (FT-STN-012).
func _show_tooltip() -> void:
	var p: StationPanel = focused_panel()
	tooltip.visible = tooltip.show_for(
		p.station, p.tooltip_intents(), ctx.settings.bindings, ctx.matcher.device, ctx.settings
	)


func _on_tooltip_dismissed(_station: String) -> void:
	tooltip.visible = false
	ctx.settings.save()


func _on_toast(key: String, args: Dictionary) -> void:
	var text: String = tr(key)
	if text == key:
		text = tr("toast.rejected") % key.trim_prefix("toast.")
	var kind: String = "warn" if key != "toast.rate_limited" else "info"
	toasts.push(text.format(args), kind, ctx.now_ms())


## A click on a docked panel focuses it (FT-JNT-001: "tap the panel").
func _on_panel_input(event: InputEvent, p: StationPanel) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and p.docked:
		focus(panels.find(p))
		accept_event()


## Events a GUI widget owns: typing in a text field, clicks on buttons, the overlay and
## the tooltip.
func _gui_owns(event: InputEvent) -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	if event is InputEventKey and vp.gui_get_focus_owner() is LineEdit:
		return true
	if event is InputEventMouseButton:
		var hovered: Control = vp.gui_get_hovered_control()
		return hovered is BaseButton or (hovered != null and tooltip.is_ancestor_of(hovered))
	return false
