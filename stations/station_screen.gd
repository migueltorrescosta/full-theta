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

## Menu (Esc / Menu): the shell opens the menu.
signal menu_requested
## The viewport changed form (a rotation, a resize past a phone's size; LayoutMode.Form):
## panels with phone layouts rearrange (#28).
signal form_changed(form: LayoutMode.Form)
## `?` / View, or the first visit to a station: the shell opens the menu on Controls.
signal help_requested

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
## The bar of the touch layouts: tap-sized alert chip and sound button (D194).
const TOUCH_BAR_HEIGHT: float = 52.0
## A phone's bar: the chip and sound button are primary targets (48 px, #28).
const PHONE_BAR_HEIGHT: float = 56.0
## Under this width the top bar takes two rows (a phone, a tablet upright).
const COMPACT_WIDTH: float = 900.0
## A phone's smaller bar text fits one row down to this width.
const COMPACT_PHONE_WIDTH: float = 480.0
## The phone's radar column: a smaller disc (D195).
const PHONE_RADAR: float = 180.0
const PHONE_SIDE_WIDTH: float = 180.0
## Least height of a docked panel: top bar, radar and one docked panel fit 720p at
## 150 % UI scale (480 px), so the screen never grows past the window.
const DOCK_MIN_HEIGHT: float = 120.0
const SCROLL_BAR_W: float = 14.0
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
var chip_strip: ChipStrip
var share_bar: ShareBar
var training: TrainingBanner
## Makes the panel of a station; tests swap it (default StationRegistry.make).
var panel_factory: Callable = StationRegistry.make
## Controls of the shell that take the input while visible (Settings, the outcome card).
var blockers: Array[Control] = []
## The viewport's form (LayoutMode.Form), kept by _relayout; panels read it.
var form: LayoutMode.Form = LayoutMode.Form.DESKTOP
## Show the "turn sideways" banner on a phone held upright (#28).
var rotate_prompt: bool = true
var rotate_banner: RotateBanner

var _rows: VBoxContainer
var _main: Control
var _dock: VBoxContainer
## The radar and the extras column (share buttons, docked panels): beside the main area
## in landscape, below it in portrait (D216); it hides for a lone full-screen panel.
var _side: BoxContainer
var _body: BoxContainer
var _extras: VBoxContainer
var _blocked: bool = false
## The dev seat's station tabs (one button per panel) and its one-line hint; null when the
## screen holds one or two panels.
var _tabs: HFlowContainer
var _hint: Label


## Builds the screen for the current pick (ctx.crew.entry_def()). Entries without
## functional stations (Captain, Viewer) get one panel of their own id.
func setup(context: StationContext) -> void:
	ctx = context
	# The matcher outlives screens: a screen freed while blocked (the outcome card before a
	# run reset) left it restricted.
	ctx.matcher.restrict([])
	var def: Dictionary = ctx.crew.entry_def()
	for s: Variant in def.get("stations", []):
		stations.append(str(s))
	if stations.is_empty():
		stations.append(ctx.crew.entry)
	_build()
	_relayout()
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
	# the Shakedown's step banner and Next (FT-MIS-039).
	training = TrainingBanner.new()
	training.station = stations[0]
	add_child(training)
	training.setup(ctx)
	Input.joy_connection_changed.connect(_on_joy_changed)
	_build_tabs()
	focus(0)
	rotate_banner.settings = ctx.settings
	rotate_banner.refresh()


func _ready() -> void:
	get_viewport().size_changed.connect(_relayout)
	_relayout()
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
	_show_side()
	if _tabs != null:
		_show_tabs()
	_open_first_visit_help()


## The radar column hides for a lone full-screen panel (which may depend on the form).
func _show_side() -> void:
	if not panels.is_empty():
		_side.visible = not (panels.size() == 1 and focused_panel().full_screen())


## The dev seat's station switcher: a tab per panel, numbered for Shift + digit, and until the
## first switch a one-line hint (kept in the first-run tips).
func _build_tabs() -> void:
	if panels.size() < TABS_FROM:
		return
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 4)
	_tabs.add_theme_constant_override("v_separation", 2)
	top_bar.get_parent().add_child(_tabs)
	top_bar.get_parent().move_child(_tabs, top_bar.get_index() + 1)
	for i: int in panels.size():
		var b: Button = Button.new()
		b.name = "Tab%d" % (i + 1)
		b.toggle_mode = true
		b.text = "%d %s" % [i + 1, tr("station." + stations[i])]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(focus.bind(i))
		_tabs.add_child(b)
	_hint = Label.new()
	_hint.text = tr("screen.tabs_hint") % panels.size()
	_hint.add_theme_color_override("font_color", Palette.color("text_dim"))
	_hint.visible = not ctx.settings.tooltip_seen(TAB_HINT_KEY)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tabs.add_child(_hint)


## Marks the focused tab; a switch after the first panel retires the hint.
func _show_tabs() -> void:
	for i: int in panels.size():
		(_tabs.get_child(i) as Button).set_pressed_no_signal(i == focus_index)
	if _hint.visible and focus_index != 0:
		_hint.visible = false
		ctx.settings.mark_tooltip_seen(TAB_HINT_KEY)
		ctx.settings.save()


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
		return _common(ev)
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
	if _gui_owns(event):
		return
	feed(event)


func _process(delta: float) -> void:
	_update_block()
	_dispatch_batch(ctx.matcher.update(ctx.now_ms(), delta))
	var now: int = ctx.now_ms()
	top_bar.can_set_alert = ctx.crew.is_crew()
	var status: Dictionary = ctx.view.blocks.get(StationViews.Section.STATUS, {})
	top_bar.show_state(
		ctx.crew.ship_name(),
		status,
		ctx.crew.alert,
		stations,
		ctx.crew.mission_seconds(ctx.view.tick),
		focused_station(),
		_maxes(),
		ctx.crew.summaries(status, ctx.ship_def())
	)
	radar.set_picture(ctx.picture(), ctx.crew.selection)
	radar.blip_scale = focused_panel().blip_scale()
	toasts.update(now)
	flash.update(now)
	chip_strip.show_chips(
		ChipView.incoming(ctx.view, stations), ChipView.outgoing(ctx.view, stations), ctx.view
	)
	var left: Dictionary = {}
	for id: StringName in ctx.crew.shares:
		left[id] = ctx.crew.share_left(id, now)
	share_bar.show_features(shareable(), left)


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
			handled = focused_panel().handle_intent(ev) or _answer_chip(id == "accept")
		"request":
			handled = focused_panel().has_request_chip()
			if handled:
				focused_panel().send_request()
		"radar_strip":
			radar.toggle_strip()
		"claim":
			_claim()
		"share":
			handled = not shareable().is_empty()
			for feature: StringName in shareable():
				ctx.intents.share(String(feature))
		"overlay":
			help_requested.emit()
			_update_block()
		"menu":
			# Esc first closes what the focused panel has open on top (Comms' overlay).
			if not focused_panel().close_overlay():
				menu_requested.emit()
				_update_block()
		_:
			handled = _live(id)
	return handled


## The data shortcuts this screen's stations may share with their partners (D210).
func shareable() -> Array[StringName]:
	var out: Array[StringName] = []
	if ctx.crew.is_crew():
		out = ShareBar.features(stations, ctx.crew.toggles)
	return out


## Answers the oldest request chip sent to this screen, the focused station's first
## (FT-PAIR-013); false when none is open.
func _answer_chip(accept: bool) -> bool:
	var open: Array[Dictionary] = ChipView.incoming(ctx.view, stations)
	if open.is_empty():
		return false
	var mine: Array[Dictionary] = open.filter(
		func(c: Dictionary) -> bool: return c["to"] == focused_station()
	)
	ctx.intents.answer_chip(int((mine if not mine.is_empty() else open)[0]["id"]), accept)
	return true


## Select under the pointer; false over nothing, so the click falls through to the
## panel (owner decision in #7: LMB fires in the turret).
func _select(device: String) -> bool:
	if device == IntentTable.PAD and focused_panel().take_select():
		return true
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty() or item["kind"] == "point" or item["kind"] == "card":
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
		"training_next":
			return training.press()
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
	ctx.ping_item(item)


## Mark at the cursor, or on the selection (FT-SPA-013, FT-SPA-022): refused with a
## toast when the ship has 8 marks, unless the focused panel replaces one (Relay). On a
## forward view only a contact takes a mark (FT-SPA-030).
func _mark(device: String) -> void:
	if ctx.crew.entry == StationViews.VIEWER:
		return
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty():
		item = ctx.crew.selection
	if item.is_empty():
		return
	# A forward view marks only a contact (FT-SPA-030).
	if focused_panel().marks_attach_only() and item.get("kind", "") != "contact":
		return
	if ctx.crew.marks.size() >= CrewState.MAX_MARKS:
		if not focused_panel().replace_mark(item):
			_on_toast("toast.marks_full", {})
		return
	ctx.mark_item(-1, item)


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


# --- Layout and widgets. ---


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("background")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Everything but the background and the flash stays inside the safe area (#28).
	var rows: VBoxContainer = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)
	_rows = rows
	top_bar = TopBar.new()
	top_bar.custom_minimum_size = Vector2(0, TOP_BAR_HEIGHT)
	top_bar.alert_picked.connect(_set_alert)
	rows.add_child(top_bar)
	rotate_banner = RotateBanner.new()
	rows.add_child(rotate_banner)
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_body)
	_main = Control.new()
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.clip_contents = true
	_body.add_child(_main)
	_side = BoxContainer.new()
	_body.add_child(_side)
	radar = DiscRadar.new()
	_side.add_child(radar)
	# The column scrolls instead of growing the screen past the viewport (150 % UI scale,
	# a phone with four share buttons): the radar keeps its size, the rest is reachable.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A wide bar shows at a glance that the column scrolls.
	scroll.get_v_scroll_bar().custom_minimum_size.x = SCROLL_BAR_W
	_side.add_child(scroll)
	_extras = VBoxContainer.new()
	_extras.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_extras.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_extras)
	# The share buttons sit above the docked panels, not over them (D217).
	share_bar = ShareBar.new()
	share_bar.visible = false
	share_bar.share_pressed.connect(func(id: StringName) -> void: ctx.intents.share(String(id)))
	_extras.add_child(share_bar)
	_dock = VBoxContainer.new()
	_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_extras.add_child(_dock)
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
	chip_strip = ChipStrip.new()
	chip_strip.position = Vector2(8.0, TOP_BAR_HEIGHT + 8.0)
	chip_strip.visible = false
	add_child(chip_strip)
	flash = AlertFlash.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)


## Arranges the screen for the viewport (LayoutMode): the bar's height and rows, and the
## radar column beside the main area (landscape) or below it (portrait), narrower or
## shorter on a phone. Runs on every resize and rotation.
func _relayout() -> void:
	if _body == null or not is_inside_tree():
		return
	var size_now: Vector2 = get_viewport().get_visible_rect().size
	var kind: LayoutMode.Kind = LayoutMode.kind_of(self)
	var phone: bool = kind == LayoutMode.Kind.PHONE
	# The safe area: on a phone also clear of the gesture band, so nothing on the screen
	# can be tapped there (#28).
	var m: Vector4 = SafeArea.margins(self)
	var bottom: float = maxf(m.w, SafeArea.tap_band(self))
	_rows.offset_left = m.x
	_rows.offset_top = m.y
	_rows.offset_right = -m.z
	_rows.offset_bottom = -bottom
	size_now -= Vector2(m.x + m.z, m.y + bottom)
	var touch: bool = LayoutMode.is_touch(kind)
	var portrait: bool = LayoutMode.portrait(size_now)
	_body.vertical = portrait
	_side.vertical = not portrait
	var bar: float = TOP_BAR_HEIGHT
	if phone:
		bar = PHONE_BAR_HEIGHT
	elif touch:
		bar = TOUCH_BAR_HEIGHT
	var two_rows: bool = size_now.x < (COMPACT_PHONE_WIDTH if phone else COMPACT_WIDTH)
	top_bar.set_compact(two_rows, bar, phone)
	top_bar.custom_minimum_size.y = bar * (2.0 if two_rows else 1.0)
	var disc: float = RADAR_HEIGHT
	var short: bool = size_now.y < SHORT_H and not phone
	if phone:
		disc = PHONE_RADAR
	elif short:
		disc = SHORT_RADAR
	_side.custom_minimum_size = Vector2.ZERO
	if portrait:
		radar.custom_minimum_size = Vector2(disc, disc)
		_side.custom_minimum_size.y = disc
	else:
		var width: float = PHONE_SIDE_WIDTH if phone else SIDE_WIDTH
		if short and size_now.x < COMPACT_WIDTH:
			width = SHORT_SIDE_WIDTH
		radar.custom_minimum_size = Vector2(width, disc if not phone else width)
		_side.custom_minimum_size.x = width
	share_bar.min_width = 150.0 if phone else 260.0
	share_bar.button_h = ShareBar.SHORT_H if short and not touch else ShareBar.BUTTON_H
	var top: float = m.y + top_bar.custom_minimum_size.y + 8.0
	toasts.offset_top = top
	toasts.offset_bottom = top
	toasts.offset_left = -16.0 - m.z
	toasts.offset_right = -16.0 - m.z
	chip_strip.position = Vector2(8.0 + m.x, top)
	rotate_banner.visible = false
	if rotate_prompt:
		rotate_banner.refresh()
	_show_side()
	var now: LayoutMode.Form = LayoutMode.form_of(self)
	if now != form:
		form = now
		form_changed.emit(form)


## The first visit to a station asks for the menu's Controls tab, once per client and
## station (FT-STN-012, D185); Settings re-enables it. The first station waits for the
## screen to enter the tree, so the shell has connected `help_requested` by then.
func _open_first_visit_help() -> void:
	var station: String = focused_station()
	if not is_inside_tree() or ctx.settings.tooltip_seen(station):
		return
	ctx.settings.mark_tooltip_seen(station)
	ctx.settings.save()
	help_requested.emit()
	_update_block()


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
