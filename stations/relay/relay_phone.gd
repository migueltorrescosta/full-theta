class_name RelayPhone
extends Control
## Relay on a phone (#28 follow-up, design 2.5, owner picks P28-Tabs, P28-Common, P28-S2;
## D287-D289). Landscape: the map fills the panel under two translucent rails, and the
## pages swap what the rails hold:
##   Map (rest): Launch probe, Hazard, Route, Flag lanes | Accept, Decline, Send ▸, Centre
##   Marks: the marks list | Rename, Delete, Attach, Centre, Send ▸
##   Contacts: the nearest contacts | Route, Centre
##   Log: the ship's log and the inbox (a wider left panel) | the main-screen views
##   Crew: CrewPage (requests, Ping, Mark, shares)
## Send ▸ opens the screen's choice sheet of allied ships; a long press on Launch probe
## takes or releases the probe launcher. The probe count and the waiting mark read across
## the map's top, under the screen's view-top row. Upright (the reduced layout under the
## "turn sideways" banner): the map on top, the lines, then the page's list and buttons in
## rows; the screen's bottom tab bar holds the tabs.
## Every button runs the panel's intent (RelayPanel.handle_intent), so a tap does what the
## key does. On the map: drag places or moves a mark, a second finger slides its depth,
## pinch zooms and two fingers turn the map (RelayPanel).

const RAIL_W: float = 168.0
## The Log page's left panel (the log's lines need the width).
const LOG_W: float = 300.0
## The probe and inbox line over the map (landscape), and the armed hint below it.
const LINE_H: float = 28.0
## Upright: the page zone's height (four rows of buttons).
const ZONE_H: float = 4.0 * UiTheme.TOUCH_PRIMARY + 3.0 * UiTheme.TOUCH_GAP
## A press on Launch probe this long takes or releases the launcher (ms).
const LONG_PRESS_MS: int = 500
## Log lines on the Log page.
const LOG_LINES: int = 8
const PAGE_MAP: int = 0
const PAGE_MARKS: int = 1
const PAGE_CONTACTS: int = 2
const PAGE_LOG: int = 3
const PAGE_CREW: int = 4

var panel: RelayPanel
var form: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE
## The landscape rails (null upright).
var layout: RailLayout
## Map, Marks, Contacts, Log, Crew (set on the panel as its `pages`).
var pages: PageHost = PageHost.new()
var crew: CrewPage
## Every page button by name: launch, hazard, route, lanes, accept, decline, send, centre
## (Map); rename, delete, attach, centre_mark, send_mark (Marks); route_contact,
## centre_contact (Contacts); view_1 to view_5 (Log).
var buttons: Dictionary[String, RailButton] = {}
var probes: Label
var mail: Label
var log_text: Label

var _marks_box: VBoxContainer
var _contacts_box: VBoxContainer
var _contact_key: Array = []
var _mark_key: Array = []
var _long_at: int = -1
var _long_done: bool = false
var _reserve: float = -1.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A gap under the top bar, so its buttons and the first rail button are apart.
	offset_top = UiTheme.TOUCH_GAP
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The form of the station screen `panel` is on, from the screen's own size: in the game
## it fills the window (LayoutMode.form_of); tests lay a screen out at a set size inside
## the tiny headless window, which alone would read as a phone.
static func form_of_panel(panel: Control) -> LayoutMode.Form:
	var n: Node = panel
	while n != null and not n is StationScreen:
		n = n.get_parent()
	if n == null:
		return LayoutMode.form_of(panel)
	var vp: Viewport = panel.get_viewport()
	var factor: float = (vp as Window).content_scale_factor if vp is Window else 1.0
	var dp: Vector2 = LayoutMode.dp_size((n as Control).size, factor, LayoutMode.density())
	return LayoutMode.form_for(dp, LayoutMode.coarse_pointer())


## Hides the HUD and builds the pages for `phone_form` around the map.
func build(p: RelayPanel, phone_form: LayoutMode.Form) -> void:
	panel = p
	form = phone_form
	_make_controls()
	var page_parts: Array = [
		[
			[buttons["launch"], buttons["hazard"], buttons["route"], buttons["lanes"]],
			[buttons["accept"], buttons["decline"], buttons["send"], buttons["centre"]]
		],
		[
			[_scrolled(_marks_box)],
			[
				buttons["rename"],
				buttons["delete"],
				buttons["attach"],
				buttons["centre_mark"],
				buttons["send_mark"]
			]
		],
		[[_scrolled(_contacts_box)], [buttons["route_contact"], buttons["centre_contact"]]],
		[[log_text], _views()],
		[[crew], []],
	]
	var titles: Array[String] = [
		TouchText.of("page.map", "Map"),
		tr("relay.marks"),
		tr("relay.contacts"),
		tr("relay.log"),
		TouchText.of("page.crew", "Crew"),
	]
	layout = RailLayout.new()
	if form == LayoutMode.Form.PHONE_LANDSCAPE:
		_build_landscape(page_parts, titles)
	else:
		_build_portrait(page_parts, titles)
	pages.page_changed.connect(_on_page)
	layout.content_rect_changed.connect(_place_view)
	panel.hud.visible = false


func _make_controls() -> void:
	var specs: Array = [
		["launch", tr("relay.launch"), "probe_launch"],
		["hazard", tr("relay.hazard"), "hazard_add"],
		["route", tr("intent.route"), "route"],
		["lanes", tr("relay.lanes_off"), "flag_lanes"],
		["accept", tr("relay.accept"), "accept"],
		["decline", tr("relay.decline"), "decline"],
		["send", TouchText.of("relay.send_to", "Send ▸"), ""],
		["centre", TouchText.of("relay.centre", "Centre"), "map_centre"],
		["rename", TouchText.of("relay.rename", "Rename"), "mark_rename"],
		["delete", TouchText.of("relay.delete", "Delete"), "mark_delete"],
		["attach", TouchText.of("relay.attach", "Attach"), "mark_attach"],
		["centre_mark", TouchText.of("relay.centre", "Centre"), "map_centre"],
		["send_mark", TouchText.of("relay.send_to", "Send ▸"), ""],
		["route_contact", tr("intent.route"), "route"],
		["centre_contact", TouchText.of("relay.centre", "Centre"), "map_centre"],
	]
	for i: int in MainScreen.NAMES.size():
		specs.append(
			["view_%d" % (i + 1), tr("view." + MainScreen.NAMES[i]), "main_view_%d" % (i + 1)]
		)
	for s: Array in specs:
		var b: RailButton = RailButton.make(str(s[1]))
		b.name = "Relay_" + str(s[0])
		var intent: String = s[2]
		if s[0] in ["send", "send_mark"]:
			b.pressed.connect(panel.open_send)
		elif s[0] in ["route", "route_contact"]:
			b.pressed.connect(_route)
		elif s[0] == "launch":
			b.pressed.connect(_on_launch)
		else:
			b.pressed.connect(_intent.bind(intent))
		buttons[s[0]] = b
	# A long press on Launch probe takes or releases the launcher (design 2.5).
	buttons["launch"].hold = true
	buttons["launch"].held.connect(_on_launch_held)
	crew = CrewPage.new(panel)
	crew.name = "CrewPage"
	_marks_box = _column()
	_contacts_box = _column()
	ListLines.attach(_marks_box)
	ListLines.attach(_contacts_box)
	log_text = Label.new()
	log_text.name = "LogText"
	log_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	log_text.add_theme_font_size_override("font_size", 13)
	log_text.add_theme_color_override("font_color", Palette.color("text"))
	probes = _label()
	mail = _label()


## The main-screen view buttons of the Log page.
func _views() -> Array:
	var out: Array = []
	for i: int in MainScreen.NAMES.size():
		out.append(buttons["view_%d" % (i + 1)])
	return out


## Overlay rails over the full map; each page fills its left and right part.
func _build_landscape(page_parts: Array, titles: Array[String]) -> void:
	add_child(layout)
	layout.set_content(panel.map)
	var left: TouchRail = layout.rail(SIDE_LEFT)
	left.custom_minimum_size.x = RAIL_W
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.custom_minimum_size.x = RAIL_W
	for i: int in page_parts.size():
		var parts: Array = []
		for side: int in 2:
			var col: VBoxContainer = _column()
			col.size_flags_vertical = Control.SIZE_EXPAND_FILL
			for c: Control in page_parts[i][side]:
				col.add_child(c)
				if c is ScrollContainer or c == log_text or c == crew:
					c.size_flags_vertical = Control.SIZE_EXPAND_FILL
			(left if side == 0 else right).add(col)
			parts.append(col)
		pages.add_page(titles[i], parts)
	# The rails have room for five buttons only: the probe and inbox lines go over the
	# map's top edge, between the rails.
	mail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l: Label in [probes, mail]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	_on_page(PAGE_MAP)


## Upright: the map on top, the probe and inbox lines, then the page's part in rows.
func _build_portrait(page_parts: Array, titles: Array[String]) -> void:
	var col: VBoxContainer = _column()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(layout)
	layout.set_content(panel.map)
	col.add_child(_row([probes, mail]))
	for i: int in page_parts.size():
		var zone: VBoxContainer = _column()
		zone.custom_minimum_size.y = ZONE_H
		var lists: Array = []
		var row_buttons: Array = []
		for c: Control in page_parts[i][0] + page_parts[i][1]:
			if c is RailButton:
				row_buttons.append(c)
			else:
				lists.append(c)
		for c: Control in lists:
			c.size_flags_vertical = Control.SIZE_EXPAND_FILL
			zone.add_child(c)
		var per_row: int = 2 if lists.is_empty() else 3
		for k: int in range(0, row_buttons.size(), per_row):
			zone.add_child(_row(row_buttons.slice(k, k + per_row)))
		col.add_child(zone)
		pages.add_page(titles[i], [zone])


## Gives the map back to the panel and the HUD.
func release() -> void:
	layout.content_rect_changed.disconnect(_place_view)
	panel.map.reparent(panel, false)
	panel.move_child(panel.map, 0)
	panel.map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.map.view_rect = Rect2()
	panel._hint.offset_left = 260.0
	panel._hint.offset_right = -8.0
	panel._hint.offset_top = 8.0
	panel._rename.custom_minimum_size = Vector2(220, 0)
	panel._rename.position = Vector2(12, 12)
	panel.hud.set_docked(panel.docked)


## The Log page widens the left rail; the Crew page has nothing on the right.
func _on_page(index: int) -> void:
	if form != LayoutMode.Form.PHONE_LANDSCAPE:
		return
	layout.left.custom_minimum_size.x = LOG_W if index == PAGE_LOG else RAIL_W
	layout.right.visible = index != PAGE_CREW
	layout.queue_sort()


## The map's part between the rails, under the view-top row, in the map's coordinates.
func view_in_map() -> Rect2:
	var r: Rect2 = layout.content_rect_in(panel.map)
	var top: float = panel.top_reserve
	r.position.y += top
	r.size.y = maxf(r.size.y - top, 1.0)
	return r


## The map centres in the uncovered part; the lines and an armed hint sit at its top, the
## rename field under them.
func _place_view(_rect: Rect2 = Rect2()) -> void:
	_reserve = panel.top_reserve
	var r: Rect2 = view_in_map()
	if r.size.x < 2.0 * RAIL_W / 3.0 or r.size.y < LINE_H * 3.0:
		r = Rect2(Vector2.ZERO, panel.map.size)
	panel.map.view_rect = r
	panel._hint.offset_left = r.position.x + 8.0
	panel._hint.offset_right = -(panel.size.x - r.end.x) - 8.0
	var y: float = r.position.y + 4.0
	if probes.get_parent() == self:
		var half: float = maxf(r.size.x / 2.0 - 12.0, 1.0)
		probes.position = Vector2(r.position.x + 8.0, y)
		mail.position = Vector2(r.get_center().x + 4.0, y)
		for l: Label in [probes, mail]:
			l.size = Vector2(half, l.get_combined_minimum_size().y)
		y += LINE_H
	panel._hint.offset_top = position.y + y
	panel._rename.custom_minimum_size = Vector2(220, UiTheme.TOUCH_PRIMARY)
	panel._rename.position = Vector2(r.position.x + 8.0, position.y + y)
	panel.map.queue_redraw()


## Mirrors the panel each frame: texts, enabled states, the lists and the log.
func update() -> void:
	if panel.top_reserve != _reserve:
		_place_view()
	if _long_at >= 0 and panel.ctx.now_ms() - _long_at >= LONG_PRESS_MS:
		_long_at = -1
		_long_done = true
		panel.toggle_probe_claim()
	var hud: RelayHud = panel.hud
	var crew_state: CrewState = panel.ctx.crew
	probes.text = hud._probes.text
	mail.text = hud._mail.text
	buttons["launch"].disabled = hud.launch.disabled
	buttons["lanes"].text = hud.lanes.text
	var holder: String = crew_state.claimer(StationViews.CLAIM_PROBE)
	if holder != "" and holder != panel.ctx.settings.player_name:
		buttons["launch"].text = tr("relay.launch") + " · " + holder
	else:
		buttons["launch"].text = tr("relay.launch")
	var mail_none: bool = crew_state.inbox.is_empty()
	buttons["accept"].disabled = mail_none
	buttons["decline"].disabled = mail_none
	var mark: bool = panel._selected_mark() >= 0
	var zone: bool = crew_state.selection.get("kind", "") == "zone"
	var none: bool = crew_state.selection.is_empty()
	for k: String in ["send", "send_mark"]:
		buttons[k].disabled = not mark or hud.allies().is_empty()
	for k: String in ["rename", "attach"]:
		buttons[k].disabled = not mark
	buttons["delete"].disabled = not (mark or zone)
	for k: String in ["centre", "centre_mark", "centre_contact"]:
		buttons[k].disabled = none
	var clear: bool = none and not _route_empty()
	for k: String in ["route", "route_contact"]:
		buttons[k].text = tr("intent.route_clear") if clear else tr("intent.route")
		buttons[k].disabled = none and not clear
	_fill_contacts()
	_fill_marks()
	_fill_log()


## Route: the selection becomes the next waypoint; with nothing selected it clears the
## route (G and Shift+G).
func _route() -> void:
	var clear: bool = panel.ctx.crew.selection.is_empty() and not _route_empty()
	_intent("route_clear" if clear else "route")


func _route_empty() -> bool:
	var routes: Array = panel.ctx.crew.routes
	return routes.is_empty() or (routes[0] as Array).is_empty()


func _intent(id: String) -> void:
	panel.handle_intent({"id": id, "pressed": true})


## A tap on Launch probe launches (to the selection, else arms the map), unless the press
## was long enough to claim.
func _on_launch() -> void:
	if _long_done:
		_long_done = false
		return
	_intent("probe_launch")


func _on_launch_held(down: bool) -> void:
	if down:
		_long_at = panel.ctx.now_ms()
		_long_done = false
	else:
		_long_at = -1


## The Contacts page: the nearest contacts, each a tap to select.
func _fill_contacts() -> void:
	var crew_state: CrewState = panel.ctx.crew
	var rows: Array = panel.hud._contact_rows()
	var key: Array = [rows, crew_state.selection]
	if key == _contact_key:
		return
	_contact_key = key.duplicate(true)
	_clear(_contacts_box)
	for r: Array in rows:
		var id: int = r[0]
		var b: RailButton = RailButton.make(ChipText.chip(r[1], r[2]))
		b.pressed.connect(crew_state.select.bind("contact", id))
		b.add_theme_color_override(
			"font_color", Palette.allegiance_color(Palette.allegiance(str(r[1])))
		)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(crew_state.is_selected("contact", id))
		_contacts_box.add_child(b)


## The Marks page: the marks in use, each a tap to select (the selected one pressed).
func _fill_marks() -> void:
	var crew_state: CrewState = panel.ctx.crew
	var key: Array = [crew_state.marks.duplicate(true), crew_state.selection]
	if key == _mark_key:
		return
	_mark_key = key
	_clear(_marks_box)
	if crew_state.marks.is_empty():
		var none: Label = _label()
		none.text = TouchText.of("relay.no_marks", "No marks yet: drag on the map.")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.clip_text = false
		_marks_box.add_child(none)
	for m: Dictionary in crew_state.marks:
		var slot: int = m["slot"]
		var text: String = str(m["name"])
		if int(m.get("contact", -1)) >= 0:
			text += " · " + panel.ctx.view.callsign(int(m["contact"]))
		var b: RailButton = RailButton.make(text)
		b.pressed.connect(crew_state.select.bind("mark", slot))
		b.toggle_mode = true
		b.set_pressed_no_signal(crew_state.is_selected("mark", slot))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_marks_box.add_child(b)


## The Log page: the inbox, then the ship's log, newest last.
func _fill_log() -> void:
	var crew_state: CrewState = panel.ctx.crew
	var lines: PackedStringArray = []
	for item: Dictionary in crew_state.inbox:
		lines.append(tr("relay.inbox_item") % [item["name"], item["from"]])
	var entries: Array = crew_state.relay_log.slice(-LOG_LINES)
	if entries.is_empty():
		lines.append(tr("relay.log_empty"))
	for e: Dictionary in entries:
		lines.append(RelayHud.log_text(e))
	var text: String = "\n".join(lines)
	if log_text.text != text:
		log_text.text = text


func _clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _label() -> Label:
	var l: Label = Label.new()
	l.add_theme_color_override("font_color", Palette.color("text_dim"))
	l.add_theme_font_size_override("font_size", 13)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A list that scrolls (seven contacts and eight marks outgrow a phone).
func _scrolled(box: VBoxContainer) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return scroll


func _column() -> VBoxContainer:
	var c: VBoxContainer = VBoxContainer.new()
	c.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	return c


func _row(controls: Array) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	for c: Control in controls:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
	return row
