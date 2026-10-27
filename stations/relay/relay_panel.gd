class_name RelayPanel
extends StationPanel
## Relay (T054, §5.5, E02): the map read-out (RelayMap), the marks it curates (FT-RLY-001
## to FT-RLY-003, FT-SPA-006, FT-M1-017), probes (P launches one to the selection, else
## arms the next click; H the same for a hazard zone), routes (G adds the selection as a
## waypoint, Shift+G clears), lane flagging (L), and the HUD around the map (RelayHud):
## probes, contacts, marks, the ship's log and the inbox of marks other ships sent
## (Enter accepts and Backspace declines the oldest, X sends the selected mark to the
## ship chosen beside SEND). The main-screen view switch comes with the Captain (F).
##
## KB/M: drag on empty map places a mark on the view plane through the map centre
## (FT-RLY-002); drag a mark to move it, drop it on a contact to attach it; hold Shift
## while dragging to push the point along the view direction (depth); right-drag
## turns the map, the wheel zooms. N renames the selected mark, Delete deletes it, M
## attaches it to the nearest contact or frees it where it is, C centres the map on
## the selection (again: back on the ship). With 8 marks in use a new mark replaces
## the selected mark, else it is refused with a toast (FT-SPA-022).
## Controller: the left stick moves a cursor, the triggers its depth, the right stick
## turns the map; A, R3 and hold R3 select, ping and mark at the cursor (§5.0).
## Touch: the HUD's buttons and drags on the map; a lone Relay panel on a phone puts the
## buttons in thumb rails over the full map instead (RelayPhone, #28) and drops the
## screen's radar column.

## Under this width (a phone, D195) the HUD stacks around the map.
const NARROW_W: float = 560.0
## Under this height the HUD's bottom box is one row (a phone on its side).
const SHORT_H: float = 480.0
## A press that moves less than this is a click (select), not a drag (px).
const DRAG_PX: float = 6.0
## Controller cursor speed (px/s), depth speed (map spans/s), turn speed (px-equivalent/s).
const PAD_CURSOR_PX_S: float = 420.0
const PAD_DEPTH_SPANS_S: float = 0.5
const PAD_TURN_PX_S: float = 160.0
## A new hazard zone's radius (m). PROVISIONAL.
const HAZARD_RADIUS_M: float = 2000.0

var map: RelayMap
var hud: RelayHud
## The phone arrangement (RelayPhone), null in the wide layout.
var phone: RelayPhone
## What the next click on the map places: "" (a mark), "probe" or "hazard".
var armed: String = ""
var _hint: Label
var _rename: LineEdit
## The drag in progress: {"slot" (-1 places a new mark), "start", "plane" (px), "depth"
## (m), "moved"}, or {}.
var _drag: Dictionary = {}
var _turning: bool = false
var _centred: bool = false
var _cursor: Vector2 = Vector2(-1, -1)
var _cursor_depth: float = 0.0
var _rename_slot: int = -1


func _setup() -> void:
	clip_contents = true
	map = RelayMap.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(map)
	_hint = Label.new()
	_hint.text = tr("relay.hint")
	_hint.add_theme_color_override("font_color", Palette.color("text_dim"))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_left = 260.0
	_hint.offset_right = -8.0
	_hint.offset_top = 8.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	hud = RelayHud.new()
	add_child(hud)
	hud.setup(ctx)
	resized.connect(
		func() -> void:
			hud.set_narrow(size.x < NARROW_W)
			hud.set_short(size.x >= NARROW_W and size.y < SHORT_H)
			_arrange()
	)
	hud.launch_pressed.connect(func() -> void: _arm("probe"))
	hud.hazard_pressed.connect(func() -> void: _arm("hazard"))
	hud.lanes_pressed.connect(_toggle_lanes)
	hud.accept_pressed.connect(_accept)
	hud.decline_pressed.connect(func(id: int) -> void: ctx.intents.decline_mark(id))
	hud.send_pressed.connect(_send_selected)
	_rename = LineEdit.new()
	_rename.name = "Rename"
	_rename.visible = false
	_rename.custom_minimum_size = Vector2(220, 0)
	_rename.position = Vector2(12, 12)
	_rename.text_submitted.connect(_on_rename)
	_rename.focus_exited.connect(func() -> void: _rename.visible = false)
	add_child(_rename)
	refresh()


func _mode_changed() -> void:
	map.chips = not docked
	_arrange()
	_update_hint()
	hud.set_docked(docked or phone != null)


## A lone panel on a phone takes the whole screen in the phone arrangement (#28).
func full_screen() -> bool:
	return _wants_phone()


func _wants_phone() -> bool:
	if docked or not is_inside_tree() or ctx.crew.stations().size() > 1:
		return false
	return LayoutMode.is_phone(RelayPhone.form_of_panel(self))


## Builds, rebuilds (a turned phone) or drops the phone arrangement.
func _arrange() -> void:
	var want: bool = _wants_phone()
	var form: LayoutMode.Form = RelayPhone.form_of_panel(self) if want else LayoutMode.Form.DESKTOP
	if want and phone != null and phone.form == form:
		return
	if not want and phone == null:
		return
	if phone != null:
		phone.release()
		phone.queue_free()
		phone = null
	if want:
		phone = RelayPhone.new()
		add_child(phone)
		move_child(phone, hud.get_index())
		phone.build(self, form)
	refresh()


## The hint sits top right over the map; a phone-wide HUD covers that corner, so there it
## only shows while a probe or hazard is armed. A phone shows it only then too: its
## mouse-and-keyboard text means nothing on a touch screen (#28).
func _update_hint() -> void:
	var wide: bool = size.x >= NARROW_W and phone == null
	_hint.visible = not docked and (armed != "" or wide)


func _process(delta: float) -> void:
	if focused:
		_poll_pad(delta)
	refresh()


## Pushes the current picture into the map (every frame; tests call it directly).
func refresh() -> void:
	map.picture = ctx.picture()
	map.selected = ctx.crew.selection
	if ctx.crew.selection.is_empty():
		_centred = false
	map.centre = ctx.crew.selection if _centred else {}
	map.cursor_on = focused and ctx.matcher.device == IntentTable.PAD
	if _cursor.x < 0.0 and size.x > 0.0:
		_cursor = size / 2.0
	map.cursor = _cursor
	var blk: Dictionary = ctx.view.blocks.get(StationViews.Section.RELAY, {})
	map.probes = blk.get("probes", [])
	map.lanes_on = bool(blk.get("lanes", false))
	map.routes = ctx.crew.routes
	# Narrow, the log and inbox box covers the map's bottom edge: the span caption sits above it.
	map.caption_bottom = hud.bottom_top() if hud.visible and size.x < NARROW_W else -1.0
	map.queue_redraw()
	hud.refresh()
	if phone != null:
		phone.update()
	_hint.text = tr("relay.armed_" + armed) if armed != "" else tr("relay.hint")
	_update_hint()


func handle_intent(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)):
		return false
	var handled: bool = true
	match str(ev["id"]):
		"mark_delete":
			var slot: int = _selected_mark()
			if slot < 0:
				handled = _delete_zone()
			else:
				ctx.intents.delete_mark(slot)
		"mark_rename":
			handled = _start_rename()
		"mark_attach":
			handled = _toggle_attach()
		"map_centre":
			_centred = not _centred and not ctx.crew.selection.is_empty()
			refresh()
		"probe_launch":
			_to_selection_or_arm("probe")
		"hazard_add":
			_to_selection_or_arm("hazard")
		"route":
			handled = _route_to_selection()
		"route_clear":
			ctx.intents.route_clear(0)
		"flag_lanes":
			_toggle_lanes()
		"mark_send":
			handled = _send_selected(hud.send_target())
		"accept", "decline":
			handled = _answer_oldest(str(ev["id"]) == "accept")
		_:
			handled = _main_view(str(ev["id"]))
	return handled


## Alt+1 to Alt+5: Relay switches the main screen's view while no Captain is seated
## (FT-RLY-010, D88); with one the server would refuse, so say so instead.
func _main_view(id: String) -> bool:
	var n: String = id.trim_prefix("main_view_")
	if n == id or not n.is_valid_int():
		return false
	if not ctx.crew.may_switch_main_view():
		ctx.crew.toast.emit("toast.captain_seated", {})
		return true
	ctx.intents.set_main_view(n.to_int() - 1)
	return true


## Accepts or declines the oldest mark in the inbox (Enter / Backspace, X / Y).
func _answer_oldest(accept: bool) -> bool:
	if ctx.crew.inbox.is_empty():
		return false
	var id: int = ctx.crew.inbox[0]["id"]
	if accept:
		_accept(id)
	else:
		ctx.intents.decline_mark(id)
	return true


## A contact or mark under the pointer, else the map point there (on the view plane;
## at the controller cursor's depth under the cursor), for select, ping and mark.
func item_at(screen_pos: Vector2) -> Dictionary:
	refresh()
	var hit: Dictionary = map.item_at(screen_pos)
	if not hit.is_empty():
		return hit
	var depth: float = _cursor_depth if screen_pos.distance_to(_cursor) < 1.0 else 0.0
	return _point(map.unproject(screen_pos, depth))


func cursor_pos() -> Vector2:
	return _cursor if _cursor.x >= 0.0 else size / 2.0


## FT-SPA-022: Relay replaces the selected mark when all 8 are used.
func replace_mark(item: Dictionary) -> bool:
	var slot: int = _selected_mark()
	if slot < 0 or item.get("kind", "") not in ["contact", "point"]:
		return false
	ctx.mark_item(slot, item)
	return true


## The claim K takes or releases: the probe launcher (a second Relay seat waits for it).
func claim_item() -> String:
	return StationViews.CLAIM_PROBE


## P and H: with something selected the probe or hazard goes to it; else the next click on
## the map places it (the same key again lets go).
func _to_selection_or_arm(what: String) -> void:
	var at: Variant = _selection_pos()
	if at == null:
		_arm(what)
	else:
		_place(what, at)


## Arms what the next click places; the same again disarms.
func _arm(what: String) -> void:
	armed = "" if armed == what else what
	refresh()


## Sends a probe or a hazard zone to a point (m).
func _place(what: String, at: Vector3) -> void:
	if what == "probe":
		var blk: Dictionary = ctx.view.blocks.get(StationViews.Section.RELAY, {})
		if int(blk.get("stock", 1)) <= 0:
			ctx.crew.toast.emit("toast.relay_no_probes", {})
			return
		ctx.intents.command({"kind": "launch_probe", "x": at.x, "y": at.y, "z": at.z})
	else:
		ctx.intents.hazard_add(HAZARD_RADIUS_M, at)


## G: the selection becomes the next waypoint of route 1 (FT-RLY-005).
func _route_to_selection() -> bool:
	var at: Variant = _selection_pos()
	if at == null:
		ctx.crew.toast.emit("toast.select_first", {})
		return false
	ctx.intents.route_add(0, at)
	return true


func _toggle_lanes() -> void:
	var blk: Dictionary = ctx.view.blocks.get(StationViews.Section.RELAY, {})
	ctx.intents.command({"kind": "flag_lanes", "on": not bool(blk.get("lanes", false))})


## Accepts an inbox mark; with all 8 used it replaces the selected mark, else the toast
## (FT-SPA-022, D182).
func _accept(id: int) -> void:
	var slot: int = -1
	if ctx.crew.marks.size() >= CrewState.MAX_MARKS:
		slot = _selected_mark()
		if slot < 0:
			ctx.crew.toast.emit("toast.relay_marks_full", {})
			return
	ctx.intents.accept_mark(id, slot)


## Sends the selected mark to an allied ship's Relay (FT-RLY-008).
func _send_selected(ship: int) -> bool:
	var slot: int = _selected_mark()
	if slot < 0:
		ctx.crew.toast.emit("toast.select_first", {})
		return false
	if ship < 0:
		return false
	ctx.intents.send_mark(slot, ship)
	return true


## Delete with a hazard zone selected removes it (scan positions stay Science's).
func _delete_zone() -> bool:
	var s: Dictionary = ctx.crew.selection
	if s.get("kind", "") != "zone":
		return false
	if ctx.crew.zone_by_id(int(s["id"])).get("kind", "") != "hazard":
		return false
	ctx.intents.hazard_delete(int(s["id"]))
	return true


## The position (m) of the shared selection, or null.
func _selection_pos() -> Variant:
	return _item_pos(ctx.crew.selection)


## The position (m) of an item ({"kind", "id"}), or null.
func _item_pos(s: Dictionary) -> Variant:
	match s.get("kind", ""):
		"contact":
			if int(s["id"]) in ctx.interp.contact_ids():
				return ctx.interp.contact_position(int(s["id"]))
		"mark":
			var m: Dictionary = ctx.crew.mark_in_slot(int(s["id"]))
			if not m.is_empty():
				return ctx.mark_position(m)
		"zone":
			return ctx.zone_position(int(s["id"]))
		"site":
			return Vector3.ZERO
	return null


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		_on_button(mb)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm == null:
		return
	if _turning:
		map.rotate_by(mm.relative)
		accept_event()
	elif not _drag.is_empty():
		if mm.shift_pressed:
			# Shift+drag: up pushes the point away along the view direction.
			_drag["depth"] = float(_drag["depth"]) + mm.relative.y / map.ppm()
		else:
			_drag["plane"] = (_drag["plane"] as Vector2) + mm.relative
		var far: bool = (_drag["plane"] as Vector2).distance_to(_drag["start"]) > DRAG_PX
		_drag["moved"] = bool(_drag["moved"]) or far or float(_drag["depth"]) != 0.0
		if _drag["moved"]:
			map.preview = {
				"rel": map.unproject(_drag["plane"], _drag["depth"]),
				"plane": map.unproject(_drag["plane"]),
				"label": _preview_label(),
			}
			map.queue_redraw()
		accept_event()


func _on_button(mb: InputEventMouseButton) -> void:
	if docked:
		return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				refresh()
				var hit: Dictionary = map.item_at(mb.position)
				if armed != "":
					# Armed: this click (or drag, Shift for depth) places the probe or hazard.
					_drag = {
						"slot": -2,
						"start": mb.position,
						"plane": mb.position,
						"depth": 0.0,
						"moved": false
					}
				elif hit.is_empty() or hit["kind"] == "mark":
					var slot: int = int(hit["id"]) if not hit.is_empty() else -1
					_drag = {
						"slot": slot,
						"start": mb.position,
						"plane": mb.position,
						"depth": 0.0,
						"moved": false
					}
			else:
				if not _drag.is_empty() and (_drag["moved"] or _drag["slot"] == -2):
					_drop()
				_drag = {}
				map.preview = {}
		MOUSE_BUTTON_RIGHT:
			_turning = mb.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				map.zoom(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				map.zoom(1)
		_:
			return
	accept_event()


## Ends a drag: a mark dropped on a contact attaches to it; otherwise it lands at the
## dragged point. A new mark takes the first free slot (or replaces the selected mark
## when all 8 are used).
func _drop() -> void:
	var slot: int = _drag["slot"]
	var depth: float = _drag["depth"]
	var on: Dictionary = map.item_at(_drag["plane"]) if depth == 0.0 else {}
	if slot == -2:
		var at: Variant = _item_pos(on) if on.get("kind", "") != "site" else null
		_place(armed, at if at != null else map.site_position(map.unproject(_drag["plane"], depth)))
		armed = ""
		return
	var item: Dictionary = (
		on if on.get("kind", "") == "contact" else _point(map.unproject(_drag["plane"], depth))
	)
	if slot < 0:
		if ctx.crew.marks.size() < CrewState.MAX_MARKS:
			ctx.mark_item(-1, item)
		elif not replace_mark(item):
			ctx.crew.toast.emit("toast.relay_marks_full", {})
	else:
		ctx.move_mark_to(slot, item)


func _start_rename() -> bool:
	var slot: int = _selected_mark()
	if slot < 0:
		return false
	_rename_slot = slot
	_rename.text = str(ctx.crew.mark_in_slot(slot).get("name", ""))
	_rename.visible = true
	_rename.grab_focus()
	_rename.select_all()
	return true


func _on_rename(text: String) -> void:
	if _rename_slot >= 0:
		ctx.intents.rename_mark(_rename_slot, text)
	_rename_slot = -1
	_rename.visible = false
	_rename.release_focus()


## Attached: free it where it is now. Free: attach it to the contact nearest to it
## along the minimum image (D124).
func _toggle_attach() -> bool:
	var m: Dictionary = ctx.crew.mark_in_slot(_selected_mark())
	if m.is_empty():
		return false
	var slot: int = m["slot"]
	var at: Vector3 = ctx.mark_position(m)
	if int(m.get("contact", -1)) >= 0:
		ctx.intents.move_mark(slot, -1, at)
		return true
	var best: int = -1
	var best_d: float = INF
	for id: int in ctx.interp.contact_ids():
		if id == ctx.crew.ship:
			continue
		var d: float = ctx.interp.min_image(ctx.interp.contact_position(id) - at).length()
		if d < best_d:
			best_d = d
			best = id
	if best < 0:
		return false
	ctx.move_mark_to(slot, {"kind": "contact", "id": best})
	return true


## Controller: left stick cursor, triggers depth, right stick turns the map.
func _poll_pad(delta: float) -> void:
	var m: InputMatcher = ctx.matcher
	var move: Vector2 = Vector2(m.axis("relay_cursor_x"), m.axis("relay_cursor_y"))
	if move != Vector2.ZERO:
		_cursor = (cursor_pos() + move * PAD_CURSOR_PX_S * delta).clamp(Vector2.ZERO, size)
	_cursor_depth -= m.axis("relay_depth") * PAD_DEPTH_SPANS_S * map.span_m * delta
	var spin: Vector2 = Vector2(m.axis("relay_rotate_x"), m.axis("relay_rotate_y"))
	if spin != Vector2.ZERO:
		map.rotate_by(spin * PAD_TURN_PX_S * delta)


func _point(rel: Vector3) -> Dictionary:
	return {"kind": "point", "pos": map.site_position(rel)}


func _selected_mark() -> int:
	var s: Dictionary = ctx.crew.selection
	return int(s["id"]) if s.get("kind", "") == "mark" else -1


func _preview_label() -> String:
	if int(_drag["slot"]) >= 0:
		return str(ctx.crew.mark_in_slot(_drag["slot"]).get("name", ""))
	for k: int in CrewState.MAX_MARKS:
		if ctx.crew.mark_in_slot(k).is_empty():
			return CrewState.MARK_NAMES[k]
	return ""
