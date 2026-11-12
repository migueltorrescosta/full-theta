class_name RelayHud
extends Control
## The panels around Relay's map (§5.5, FT-RLY-004, FT-RLY-006, FT-RLY-008, FT-RLY-009):
## left, the probes (stock, LAUNCH), the lane and hazard switches, the contacts and the
## marks; below, the ship's log and the inbox of marks other ships sent, each waiting for
## Accept or Decline, with SEND for the selected mark. It reads the model and only emits
## signals; RelayPanel does the sending. No NPC text anywhere (FT-RLY-007): the log is
## keyed lines with numbers and callsigns.

signal launch_pressed
signal hazard_pressed
signal lanes_pressed
signal accept_pressed(id: int)
signal decline_pressed(id: int)
signal send_pressed(ship: int)

## Contacts and log lines listed (the rest scroll off).
const CONTACT_ROWS: int = 7
const LOG_ROWS: int = 4
## The box's top edge (from the bottom) when it is a heading over one row of buttons.
const SHORT_BOX_TOP: float = -82.0
## Least width of the log column.
const LOG_MIN_WIDTH: float = 60.0

var ctx: StationContext
var launch: Button
var lanes: Button
var hazard: Button
var accept: Button
var decline: Button
var send: Button
var send_to: OptionButton
## True while the station's Shakedown step asks for an intent (StationPanel.lesson_wants): a
## control that hides while it can't act shows then, so the lesson never names a hidden one.
var wants: Callable = func(_intent: String) -> bool: return false

var _left: PanelContainer
var _left_margin: MarginContainer
var _left_scroll: ScrollContainer
var _col: VBoxContainer
var _narrow: bool = false
var _short: bool = false
var _log_col: VBoxContainer
var _inbox_heading: Label
var _bottom_row: BoxContainer
var _bottom: PanelContainer
var _probes: Label
var _fab: Label
var _probe_rows: VBoxContainer
var _contacts: VBoxContainer
var _marks: HFlowContainer
var _log: VBoxContainer
var _mail: Label
var _key: Array = []
var _contact_ids: Array = []
var _mark_slots: Array = []
var _ally_list: Array[Dictionary] = []
var _mail_buttons: HBoxContainer


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(context: StationContext) -> void:
	ctx = context
	_left = _box([0.0, 0.0, 0.0, 1.0], [8.0, 8.0, 216.0, -110.0])
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The margin under the scroll makes its last visible row whole at rest (_snap_left).
	_left_margin = MarginContainer.new()
	_left_margin.add_child(scroll)
	_left.add_child(_left_margin)
	_left_scroll = scroll
	_col = col
	_left.resized.connect(_snap_left.call_deferred)
	scroll.add_child(col)
	_probes = Label.new()
	col.add_child(_probes)
	_probe_rows = VBoxContainer.new()
	ListLines.attach(_probe_rows)
	col.add_child(_probe_rows)
	_fab = Label.new()
	col.add_child(_fab)
	launch = _button(col, "Launch", "relay.launch", launch_pressed.emit)
	hazard = _button(col, "Hazard", "relay.hazard", hazard_pressed.emit)
	lanes = _button(col, "Lanes", "relay.lanes_off", lanes_pressed.emit)
	col.add_child(_heading("relay.contacts"))
	_contacts = VBoxContainer.new()
	ListLines.attach(_contacts)
	col.add_child(_contacts)
	col.add_child(_heading("relay.marks"))
	_marks = HFlowContainer.new()
	col.add_child(_marks)
	_bottom = _box([0.0, 1.0, 1.0, 1.0], [224.0, -102.0, -8.0, -8.0])
	# Tap-sized buttons make the box taller than its 94 px: it grows upward (D194).
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row: BoxContainer = BoxContainer.new()
	_bottom_row = row
	row.add_theme_constant_override("separation", 16)
	_bottom.add_child(row)
	var log_col: VBoxContainer = VBoxContainer.new()
	log_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The inbox buttons take what they need; the log wraps in what is left.
	log_col.custom_minimum_size.x = LOG_MIN_WIDTH
	_log_col = log_col
	log_col.add_child(_heading("relay.log"))
	_log = VBoxContainer.new()
	ListLines.attach(_log)
	log_col.add_child(_log)
	row.add_child(log_col)
	var mail: BoxContainer = BoxContainer.new()
	mail.vertical = true
	mail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inbox_heading = _heading("relay.inbox")
	mail.add_child(_inbox_heading)
	_mail = Label.new()
	_mail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mail.add_child(_mail)
	var buttons: HBoxContainer = HBoxContainer.new()
	_mail_buttons = buttons
	accept = _button(buttons, "Accept", "relay.accept", _on_accept)
	decline = _button(buttons, "Decline", "relay.decline", _on_decline)
	send_to = OptionButton.new()
	send_to.name = "SendTo"
	buttons.add_child(send_to)
	send = _button(buttons, "Send", "relay.send", _on_send)
	mail.add_child(buttons)
	row.add_child(mail)
	_bottom.resized.connect(_fit_left)
	ctx.crew.changed.connect(func(_what: StringName) -> void: refresh())
	refresh()


## Re-reads the model; cheap when nothing changed.
func refresh() -> void:
	if ctx == null:
		return
	var blk: Dictionary = ctx.snap.blocks.get(StationCatalogue.Section.RELAY, {})
	var near: Array = _contact_rows()
	var key: Array = [blk, near, ctx.crew.marks, ctx.crew.inbox, ctx.crew.relay_log]
	key.append_array([ctx.crew.selection, ctx.crew.catalogue.get("ships", [])])
	key.append(_lesson_key())
	if key == _key:
		return
	_key = key.duplicate(true)
	var stock: int = int(blk.get("stock", 0))
	var out: int = (blk.get("probes", []) as Array).size()
	_probes.text = tr("relay.probes") % [stock, out]
	_clear(_probe_rows)
	for pr: Dictionary in blk.get("probes", []):
		var flying: bool = not bool(pr["deployed"])
		_probe_rows.add_child(
			_dim(
				(
					tr("relay.probe_flying" if flying else "relay.probe_ready")
					% (int(pr["serial"]) + 1)
				)
			)
		)
	var fab: float = float(blk.get("fab_left", 0.0))
	_fab.text = tr("relay.fab") % ceili(fab) if fab > 0.0 else ""
	_fab.visible = fab > 0.0
	# Launch shows only with a probe in stock (C3: no dead button; the line above says
	# "0 left"), or while the Shakedown's probe or claim step names it.
	launch.visible = stock > 0 or wants.call("probe_launch") or wants.call("claim")
	lanes.text = tr("relay.lanes_on" if bool(blk.get("lanes", false)) else "relay.lanes_off")
	_fill_contacts(near)
	_fill_marks()
	_fill_log()
	_fill_inbox()
	_snap_left.call_deferred()


func _snap_left() -> void:
	if _left_margin != null and is_inside_tree():
		ScrollSnap.fit(_left_scroll, _left_margin, _col)


## A phone-wide HUD (D195): the probe and contact column spans the top, the log and inbox
## stack at the bottom, so the map keeps the middle.
func set_narrow(narrow: bool) -> void:
	_bottom_row.vertical = narrow
	_place(_left, [0.0, 0.0, 1.0, 0.0] if narrow else [0.0, 0.0, 0.0, 1.0])
	_left.offset_left = 8.0
	_left.offset_top = 8.0
	_left.offset_right = -8.0 if narrow else 216.0
	_left.offset_bottom = 230.0 if narrow else -110.0
	_place(_bottom, [0.0, 1.0, 1.0, 1.0])
	_bottom.offset_left = 8.0 if narrow else 224.0
	_bottom.offset_right = -8.0
	_bottom.offset_top = -170.0 if narrow else (SHORT_BOX_TOP if _short else -102.0)
	_bottom.offset_bottom = -8.0
	_narrow = narrow
	_fit_left()


## A short HUD (a window about 480 px tall): the log goes and the inbox is its heading, with
## the waiting mark after it, over one row of buttons, so the box stops covering the map's
## lower part and still names itself.
func set_short(short: bool) -> void:
	_short = short
	_log_col.visible = not short
	_inbox_heading.clip_text = short
	_inbox_heading.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS if short else TextServer.OVERRUN_NO_TRIMMING
	)
	_inbox_heading.custom_minimum_size.x = 60.0 if short else 0.0
	_show_mail()
	_fill_inbox_heading()
	if not _narrow:
		_bottom.offset_top = SHORT_BOX_TOP if short else -102.0
	_fit_left()


## Top of the log and inbox box, in the HUD's coordinates (the map's caption sits above it).
func bottom_top() -> float:
	return _bottom.position.y


## The part of the panel the HUD's boxes leave to the map (the panel's coordinates): right
## of the probe column and above the log box, or between them when narrow. The map centres
## and fits in it, so no item sits under an opaque box (D319).
func free_rect() -> Rect2:
	if not visible or _left == null or size.x <= 0.0:
		return Rect2()
	var top: float = _left.position.y + _left.size.y + 8.0 if _narrow else 0.0
	var left: float = 0.0 if _narrow else _left.position.x + _left.size.x + 8.0
	var bottom: float = _bottom.position.y - 8.0
	return Rect2(left, top, size.x - left, maxf(bottom - top, 0.0))


## Narrow: the probe column ends above the bottom box, which grows upward with
## its content (tap-sized buttons, a wrapped inbox), instead of lying over the contacts.
func _fit_left() -> void:
	if not _narrow:
		_left.offset_bottom = -8.0 if _short else -110.0
		return
	# 24 px stay free for the map's span caption.
	_left.offset_bottom = clampf(_bottom.position.y - 30.0, 64.0, 230.0)


## Whether the HUD is shown (not in the docked view).
func set_docked(docked: bool) -> void:
	visible = not docked


## The log line of an entry in the session language: its key's text with the entry's
## numbers and callsigns (FT-RLY-006, FT-RLY-007).
static func log_text(entry: Dictionary) -> String:
	var args: Dictionary = entry.get("args", {})
	var text: String = String(TranslationServer.translate("relay.log." + str(entry["key"])))
	for k: String in ["callsign", "name", "from"]:
		if args.has(k):
			return text % str(args[k])
	if args.has("n"):
		return text % int(args["n"])
	if args.has("route"):
		return text % int(args["route"])
	return text


## The ships of the own faction other than this one: [{"id", "name"}].
func allies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ships: Array = ctx.crew.catalogue.get("ships", [])
	var faction: int = -1
	for s: Dictionary in ships:
		if int(s["id"]) == ctx.crew.ship:
			faction = int(s["faction"])
	for s: Dictionary in ships:
		if int(s["id"]) != ctx.crew.ship and int(s["faction"]) == faction:
			out.append({"id": int(s["id"]), "name": str(s["name"])})
	return out


## The ship the SEND button targets, -1 without an ally.
func send_target() -> int:
	return int(send_to.get_selected_metadata()) if send_to.item_count > 0 else -1


func _contact_rows() -> Array:
	var rows: Array = []
	for it: Dictionary in ctx.picture().contacts_by_range(CONTACT_ROWS):
		rows.append([it["id"], it["label"], (it["local"] as Vector3).snappedf(50.0)])
	return rows


## Buttons are kept while the same items are listed and only their text and state change,
## so a press that lands during a refresh still arrives (a rebuild eats the click).
func _fill_contacts(rows: Array) -> void:
	var ids: Array = rows.map(func(r: Array) -> Variant: return r[0])
	if ids != _contact_ids:
		_contact_ids = ids
		_clear(_contacts)
		for r: Array in rows:
			var b: Button = Button.new()
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var id: int = r[0]
			b.pressed.connect(func() -> void: ctx.crew.select("contact", id))
			_contacts.add_child(b)
	for i: int in rows.size():
		var b: Button = _contacts.get_child(i) as Button
		var r: Array = rows[i]
		b.text = CalloutText.callout(r[1], r[2])
		b.add_theme_color_override(
			"font_color", Palette.allegiance_color(Palette.allegiance(str(r[1])))
		)


func _fill_marks() -> void:
	var slots: Array = ctx.crew.marks.map(func(m: Dictionary) -> Variant: return m["slot"])
	if slots != _mark_slots:
		_mark_slots = slots
		_clear(_marks)
		for m: Dictionary in ctx.crew.marks:
			var b: Button = Button.new()
			b.toggle_mode = true
			var slot: int = m["slot"]
			b.pressed.connect(func() -> void: ctx.crew.select("mark", slot))
			_marks.add_child(b)
	for i: int in ctx.crew.marks.size():
		var m: Dictionary = ctx.crew.marks[i]
		var b: Button = _marks.get_child(i) as Button
		b.text = CalloutText.mark_label(m, ctx.snap)
		b.set_pressed_no_signal(ctx.crew.is_selected("mark", m["slot"]))


func _fill_log() -> void:
	_clear(_log)
	var entries: Array = ctx.crew.relay_log.slice(-LOG_ROWS)
	if entries.is_empty():
		_log.add_child(_wrapped(tr("relay.log_empty")))
	for e: Dictionary in entries:
		_log.add_child(_wrapped(log_text(e)))


## A short box has room for one line under its heading: the inbox line when no button row
## shows, else the buttons, the heading then carrying the line ("INBOX  Name from Ship +1",
## "INBOX  No marks waiting").
func _show_mail() -> void:
	_mail.visible = not _short or (_mail_buttons != null and not _mail_buttons.visible)


func _fill_inbox_heading() -> void:
	var text: String = tr("relay.inbox").to_upper()
	if not _mail.visible:
		text += "  " + _mail.text
	_inbox_heading.text = text


func _fill_inbox() -> void:
	var item: Dictionary = {} if ctx.crew.inbox.is_empty() else ctx.crew.inbox[0]
	if item.is_empty():
		_mail.text = tr("relay.no_mail")
	else:
		var more: String = " +%d" % (ctx.crew.inbox.size() - 1) if ctx.crew.inbox.size() > 1 else ""
		_mail.text = tr("relay.inbox_item") % [item["name"], item["from"]] + more
	# Accept and Decline show only with a mark waiting (the line says "No marks waiting").
	accept.visible = not item.is_empty() or wants.call("accept")
	decline.visible = not item.is_empty() or wants.call("decline")
	var targets: Array = allies()
	if targets != _ally_list:
		_ally_list = targets
		var kept: int = send_target()
		send_to.clear()
		for a: Dictionary in targets:
			send_to.add_item(a["name"])
			send_to.set_item_metadata(send_to.item_count - 1, a["id"])
			if a["id"] == kept:
				send_to.select(send_to.item_count - 1)
	# Send and its ship list show only with an ally to send to and a mark selected; the row
	# goes when none of its buttons shows.
	send.visible = can_send() or wants.call("mark_send")
	send_to.visible = send.visible and send_to.item_count > 0
	_mail_buttons.visible = accept.visible or decline.visible or send.visible
	_show_mail()
	_fill_inbox_heading()


## True when a mark is selected and an allied ship can take it.
func can_send() -> bool:
	return not allies().is_empty() and ctx.crew.selection.get("kind", "") == "mark"


## What the lesson steps ask that changes which buttons show.
func _lesson_key() -> Array:
	var out: Array = []
	for id: String in ["probe_launch", "claim", "accept", "decline", "mark_send"]:
		out.append(wants.call(id))
	return out


func _on_accept() -> void:
	if not ctx.crew.inbox.is_empty():
		accept_pressed.emit(ctx.crew.inbox[0]["id"])


func _on_decline() -> void:
	if not ctx.crew.inbox.is_empty():
		decline_pressed.emit(ctx.crew.inbox[0]["id"])


func _on_send() -> void:
	if send_target() >= 0:
		send_pressed.emit(send_target())


func _place(box: Control, anchors: Array) -> void:
	box.anchor_left = anchors[0]
	box.anchor_top = anchors[1]
	box.anchor_right = anchors[2]
	box.anchor_bottom = anchors[3]


## A translucent panel with anchors and offsets as [left, top, right, bottom].
func _box(anchors: Array, offsets: Array) -> PanelContainer:
	var box: PanelContainer = PanelContainer.new()
	_place(box, anchors)
	box.offset_left = offsets[0]
	box.offset_top = offsets[1]
	box.offset_right = offsets[2]
	box.offset_bottom = offsets[3]
	box.add_theme_stylebox_override("panel", UiTheme.box("panel", "line_strong", 6, 6, 0.85))
	add_child(box)
	return box


func _button(parent: Node, id: String, key: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = id
	b.text = tr(key)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _heading(key: String) -> Label:
	var l: Label = Label.new()
	l.text = tr(key).to_upper()
	l.add_theme_color_override("font_color", Palette.color("text_dim"))
	return l


func _dim(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.color("text_dim"))
	l.clip_text = true
	return l


## A dim label that wraps in the column instead of clipping.
func _wrapped(text: String) -> Label:
	var l: Label = _dim(text)
	l.clip_text = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
