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

var ctx: StationContext
var launch: Button
var lanes: Button
var hazard: Button
var accept: Button
var decline: Button
var send: Button
var send_to: OptionButton

var _left: PanelContainer
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
	_left.add_child(scroll)
	scroll.add_child(col)
	_probes = Label.new()
	col.add_child(_probes)
	_probe_rows = VBoxContainer.new()
	col.add_child(_probe_rows)
	_fab = Label.new()
	col.add_child(_fab)
	launch = _button(col, "Launch", "relay.launch", launch_pressed.emit)
	hazard = _button(col, "Hazard", "relay.hazard", hazard_pressed.emit)
	lanes = _button(col, "Lanes", "relay.lanes_off", lanes_pressed.emit)
	col.add_child(_heading("relay.contacts"))
	_contacts = VBoxContainer.new()
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
	log_col.add_child(_heading("relay.log"))
	_log = VBoxContainer.new()
	log_col.add_child(_log)
	row.add_child(log_col)
	var mail: VBoxContainer = VBoxContainer.new()
	mail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mail.add_child(_heading("relay.inbox"))
	_mail = Label.new()
	_mail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mail.add_child(_mail)
	var buttons: HBoxContainer = HBoxContainer.new()
	accept = _button(buttons, "Accept", "relay.accept", _on_accept)
	decline = _button(buttons, "Decline", "relay.decline", _on_decline)
	send_to = OptionButton.new()
	send_to.name = "SendTo"
	buttons.add_child(send_to)
	send = _button(buttons, "Send", "relay.send", _on_send)
	mail.add_child(buttons)
	row.add_child(mail)
	ctx.crew.changed.connect(func(_what: StringName) -> void: refresh())
	refresh()


## Re-reads the model; cheap when nothing changed.
func refresh() -> void:
	if ctx == null:
		return
	var blk: Dictionary = ctx.view.blocks.get(StationViews.Section.RELAY, {})
	var near: Array = _contact_rows()
	var key: Array = [blk, near, ctx.crew.marks, ctx.crew.inbox, ctx.crew.relay_log]
	key.append_array([ctx.crew.selection, ctx.crew.catalogue.get("ships", [])])
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
	launch.disabled = stock <= 0
	lanes.text = tr("relay.lanes_on" if bool(blk.get("lanes", false)) else "relay.lanes_off")
	_fill_contacts(near)
	_fill_marks()
	_fill_log()
	_fill_inbox()


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
	_bottom.offset_top = -170.0 if narrow else -102.0
	_bottom.offset_bottom = -8.0


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
	for it: Dictionary in ctx.picture().items:
		if it["kind"] == "contact":
			rows.append([it["id"], it["label"], (it["local"] as Vector3).snappedf(50.0)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[2].length() < b[2].length())
	return rows.slice(0, CONTACT_ROWS)


func _fill_contacts(rows: Array) -> void:
	_clear(_contacts)
	for r: Array in rows:
		var b: Button = Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = ChipText.chip(r[1], r[2])
		b.add_theme_color_override(
			"font_color", Palette.allegiance_color(Palette.allegiance(str(r[1])))
		)
		var id: int = r[0]
		b.pressed.connect(func() -> void: ctx.crew.select("contact", id))
		_contacts.add_child(b)


func _fill_marks() -> void:
	_clear(_marks)
	for m: Dictionary in ctx.crew.marks:
		var b: Button = Button.new()
		b.text = str(m["name"])
		b.toggle_mode = true
		b.button_pressed = ctx.crew.is_selected("mark", m["slot"])
		var slot: int = m["slot"]
		b.pressed.connect(func() -> void: ctx.crew.select("mark", slot))
		_marks.add_child(b)


func _fill_log() -> void:
	_clear(_log)
	var entries: Array = ctx.crew.relay_log.slice(-LOG_ROWS)
	if entries.is_empty():
		_log.add_child(_dim(tr("relay.log_empty")))
	for e: Dictionary in entries:
		_log.add_child(_dim(log_text(e)))


func _fill_inbox() -> void:
	var item: Dictionary = {} if ctx.crew.inbox.is_empty() else ctx.crew.inbox[0]
	if item.is_empty():
		_mail.text = tr("relay.no_mail")
	else:
		var more: String = " +%d" % (ctx.crew.inbox.size() - 1) if ctx.crew.inbox.size() > 1 else ""
		_mail.text = tr("relay.inbox_item") % [item["name"], item["from"]] + more
	accept.disabled = item.is_empty()
	decline.disabled = item.is_empty()
	var kept: int = send_target()
	send_to.clear()
	for a: Dictionary in allies():
		send_to.add_item(a["name"])
		send_to.set_item_metadata(send_to.item_count - 1, a["id"])
		if a["id"] == kept:
			send_to.select(send_to.item_count - 1)
	send.disabled = send_to.item_count == 0 or ctx.crew.selection.get("kind", "") != "mark"


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
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Palette.color("panel") * Color(1, 1, 1, 0.85)
	style.set_content_margin_all(6.0)
	box.add_theme_stylebox_override("panel", style)
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


func _clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
