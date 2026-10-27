class_name RelayPhone
extends Control
## Relay on a phone (#28, owner pick 2026-10-28: overlay rails, A). Landscape: the map
## fills the panel under two translucent thumb rails, the probe tools and the mark on the
## left, every inbox action on the right, the contacts and the share buttons in drawers;
## the probe count and the waiting mark read across the map's top edge.
## Upright (the reduced layout under the screen's "turn sideways" banner): the map on top
## and the same buttons in rows below it, the drawers over the map. The buttons emit the
## HUD's signals or call the panel's commands, so a tap does what the HUD button and the
## key do; the HUD itself hides. The mark button selects the next mark (for Send).

const RAIL_W: float = 168.0
const DRAWER_W: float = 240.0
## The probe and inbox line over the map (landscape), and the armed hint below it.
const LINE_H: float = 28.0

var panel: RelayPanel
var form: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE
var layout: RailLayout
var launch: RailButton
var hazard: RailButton
var lanes: RailButton
var mark: RailButton
var contacts_button: RailButton
var accept: RailButton
var decline: RailButton
var send: RailButton
var share_button: RailButton
var contacts: TouchDrawer
var share: TouchDrawer
var share_bar: ShareBar
var probes: Label
var mail: Label

var _contact_box: VBoxContainer
var _contact_key: Array = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A gap under the top bar, so its buttons and the first rail button are apart.
	offset_top = UiTheme.TOUCH_GAP
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Hides the HUD and builds the phone arrangement for `phone_form` around the map.
func build(p: RelayPanel, phone_form: LayoutMode.Form) -> void:
	panel = p
	form = phone_form
	var hud: RelayHud = panel.hud
	launch = _button(hud.launch.text, func() -> void: hud.launch_pressed.emit())
	hazard = _button(hud.hazard.text, func() -> void: hud.hazard_pressed.emit())
	lanes = _button(hud.lanes.text, func() -> void: hud.lanes_pressed.emit())
	mark = _button(tr("relay.marks"), _next_mark)
	contacts_button = _button(tr("relay.contacts") + " ▸", Callable())
	accept = _button(hud.accept.text, hud._on_accept)
	decline = _button(hud.decline.text, hud._on_decline)
	send = _button(hud.send.text, hud._on_send)
	share_button = _button(TouchText.of("relay.share", "Share") + " ▸", Callable())
	probes = _label()
	mail = _label()
	layout = RailLayout.new()
	contacts = TouchDrawer.new(tr("relay.contacts"), SIDE_LEFT)
	_contact_box = _scrolled(contacts)
	share = TouchDrawer.new(TouchText.of("relay.share", "Share"), SIDE_RIGHT)
	share_bar = ShareBar.new()
	share_bar.button_h = UiTheme.TOUCH_PRIMARY
	share_bar.min_width = DRAWER_W - 24.0
	share_bar.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	share_bar.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	share_bar.share_pressed.connect(
		func(id: StringName) -> void: panel.ctx.intents.share(String(id))
	)
	_scrolled(share).add_child(share_bar)
	var send_to: OptionButton = hud.send_to
	send_to.custom_minimum_size.y = UiTheme.TOUCH_PRIMARY
	if form == LayoutMode.Form.PHONE_LANDSCAPE:
		add_child(layout)
		layout.set_content(panel.map)
		var left: TouchRail = layout.rail(SIDE_LEFT)
		left.custom_minimum_size.x = RAIL_W
		for c: Control in [launch, hazard, lanes, mark, contacts_button]:
			left.add(c)
		var right: TouchRail = layout.rail(SIDE_RIGHT)
		right.custom_minimum_size.x = RAIL_W
		for c: Control in [accept, decline]:
			right.add(c)
		send_to.reparent(right.box, false)
		send_to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for c: Control in [send, share_button]:
			right.add(c)
		# The rails have room for five buttons only: the probe and inbox lines go over
		# the map's top edge, between the rails.
		mail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for l: Label in [probes, mail]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
	else:
		var col: VBoxContainer = _column()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(col)
		layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(layout)
		layout.set_content(panel.map)
		col.add_child(_row([probes, mail]))
		col.add_child(_row([launch, hazard]))
		col.add_child(_row([lanes, mark]))
		col.add_child(_row([accept, decline]))
		var sends: HBoxContainer = _row([send])
		send_to.reparent(sends, false)
		sends.move_child(send_to, 0)
		send_to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(sends)
		col.add_child(_row([contacts_button, share_button]))
	for d: TouchDrawer in [contacts, share]:
		d.custom_minimum_size.x = DRAWER_W
		layout.add_drawer(d)
	contacts.bind_opener(contacts_button)
	share.bind_opener(share_button)
	layout.content_rect_changed.connect(_place_view)
	hud.visible = false


## Gives the map and the send menu back to the panel and the HUD.
func release() -> void:
	layout.content_rect_changed.disconnect(_place_view)
	var hud: RelayHud = panel.hud
	panel.map.reparent(panel, false)
	panel.move_child(panel.map, 0)
	panel.map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.map.view_rect = Rect2()
	hud.send_to.custom_minimum_size.y = 0.0
	hud.send_to.disabled = false
	if hud.send_to.item_count == 0:
		hud.send_to.text = ""
	hud.send_to.size_flags_horizontal = 0
	hud.send_to.reparent(hud._mail_buttons, false)
	hud._mail_buttons.move_child(hud.send_to, 2)
	panel._hint.offset_left = 260.0
	panel._hint.offset_right = -8.0
	panel._hint.offset_top = 8.0
	hud.set_docked(panel.docked)


## The map centres in the uncovered part; an armed probe or hazard's hint sits above it.
func _place_view(rect: Rect2) -> void:
	var r: Rect2 = layout.content_rect_in(panel.map) if rect.has_area() else Rect2()
	panel.map.view_rect = r
	panel._hint.offset_left = r.position.x + 8.0
	panel._hint.offset_right = -(panel.size.x - r.end.x) - 8.0
	if probes.get_parent() == self:
		var half: float = maxf(r.size.x / 2.0 - 12.0, 1.0)
		probes.position = r.position + Vector2(8.0, 4.0)
		mail.position = Vector2(r.get_center().x + 4.0, r.position.y + 4.0)
		for l: Label in [probes, mail]:
			l.size = Vector2(half, l.get_combined_minimum_size().y)
		panel._hint.offset_top = position.y + r.position.y + LINE_H
	panel.map.queue_redraw()


## Mirrors the HUD each frame: texts and enabled states, the contacts and the shares.
func update() -> void:
	var hud: RelayHud = panel.hud
	probes.text = hud._probes.text
	mail.text = hud._mail.text
	launch.disabled = hud.launch.disabled
	lanes.text = hud.lanes.text
	accept.disabled = hud.accept.disabled
	decline.disabled = hud.decline.disabled
	send.disabled = hud.send.disabled
	# An empty menu reads as broken on a phone: say why it is empty.
	var none: bool = hud.send_to.item_count == 0
	hud.send_to.disabled = none
	if none:
		hud.send_to.text = tr("relay.no_allies")
	var crew: CrewState = panel.ctx.crew
	var sel: Dictionary = crew.mark_in_slot(panel._selected_mark())
	mark.text = str(sel["name"]) if not sel.is_empty() else tr("relay.marks")
	mark.disabled = crew.marks.is_empty()
	_fill_contacts()
	var shares: Array[StringName] = []
	var mine: Array[String] = [panel.station]
	if crew.is_crew():
		shares = ShareBar.features(mine, crew.toggles)
	var left: Dictionary = {}
	for id: StringName in crew.shares:
		left[id] = crew.share_left(id, panel.ctx.now_ms())
	share_bar.show_features(shares, left)
	share_button.disabled = shares.is_empty()


## Selects the mark after the selected one (the first when none is), for Send.
func _next_mark() -> void:
	var crew: CrewState = panel.ctx.crew
	if crew.marks.is_empty():
		return
	var at: int = -1
	for i: int in crew.marks.size():
		if int(crew.marks[i]["slot"]) == panel._selected_mark():
			at = i
	crew.select("mark", int(crew.marks[(at + 1) % crew.marks.size()]["slot"]))


## The contacts drawer: the HUD's nearest contacts, then the marks, each a tap to select.
func _fill_contacts() -> void:
	var crew: CrewState = panel.ctx.crew
	var rows: Array = panel.hud._contact_rows()
	var key: Array = [rows, crew.marks, crew.selection]
	if key == _contact_key:
		return
	_contact_key = key.duplicate(true)
	for c: Node in _contact_box.get_children():
		_contact_box.remove_child(c)
		c.queue_free()
	for r: Array in rows:
		var id: int = r[0]
		var b: RailButton = _button(ChipText.chip(r[1], r[2]), crew.select.bind("contact", id))
		b.add_theme_color_override(
			"font_color", Palette.allegiance_color(Palette.allegiance(str(r[1])))
		)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_contact_box.add_child(b)
	for m: Dictionary in crew.marks:
		var slot: int = m["slot"]
		var b: RailButton = _button(str(m["name"]), crew.select.bind("mark", slot))
		b.toggle_mode = true
		b.set_pressed_no_signal(crew.is_selected("mark", slot))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_contact_box.add_child(b)


func _button(text: String, handler: Callable) -> RailButton:
	var b: RailButton = RailButton.make(text)
	if handler.is_valid():
		b.pressed.connect(handler)
	return b


func _label() -> Label:
	var l: Label = Label.new()
	l.add_theme_color_override("font_color", Palette.color("text_dim"))
	l.add_theme_font_size_override("font_size", 13)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A drawer's body that scrolls (seven contacts and eight marks outgrow a phone).
func _scrolled(d: TouchDrawer) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.body.add_child(scroll)
	var box: VBoxContainer = _column()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


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
