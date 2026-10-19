extends GdUnitTestSuite
## Relay's map read-out and mark curation (T054) on the station fixture: the map's frame
## and centre, placing on the view plane with Shift+drag depth, moving, attaching,
## renaming, deleting and replacing marks, through intents and pointer drags on KB/M
## and the controller cursor.

const SETTINGS: String = "user://test_relay_panel.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(entry: String = "relay") -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	# The headless window is tiny: lay the screen out at 1280x720.
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _relay(s: StationScreen) -> RelayPanel:
	return s.panels[s.stations.find("relay")] as RelayPanel


func _ev(id: String, device: String, s: StationScreen) -> Dictionary:
	return {
		"id": id,
		"group": IntentTable.row(id)["group"],
		"target": IntentTable.target(id, device, s.focused_station(), s.stations),
		"kind": IntentTable.row(id)["kind"],
		"pressed": true,
		"value": 1.0,
		"device": device,
	}


func _sent(s: StationScreen, method: String) -> Array:
	return StationFixture.sent(s.ctx).of(method)


## A map point with nothing drawn near it.
func _empty_spot(p: RelayPanel, near: Vector2) -> Vector2:
	for k: int in 40:
		var at: Vector2 = near + Vector2(17.0 * k, 11.0 * k)
		if p.map.item_at(at).is_empty():
			return at
	return near


func _press(p: RelayPanel, at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = button
	mb.pressed = pressed
	mb.position = at
	p._gui_input(mb)


func _move(p: RelayPanel, rel: Vector2, shift: bool = false) -> void:
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.relative = rel
	mm.shift_pressed = shift
	p._gui_input(mm)


## Drags from `from` to `to` in a few steps, then `depth_px` with Shift held (up < 0).
func _drag(p: RelayPanel, from: Vector2, to: Vector2, depth_px: float = 0.0) -> void:
	_press(p, from, true)
	for k: int in 4:
		_move(p, (to - from) / 4.0)
	if depth_px != 0.0:
		_move(p, Vector2(0.0, depth_px), true)
	_press(p, to, false)


## The ship-frame offset from the map centre of a site-local position.
func _rel(p: RelayPanel, site_pos: Vector3) -> Vector3:
	return p.map.own_rot.inverse() * (site_pos - p.map.own_pos) - p.map.centre_local()


# FT: FT-RLY-001, FT-SPA-006, FT-M1-017
func test_map_is_ship_frame_centred_on_ship_or_selection_and_turns_freely() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	p.refresh()
	assert_float(p.map.period_m).is_equal(StationFixture.PERIOD_M)
	var kinds: Array = p.map.items.map(func(it: Dictionary) -> String: return it["kind"])
	assert_array(kinds).contains(["contact", "mark"])
	# Centred on the own ship: the ship projects to the middle.
	assert_vector(p.map.project(-p.map.centre_local())).is_equal_approx(p.size / 2.0, Vector2.ONE)
	# Items sit at their ship-frame offsets from the centre (D124).
	var h2: Vector3 = _local_of(p, "contact", StationFixture.H2)
	assert_dict(p.item_at(p.map.project(h2))).is_equal({"kind": "contact", "id": StationFixture.H2})
	# C centres on the selection, C again back on the ship.
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_bool(s.dispatch(_ev("map_centre", "kbm", s))).is_true()
	assert_vector(p.map.centre_local()).is_equal(h2)
	assert_vector(p.map.project(h2 - p.map.centre_local())).is_equal_approx(
		p.size / 2.0, Vector2.ONE
	)
	s.dispatch(_ev("map_centre", "kbm", s))
	assert_vector(p.map.centre_local()).is_equal(Vector3.ZERO)
	# Right-drag turns the camera with no clamp: it can go right over the top (no up).
	var start: Basis = p.map.view
	_press(p, Vector2(100, 100), true, MOUSE_BUTTON_RIGHT)
	_move(p, Vector2(0.0, PI / RelayMap.ROTATE_RAD_PER_PX))
	_press(p, Vector2(100, 100), false, MOUSE_BUTTON_RIGHT)
	assert_float(p.map.view.y.dot(start.y)).is_less(-0.99)
	assert_bool(p.map.view.is_equal_approx(p.map.view.orthonormalized())).is_true()
	# Wheel zoom.
	var span: float = p.map.span_m
	_press(p, Vector2(100, 100), true, MOUSE_BUTTON_WHEEL_UP)
	assert_float(p.map.span_m).is_less(span)


# FT: FT-RLY-002, FT-SPA-013, FT-M1-017
func test_drag_places_on_the_view_plane_and_shift_drag_sets_depth() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	p.refresh()
	var a: Vector2 = _empty_spot(p, Vector2(80, 80))
	var b: Vector2 = a + Vector2(120, 40)
	_drag(p, a, b)
	var placed: Array = _sent(s, "place_mark")
	assert_int(placed.size()).is_equal(1)
	var args: Array = placed[0][1]
	assert_array(args.slice(0, 4)).is_equal([-1, "", -1, 0])
	var rel: Vector3 = _rel(p, args[4])
	# On the plane through the centre, perpendicular to the view, under the drop point.
	assert_float(rel.dot(p.map.view.z)).is_equal_approx(0.0, 0.5)
	assert_vector(p.map.project(rel)).is_equal_approx(b, Vector2.ONE)
	# Shift+drag pushes it along the view direction; it still sits under the pointer.
	_drag(p, a, b, -100.0)
	rel = _rel(p, _sent(s, "place_mark")[1][1][4])
	assert_float(rel.dot(p.map.view.z)).is_equal_approx(-100.0 / p.map.ppm(), 0.5)
	assert_vector(p.map.project(rel)).is_equal_approx(b, Vector2.ONE)
	# A click (no drag) places nothing.
	_press(p, a, true)
	_press(p, a, false)
	assert_int(_sent(s, "place_mark").size()).is_equal(2)


# FT: FT-RLY-003, FT-SPA-014, FT-SPA-015, FT-M1-017
func test_relay_moves_attaches_renames_and_deletes_marks() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var bravo: int = StationFixture.BRAVO_SLOT
	p.refresh()
	var at: Vector2 = p.map.project(_local_of(p, "mark", bravo))
	# Marks are selectable like contacts (FT-SPA-015).
	assert_dict(p.item_at(at)).is_equal({"kind": "mark", "id": bravo})
	s.ctx.crew.select("mark", bravo)
	var to: Vector2 = _empty_spot(p, at + Vector2(60, -90))
	_drag(p, at, to)
	var moved: Array = _sent(s, "move_mark")[0][1]
	assert_array(moved.slice(0, 3)).is_equal([bravo, -1, 0])
	assert_vector(p.map.project(_rel(p, moved[3]))).is_equal_approx(to, Vector2.ONE)
	# Dropped on a contact: attached to it.
	_drag(p, at, p.map.project(_local_of(p, "contact", StationFixture.H2)))
	assert_array(_sent(s, "move_mark")[1][1].slice(0, 2)).is_equal([bravo, StationFixture.H2])
	# M attaches a free mark to the contact nearest to it.
	assert_bool(s.dispatch(_ev("mark_attach", "kbm", s))).is_true()
	assert_array(_sent(s, "move_mark")[2][1].slice(0, 2)).is_equal([bravo, _nearest(s, bravo)])
	# N opens the name box; Enter sends it.
	assert_bool(s.dispatch(_ev("mark_rename", "kbm", s))).is_true()
	var box: LineEdit = p.find_child("Rename", true, false)
	assert_bool(box.visible).is_true()
	assert_str(box.text).is_equal("Bravo")
	box.text_submitted.emit("Wreck")
	assert_array(_sent(s, "rename_mark")[0][1]).is_equal([bravo, "Wreck"])
	assert_bool(box.visible).is_false()
	# Delete (and the controller's d-pad down) delete the selected mark.
	assert_bool(s.dispatch(_ev("mark_delete", "kbm", s))).is_true()
	assert_bool(s.dispatch(_ev("mark_delete", "pad", s))).is_true()
	assert_array(_sent(s, "delete_mark")[0][1]).is_equal([bravo])
	# With no mark selected they do nothing.
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_bool(s.dispatch(_ev("mark_delete", "kbm", s))).is_false()
	assert_bool(s.dispatch(_ev("mark_rename", "kbm", s))).is_false()


# FT: FT-RLY-003, FT-SPA-014
func test_attach_frees_an_attached_mark_where_it_is() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var marks: Array = [{"slot": 2, "name": "Charlie", "contact": StationFixture.H2, "site": -1}]
	marks[0].merge({"x": 0.0, "y": 0.0, "z": 0.0, "by": "Bo"})
	s.ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 0)
	s.ctx.crew.select("mark", 2)
	s.dispatch(_ev("mark_attach", "pad", s))
	var args: Array = _sent(s, "move_mark")[0][1]
	assert_array(args.slice(0, 3)).is_equal([2, -1, 0])
	var h2: Vector3 = s.ctx.interp.contact_position(StationFixture.H2)
	assert_vector(args[3]).is_equal_approx(h2, Vector3.ONE * 0.01)
	assert_object(p).is_not_null()


# FT: FT-SPA-022, FT-SPA-012
func test_with_eight_marks_relay_replaces_the_selected_one() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var marks: Array = []
	for k: int in CrewState.MAX_MARKS:
		marks.append({"slot": k, "contact": -1, "site": 0, "x": 100.0 * k, "y": 0, "z": 0})
	s.ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 0)
	var toasts: Array = []
	s.ctx.crew.toast.connect(func(key: String, _a: Dictionary) -> void: toasts.append(key))
	p.refresh()
	var a: Vector2 = _empty_spot(p, Vector2(80, 80))
	# Nothing selected: refused with a toast that says how to replace.
	_drag(p, a, a + Vector2(50, 50))
	assert_array(_sent(s, "place_mark")).is_empty()
	assert_array(toasts).is_equal(["toast.relay_marks_full"])
	# A mark selected: the new one takes its slot (drag and the common mark action).
	s.ctx.crew.select("mark", 5)
	_drag(p, a, a + Vector2(50, 50))
	assert_array(_sent(s, "place_mark")[0][1].slice(0, 3)).is_equal([5, "", -1])
	s.dispatch(_ev("mark", "pad", s))
	assert_array(_sent(s, "place_mark")[1][1].slice(0, 3)).is_equal([5, "", -1])


# FT: FT-STN-005, FT-STN-003, FT-RLY-002
func test_controller_cursor_selects_pings_and_marks_with_depth() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var start: Vector2 = p.cursor_pos()
	assert_vector(start).is_equal(p.size / 2.0)
	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	s.ctx.matcher.feed(stick, s.ctx.now_ms())
	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	s.ctx.matcher.feed(trigger, s.ctx.now_ms())
	p._poll_pad(0.25)
	assert_float(p.cursor_pos().x).is_greater(start.x + 50.0)
	# Hold R3 marks the map point under the cursor, pushed away by the trigger.
	s.dispatch(_ev("mark", "pad", s))
	var args: Array = _sent(s, "place_mark")[0][1]
	assert_array(args.slice(0, 4)).is_equal([-1, "", -1, 0])
	var rel: Vector3 = _rel(p, args[4])
	assert_float(rel.dot(p.map.view.z)).is_less(-1.0)
	assert_vector(p.map.project(rel)).is_equal_approx(p.cursor_pos(), Vector2.ONE)
	# A selects and R3 pings the item under the cursor.
	p._cursor = p.map.project(_local_of(p, "contact", StationFixture.U3))
	assert_bool(s.dispatch(_ev("select", "pad", s))).is_true()
	assert_dict(s.ctx.crew.selection).is_equal({"kind": "contact", "id": StationFixture.U3})
	s.dispatch(_ev("ping", "pad", s))
	assert_array(_sent(s, "ping")[0][1].slice(0, 2)).is_equal(["contact", StationFixture.U3])


# FT: FT-JNT-001, FT-M1-006
func test_docked_relay_is_a_compact_map() -> void:
	var s: StationScreen = await _screen("ops")
	var p: RelayPanel = _relay(s)
	assert_bool(p.map.chips).is_true()
	s.dispatch(_ev("focus_2", "kbm", s))
	assert_bool(p.docked).is_true()
	assert_bool(p.map.chips).is_false()
	# Docked: pointer drags don't place marks (a click focuses the panel instead).
	_drag(p, Vector2(20, 20), Vector2(90, 60))
	assert_array(_sent(s, "place_mark")).is_empty()


func _local_of(p: RelayPanel, kind: String, id: int) -> Vector3:
	for it: Dictionary in p.map.items:
		if it["kind"] == kind and it["id"] == id:
			return it["local"]
	return Vector3.INF


func _nearest(s: StationScreen, slot: int) -> int:
	var at: Vector3 = s.ctx.mark_position(s.ctx.crew.mark_in_slot(slot))
	var best: int = -1
	var best_d: float = INF
	for id: int in s.ctx.interp.contact_ids():
		var d: float = s.ctx.interp.contact_position(id).distance_to(at)
		if d < best_d:
			best_d = d
			best = id
	return best
