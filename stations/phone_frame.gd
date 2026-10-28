class_name PhoneFrame
extends RefCounted
## The shared phone frame of a StationScreen (#28 follow-up, design "Shared frame", owner
## picks P28-Tabs, P28-Band, P28-Common, P28-Joint, P28-Dev): the station chip and the page
## tabs (the top bar on its side, the bottom tab bar upright), and for a panel in the frame
## (StationPanel.in_frame) the view-top row (selection chip, incoming request chips with ✓
## ✕, the partner glance of a joint view, the ping toast that selects) and long-press ping
## and mark. The bottom band guard takes every tap in the gesture band. Built for every
## screen, shown only on phones, so tablets and desktops keep their layout.

## The view-top row's distance from the top of the view (the bar's targets end
## UiTheme.TOUCH_GAP above it, as above the rails' first row).
const VIEW_TOP_Y: float = 0.0
## The station chip's arrow in a joint view, and the dev seat's (P28-Dev).
const JOINT_ARROW: String = "⇄"
const DEV_ARROW: String = "▾"
const CHIP_W: float = 72.0

var screen: StationScreen
var selection_chip: SelectionChip = SelectionChip.new()
var request_chips: RequestChips = RequestChips.new()
var glance: PartnerGlance = PartnerGlance.new()
var ping_toast: PingToast = PingToast.new()
## The bottom tab bar upright (the top bar holds the tabs on its side).
var bottom_tabs: PageTabs = PageTabs.new()
## Long-press ping and long-press-drag mark on the view (P28-Common).
var long_press: LongPress = LongPress.new()
## Takes every tap in the phone's bottom band (P28-Band: drawn into, never tapped).
var band_guard: Control = Control.new()
## The view-top row's layer over the main area.
var view_top: Control = Control.new()

## The feedback of an armed long-press: a ring under the finger that grows (P28-Common).
var armed_ring: ArmedRing = ArmedRing.new()

var _tabs_gap: Control = Control.new()


## A ring under a held finger once the long-press arms: it grows from START_R to END_R over
## GROW_MS, then stays until the finger lets go; it follows a mark drag.
class ArmedRing:
	extends Control

	const START_R: float = 14.0
	const END_R: float = 36.0
	const GROW_MS: int = 200
	const WIDTH: float = 3.0

	## When the gesture armed (ms), -1 while hidden.
	var since: int = -1
	var now: int = 0

	func _init() -> void:
		name = "ArmedRing"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		size = Vector2.ONE * 2.0 * (END_R + WIDTH)

	## Shows the ring centred on `at` (its parent's coordinates) from `now_ms`.
	func show_at(at: Vector2, now_ms: int) -> void:
		since = now_ms
		now = now_ms
		visible = true
		move_to(at)

	func move_to(at: Vector2) -> void:
		position = at - size / 2.0

	## The radius at `now`.
	func radius() -> float:
		var k: float = clampf(float(now - since) / GROW_MS, 0.0, 1.0)
		return lerpf(START_R, END_R, k)

	func tick(now_ms: int) -> void:
		now = now_ms
		queue_redraw()

	func hide_ring() -> void:
		since = -1
		visible = false

	func _draw() -> void:
		var c: Vector2 = size / 2.0
		var accent: Color = Palette.color("accent")
		draw_circle(c, radius(), Color(accent, 0.2))
		draw_arc(c, radius(), 0.0, TAU, 48, accent, WIDTH, true)


## Builds the widgets into the screen: the view-top row and `sheet` over `main`, the bottom
## tab bar at the end of `rows`, the band guard over everything.
func build(owner_screen: StationScreen, main: Control, rows: VBoxContainer) -> void:
	screen = owner_screen
	view_top.name = "ViewTop"
	view_top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_top.visible = false
	main.add_child(view_top)
	selection_chip.cycled.connect(cycle_target)
	selection_chip.opened.connect(open_selection_sheet)
	request_chips.answered.connect(
		func(id: int, accept: bool) -> void: screen.ctx.intents.answer_chip(id, accept)
	)
	glance.visible = false
	glance.action_pressed.connect(_partner_intent)
	ping_toast.name = "PingToast"
	ping_toast.tapped.connect(func() -> void: screen.ctx.crew.select_pinged(screen.ctx.now_ms()))
	for c: Control in [selection_chip, request_chips, glance, ping_toast]:
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		view_top.add_child(c)
	# The bottom tab bar keeps UiTheme.TOUCH_GAP from the panel's targets above it.
	_tabs_gap.custom_minimum_size.y = UiTheme.TOUCH_GAP
	_tabs_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tabs_gap.visible = false
	rows.add_child(_tabs_gap)
	bottom_tabs.name = "BottomTabs"
	bottom_tabs.upright = true
	bottom_tabs.visible = false
	rows.add_child(bottom_tabs)
	band_guard.name = "BandGuard"
	band_guard.mouse_filter = Control.MOUSE_FILTER_STOP
	band_guard.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band_guard.visible = false
	band_guard.add_to_group(TouchInput.GROUP)
	screen.add_child(band_guard)
	long_press.ping.connect(screen.ping_at)
	long_press.mark.connect(screen.mark_at)
	long_press.armed.connect(_on_armed)
	view_top.add_child(armed_ring)
	screen.top_bar.alert_sheet_requested.connect(open_alert_sheet)


## True on a phone whose focused panel is in the frame: the view-top row, long-press and
## the band apply.
func framed() -> bool:
	return screen.phone and not screen.panels.is_empty() and screen.focused_panel().in_frame


## The station chip of a joint view or the dev seat on a phone (made on first use, kept on
## the screen as `joint_switch`), and the focused panel's tabs: in the top bar on its side,
## in the bottom tab bar upright, nowhere off a phone.
func show_tabs(form_now: LayoutMode.Form, alone: bool) -> void:
	var s: StationScreen = screen
	if alone and s.joint_switch == null:
		s.joint_switch = RailButton.make("")
		s.joint_switch.name = "JointSwitch"
		s.joint_switch.add_theme_font_size_override("font_size", PageTabs.FONT)
		s.joint_switch.pressed.connect(_on_station_chip)
	var chip: RailButton = s.joint_switch
	if chip != null:
		chip.visible = alone
		chip.custom_minimum_size = Vector2(CHIP_W, UiTheme.TOUCH_PRIMARY)
		if s.panels.size() == 2:
			chip.text = "%s %s" % [JOINT_ARROW, tr("station." + s.stations[1 - s.focus_index])]
		else:
			chip.text = "%s %s" % [tr("station." + s.focused_station()), DEV_ARROW]
	var pages: PageHost = s.focused_panel().pages
	var sideways: bool = form_now == LayoutMode.Form.PHONE_LANDSCAPE
	var upright: bool = form_now == LayoutMode.Form.PHONE_PORTRAIT
	s.top_bar.tabs.bind(pages if sideways else null)
	bottom_tabs.bind(pages if upright else null)
	var strip: PageTabs = s.top_bar.tabs if sideways else bottom_tabs
	var other: PageTabs = bottom_tabs if sideways else s.top_bar.tabs
	if other.lead != null:
		other.set_lead(null)
	var lead: RailButton = chip if chip != null and alone and (sideways or upright) else null
	strip.set_lead(lead)
	bottom_tabs.visible = upright and bottom_tabs.has_content()
	_tabs_gap.visible = bottom_tabs.visible


## A phone's own touch rules: a finger in the bottom band does nothing (P28-Band), and a
## finger on a framed view (not on a rail, a sheet or a button) may long-press. True when
## the event is used up here.
func input(event: InputEvent) -> bool:
	var pos: Vector2 = Vector2(-1.0, -1.0)
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		pos = touch.position
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
	else:
		return false
	var starts: bool = touch != null and touch.pressed
	if starts and band_guard.get_global_rect().has_point(pos):
		return true
	var off: bool = not framed() or screen.blocked() or TouchInput.over(screen.get_tree(), pos)
	if starts and (off or not _over_view(pos)):
		return false
	var used: bool = long_press.feed(event, screen.ctx.now_ms())
	if armed_ring.visible:
		if long_press.is_armed():
			armed_ring.move_to(pos - view_top.global_position)
		else:
			armed_ring.hide_ring()
	return used


## True when `pos` (viewport px) is over the view-top row's layer and no button takes it.
func _over_view(pos: Vector2) -> bool:
	if not view_top.get_global_rect().has_point(pos):
		return false
	var hovered: Control = screen.get_viewport().gui_get_hovered_control()
	return not (hovered is BaseButton)


## Each frame on a phone: the view-top row's contents and places (framed only).
func process(now: int) -> void:
	view_top.visible = framed()
	if not view_top.visible:
		armed_ring.hide_ring()
		return
	long_press.update(now)
	if armed_ring.visible:
		if long_press.is_armed():
			armed_ring.tick(now)
		else:
			armed_ring.hide_ring()
	ping_toast.update(now)
	var ctx: StationContext = screen.ctx
	var crew: bool = ctx.crew.is_crew()
	selection_chip.visible = crew
	if crew:
		selection_chip.show_text(selection_text())
	var rows: Array = []
	if crew:
		for c: Dictionary in ChipView.incoming(ctx.view, screen.stations):
			var text: String = "%s: %s" % [tr("station." + str(c["from"])), ChipView.label(c)]
			rows.append({"id": c["id"], "text": text, "left": ChipView.left_s(ctx.view, c)})
	request_chips.show_chips(rows)
	if screen.panels.size() == 2:
		var other: String = screen.stations[1 - screen.focus_index]
		glance.show_for(ctx, other, screen.focused_station())
	else:
		glance.visible = false
	_place_view_top()


## The view-top row (design 1.3) at the top of the focused panel's view: the selection
## chip centred, the request chips, the partner glance and the ping toast in a column at
## the right; the column drops under the chip when the view is too narrow for both.
func _place_view_top() -> void:
	var p: StationPanel = screen.focused_panel()
	var r: Rect2 = p.view_rect()
	r.position += p.position
	var gap: float = UiTheme.TOUCH_GAP
	var x0: float = r.position.x + gap
	var x1: float = r.end.x - gap
	# The row sits at the top of the view, wherever the panel's view starts (Engineering
	# upright: under its button grid).
	var y: float = r.position.y + VIEW_TOP_Y
	selection_chip.fit(x1 - x0)
	var chip_w: float = selection_chip.get_combined_minimum_size().x
	var col: Array[Control] = []
	var col_w: float = 0.0
	for c: Control in [request_chips, glance, ping_toast]:
		if c.visible:
			col.append(c)
			col_w = maxf(col_w, c.get_combined_minimum_size().x)
	var side_by_side: bool = col.is_empty() or x1 - x0 >= chip_w + gap + col_w
	var row_h: float = 0.0
	if selection_chip.visible:
		var right: float = x1 - (col_w + gap if side_by_side and not col.is_empty() else 0.0)
		var cx: float = maxf(x0, (x0 + right - chip_w) / 2.0)
		selection_chip.position = Vector2(roundf(cx), y)
		selection_chip.size = selection_chip.get_combined_minimum_size()
		row_h = selection_chip.size.y + gap
	var cy: float = y if side_by_side else y + row_h
	for c: Control in col:
		var sz: Vector2 = c.get_combined_minimum_size()
		c.size = Vector2(col_w, sz.y)
		c.position = Vector2(roundf(x1 - col_w), cy)
		cy += sz.y + gap
	var reserve: float = row_h if side_by_side else maxf(row_h, cy - y)
	if p.top_reserve != reserve:
		p.top_reserve = reserve
		p.queue_redraw()


## The selection's text for the chip: its name, clock and height, and range band
## ("H2 · 4 high · mid"); "" with nothing selected.
func selection_text() -> String:
	var ctx: StationContext = screen.ctx
	var sel: Dictionary = ctx.crew.selection
	if sel.is_empty():
		return ""
	var label: String = str(ctx.picture().find(sel).get("label", ""))
	if label == "" and sel.get("kind", "") == "contact":
		label = ctx.view.callsign(int(sel["id"]))
	var local: Variant = ctx.selection_local()
	if local is Vector3:
		var v: Vector3 = local
		label += " · %s · %s" % [Callout.clock_height(v), Callout.range_band(v.length())]
	return label


## The selection chip's arrows: the next (+1) or previous (-1) contact by range.
func cycle_target(step: int) -> void:
	var ids: Array = screen.contacts_by_range()
	if step < 0:
		ids.reverse()
	screen.ctx.crew.cycle("contact", ids)


## The selection sheet (P28-Common): Ping, Mark here, Clear, then the focused panel's
## extras (StationPanel.selection_extras).
func open_selection_sheet() -> void:
	var ctx: StationContext = screen.ctx
	var labels: Array = [
		tr("intent.ping"),
		TouchText.of("sheet.mark_here", "Mark here"),
		TouchText.of("sheet.clear", "Clear")
	]
	var acts: Array[Callable] = [
		func() -> void: screen.ping_at(Vector2(-1.0, -1.0)),
		func() -> void: screen.mark_item(ctx.crew.selection),
		func() -> void: ctx.crew.select("", -1),
	]
	for e: Array in screen.focused_panel().selection_extras:
		labels.append(str(e[0]))
		acts.append(e[1])
	var heading: String = selection_text()
	if heading == "":
		heading = tr("helm.no_selection")
	screen.sheet.open(heading, labels, func(i: int) -> void: acts[i].call())


## The alert sheet from the phone's alert chip (FT-STN-008: crew only).
func open_alert_sheet() -> void:
	if not screen.ctx.crew.is_crew():
		return
	var labels: Array = []
	for a: Dictionary in Palette.ALERTS:
		labels.append("%s  %s" % [a["letter"], tr(a["key"])])
	screen.sheet.open(tr("intent.alert_cycle"), labels, screen._set_alert)


## A long-press armed at `at` (viewport px): the ring shows under the finger.
func _on_armed(at: Vector2) -> void:
	armed_ring.show_at(at - view_top.global_position, screen.ctx.now_ms())
	view_top.move_child(armed_ring, -1)


## The station chip: a joint view flips the focus; the dev seat opens the six-station
## sheet, numbered as D256's tabs.
func _on_station_chip() -> void:
	if screen.panels.size() == 2:
		screen.focus(1 - screen.focus_index)
		return
	var labels: Array = []
	for i: int in screen.stations.size():
		labels.append("%d %s" % [i + 1, tr("station." + screen.stations[i])])
	screen.sheet.open(TouchText.of("sheet.stations", "Stations"), labels, screen.focus)


## The partner glance's action: the other station's intent, run by its own panel.
func _partner_intent(intent: String) -> void:
	if screen.panels.size() != 2 or intent == "":
		return
	var other: int = 1 - screen.focus_index
	var ev: Dictionary = {"id": intent, "pressed": true, "target": screen.stations[other]}
	screen.panels[other].handle_intent(ev)


## A ping on a framed phone shows the toast that selects it (not a point or card ping).
func on_pinged(p: Dictionary) -> void:
	if not framed() or not str(p.get("kind", "")) in ["contact", "mark", "site", "zone"]:
		return
	var ctx: StationContext = screen.ctx
	var item: Dictionary = {"kind": p["kind"], "id": p["id"]}
	var label: String = str(ctx.picture().find(item).get("label", ""))
	if label == "" and item["kind"] == "contact":
		label = ctx.view.callsign(int(item["id"]))
	var text: String = TouchText.of("toast.pinged", "%s pinged %s") % [str(p.get("by", "")), label]
	ping_toast.show_ping(text, ctx.now_ms())
