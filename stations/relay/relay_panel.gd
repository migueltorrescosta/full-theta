class_name RelayPanel
extends StationPanel
## Relay in M1 (T054, §5.5): the map read-out (RelayMap) and the marks it curates
## (FT-RLY-001 to FT-RLY-003, FT-SPA-006, FT-M1-017). Probes, routes, lanes, the inbox
## and the main-screen view switch come with #9 and #10.
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

## A press that moves less than this is a click (select), not a drag (px).
const DRAG_PX: float = 6.0
## Controller cursor speed (px/s), depth speed (map spans/s), turn speed (px-equivalent/s).
const PAD_CURSOR_PX_S: float = 420.0
const PAD_DEPTH_SPANS_S: float = 0.5
const PAD_TURN_PX_S: float = 160.0

var map: RelayMap
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
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 90.0
	_hint.offset_right = -8.0
	_hint.offset_bottom = -6.0
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
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
	_hint.visible = not docked


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
	map.queue_redraw()


func handle_intent(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)):
		return false
	match str(ev["id"]):
		"mark_delete":
			var slot: int = _selected_mark()
			if slot < 0:
				return false
			ctx.intents.delete_mark(slot)
		"mark_rename":
			return _start_rename()
		"mark_attach":
			return _toggle_attach()
		"map_centre":
			_centred = not _centred and not ctx.crew.selection.is_empty()
			refresh()
		_:
			return false
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


func tooltip_intents() -> Array[String]:
	return ["mark_rename", "mark_delete", "mark_attach", "overlay"]


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
				if hit.is_empty() or hit["kind"] == "mark":
					var slot: int = int(hit["id"]) if not hit.is_empty() else -1
					_drag = {
						"slot": slot,
						"start": mb.position,
						"plane": mb.position,
						"depth": 0.0,
						"moved": false
					}
			else:
				if not _drag.is_empty() and _drag["moved"]:
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
		ctx.intents.move_mark(slot, -1, ctx.site(), at)
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
	return {"kind": "point", "site": ctx.site(), "pos": map.site_position(rel)}


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
