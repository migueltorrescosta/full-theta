extends GdUnitTestSuite
## Science's client (E01, §5.4): the radar with confidence-sized icons, the contact list
## and card with a confidence bar per part, the sensor and scan controls over intents,
## buttons and the controller, and both minigames over mouse, keys, controller and touch
## (taps and drags). The server side is tests/sim/science and tests/net/test_net_science_l3.

const SETTINGS: String = "user://test_science_panel.cfg"
const H2: int = StationFixture.H2
const U3: int = StationFixture.U3
const S = StationViews.Section


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## The screen on the science entry, with a SCIENCE block that has H2 well scanned (its
## class, intent, weak points, resistances and hack access revealed) and U3 barely seen.
func _screen(block: Dictionary = {}, entry: String = "science") -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	ctx.view.blocks[S.SCIENCE] = _block(block)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _block(over: Dictionary) -> Dictionary:
	var b: Dictionary = ScienceView._empty()
	b["cards"] = [
		{
			"contact": H2,
			"detect": 0.9,
			"scan": 0.9,
			"class_id": ScienceView.code(&"m1_raider"),
			"intent": 3,
			"weak_mask": 1,
			"resist": [{"type": ScienceView.code(&"kinetic"), "factor": 0.5}],
			"hack": true,
		},
		{
			"contact": U3,
			"detect": 0.2,
			"scan": 0.0,
			"class_id": 0,
			"intent": 0,
			"weak_mask": 0,
			"resist": [],
			"hack": false,
		},
	]
	b.merge(over, true)
	return b


func _sci(s: StationScreen) -> SciencePanel:
	return s.panels[s.stations.find("science")] as SciencePanel


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


func _cmds(s: StationScreen, kind: String) -> Array:
	return StationFixture.sent(s.ctx).of("command").filter(
		func(c: Array) -> bool: return c[1][0]["kind"] == kind
	)


## A scan puzzle as the section carries it: the wire turned by `truth` is the cloud.
func _scan_block(truth: Vector3, axes: int) -> Dictionary:
	var wire: Array = []
	var cloud: Array = []
	var verts: Array[Vector3] = [
		Vector3(1, 0, 0),
		Vector3(0, 0.8, 0.2),
		Vector3(-0.5, -0.4, 0.6),
		Vector3(0.1, 0.3, -0.9),
		Vector3(-0.7, 0.5, -0.2),
		Vector3(0.4, -0.7, -0.3),
	]
	var pose: Basis = Basis.from_euler(truth)
	for v: Vector3 in verts:
		wire.append({"p": v})
		cloud.append({"p": pose * v})
	return {
		"session": 1,
		"session_target": H2,
		"session_start": 10,
		"session_noise": 0.33,
		"axes": axes,
		"wire": wire,
		"cloud": cloud,
	}


func _hack_block(node: int, known: int) -> Dictionary:
	# 5x3 grid, a straight corridor along the middle row; the goal is the last column.
	var edges: Array = []
	for n: int in 15:
		var mask: int = 0
		if n / 5 == 1:
			mask = (HackGame.RIGHT if n % 5 < 4 else 0) | (HackGame.LEFT if n % 5 > 0 else 0)
			if n == 7:
				mask |= HackGame.UP
		elif n == 2:
			mask = HackGame.DOWN
		edges.append({"mask": mask if (known >> n) & 1 == 1 else 0})
	return {
		"session": 2,
		"session_target": H2,
		"session_start": 10,
		"session_noise": 0.3,
		"hack_cols": 5,
		"hack_rows": 3,
		"hack_node": node,
		"hack_goal": 9,
		"hack_sub": 2,
		"trace": 0.25,
		"known": known,
		"edges": edges,
	}


# FT: FT-SCI-001
# The radar is orbitable, and a better-detected contact draws a bigger icon.
func test_radar_icons_grow_with_detection_confidence() -> void:
	var s: StationScreen = await _screen()
	var p: SciencePanel = _sci(s)
	p.refresh()
	assert_bool(p.radar.orbitable).is_true()
	assert_float(p.radar.blip_scale[H2]).is_greater(p.radar.blip_scale[U3])
	assert_float(p.radar.blip_scale[U3]).is_less(1.0)
	assert_float(p.radar.blip_scale[H2]).is_greater(1.0)


# FT: FT-SCI-001, FT-JNT-001
# In a joint view the screen keeps its one disc radar: it is orbitable while Science has
# the focus and draws the confidence-sized icons; the panel holds the list and card.
func test_joint_view_uses_the_screens_radar() -> void:
	var s: StationScreen = await _screen({}, "sensors")
	var p: SciencePanel = _sci(s)
	assert_object(p.radar).is_null()
	assert_bool(p.full_screen()).is_false()
	assert_bool(s.radar.orbitable).is_equal(s.focused_station() == "science")
	if s.focused_station() != "science":
		s.focus(s.stations.find("science"))
	assert_bool(s.radar.orbitable).is_true()
	s._process(0.016)
	assert_float(s.radar.blip_scale[H2]).is_greater(s.radar.blip_scale[U3])
	p.refresh()
	assert_int(p._list.item_count).is_equal(3)


# FT: FT-SCI-002
# The list sorts hostile first and selects on click; the card gives each revealed part
# with a confidence, and "??" for what the scan hasn't reached.
func test_list_selects_and_card_shows_parts_by_confidence() -> void:
	var s: StationScreen = await _screen()
	var p: SciencePanel = _sci(s)
	p.refresh()
	assert_int(p._list.item_count).is_equal(3)
	assert_int(p._list.get_item_metadata(0)).is_equal(H2)
	p._list.item_selected.emit(0)
	assert_dict(s.ctx.crew.selection).is_equal({"kind": "contact", "id": H2})
	p.refresh()
	assert_dict(p.card_view.card).is_not_empty()
	assert_str(p.card_view._value("class")).is_equal("Raider")
	assert_str(p.card_view._value("intent")).is_equal(tr("sci.intent_attack"))
	assert_str(p.card_view._value("resistances")).contains("kinetic 50%")
	assert_array(p.subsystems()).is_not_empty()
	# U3 was barely seen: its card is empty-handed and the selection moves the card.
	s.ctx.crew.select("contact", U3)
	p.refresh()
	assert_float(float(p.card_view.card["scan"])).is_equal(0.0)
	assert_bool(bool(p.card_view.card["hack"])).is_false()
	assert_array(p.subsystems()).is_empty()


# FT: FT-SCI-003, FT-SCI-010, FT-SCI-009, FT-NET-022
# Controls over keys and the controller: the same commands as the buttons; selecting a
# contact tells the server; the scan is the panel's claim item.
func test_controls_send_science_commands() -> void:
	var s: StationScreen = await _screen()
	var p: SciencePanel = _sci(s)
	assert_str(p.claim_item()).is_equal(StationViews.CLAIM_SCAN)
	s.ctx.crew.select("contact", H2)
	assert_int(_cmds(s, "science_select").size()).is_equal(1)
	assert_int(_cmds(s, "science_select")[0][1][0]["contact"]).is_equal(H2)
	p.refresh()
	for pair: Array in [
		["sci_mode", "science_sensor_mode"],
		["sci_ping", "science_ping"],
		["sci_scan_mark", "science_scan_mark"],
		["sci_self_scan", "science_self_scan"],
		["sci_scan", "science_scan"],
	]:
		assert_bool(s.dispatch(_ev(pair[0], "kbm", s))).is_true()
		assert_int(_cmds(s, pair[1]).size()).is_equal(1)
	assert_bool(_cmds(s, "science_sensor_mode")[0][1][0]["active"]).is_true()
	assert_int(_cmds(s, "science_scan")[0][1][0]["contact"]).is_equal(H2)
	# The controller's triggers reach the same intents.
	assert_bool(s.dispatch(_ev("sci_hack", "pad", s))).is_true()
	var hack: Dictionary = _cmds(s, "science_hack")[0][1][0]
	assert_int(hack["contact"]).is_equal(H2)
	assert_str(hack["subsystem_id"]).is_equal(str(p.subsystems()[0]))
	s.dispatch(_ev("sci_sub_next", "pad", s))
	s.dispatch(_ev("sci_hack", "pad", s))
	assert_str(_cmds(s, "science_hack")[1][1][0]["subsystem_id"]).is_equal(str(p.subsystems()[1]))
	# The buttons reach them too, and a hack on a contact without access sends nothing.
	(p._buttons["ping"] as Button).pressed.emit()
	assert_int(_cmds(s, "science_ping").size()).is_equal(2)
	s.ctx.crew.select("contact", U3)
	p.refresh()
	assert_bool((p._buttons["hack"] as Button).disabled).is_true()
	assert_int(_cmds(s, "science_select").size()).is_equal(2)


# FT: FT-SCI-004, FT-SCI-013, FT-SCI-014
# A scan replaces the radar with the alignment minigame; the open axes turn by drag,
# keys or sticks; the live match peaks on the right pose; Enter submits the angles.
func test_scan_minigame_turns_the_open_axes_and_submits() -> void:
	var truth: Vector3 = Vector3(0.9, 0.0, -0.6)
	var s: StationScreen = await _screen(_scan_block(truth, 5))
	var p: SciencePanel = _sci(s)
	p.refresh()
	assert_bool(p.scan_game.visible).is_true()
	assert_bool(p.radar.visible).is_false()
	assert_array(p.scan_game.open_axes()).is_equal([0, 2])
	var start: float = p.scan_game.quality()
	# Keys: the dials turn the first and second open axes (x and z).
	p.scan_game.turn(0, truth.x)
	p.scan_game.turn(1, truth.z)
	assert_float(p.scan_game.quality()).is_greater(start)
	assert_float(p.scan_game.quality()).is_greater(0.95)
	assert_float(p.scan_game.angles.y).is_equal(0.0)
	# The closed axis can't be turned.
	p.scan_game.angles.y = 0.0
	# A mouse drag turns the selected axis by dx and the next open axis by dy.
	var before: Vector3 = p.scan_game.angles
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(300, 200)
	p.scan_game._gui_input(press)
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.relative = Vector2(10, 20)
	p.scan_game._gui_input(move)
	press.pressed = false
	p.scan_game._gui_input(press)
	assert_float(p.scan_game.angles.x - before.x).is_equal_approx(10.0 * ScanGame.RAD_PER_PX, 0.001)
	assert_float(p.scan_game.angles.z - before.z).is_equal_approx(20.0 * ScanGame.RAD_PER_PX, 0.001)
	# Enter (accept) submits what is set; a tap on Submit does the same.
	p.scan_game.angles = truth
	assert_bool(s.dispatch(_ev("accept", "kbm", s))).is_true()
	var sent: Dictionary = _cmds(s, "science_scan_submit")[0][1][0]
	assert_float(sent["ax"]).is_equal_approx(truth.x, 0.001)
	assert_float(sent["az"]).is_equal_approx(truth.z, 0.001)
	_tap(p.scan_game, p.scan_game._button_rect(0).get_center())
	assert_int(_cmds(s, "science_scan_submit").size()).is_equal(2)
	# Backspace cancels.
	assert_bool(s.dispatch(_ev("decline", "kbm", s))).is_true()
	assert_int(_cmds(s, "science_cancel").size()).is_equal(1)


# FT: FT-SCI-013, FT-SCI-014
# Touch: a tap on an axis chip picks the axis a drag turns; three axes show three chips.
func test_scan_minigame_works_by_tap_and_drag_with_three_axes() -> void:
	var s: StationScreen = await _screen(_scan_block(Vector3(0.5, 0.5, 0.5), 7))
	var p: SciencePanel = _sci(s)
	p.refresh()
	var g: ScanGame = p.scan_game
	assert_array(g.open_axes()).is_equal([0, 1, 2])
	_tap(g, g._chip_rect(2).get_center())
	assert_int(g.selected).is_equal(2)
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.relative = Vector2(25, 0)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(300, 200)
	g._gui_input(press)
	g._gui_input(move)
	assert_float(g.angles.z).is_equal_approx(25.0 * ScanGame.RAD_PER_PX, 0.001)
	# A cancel button is on screen too.
	_tap(g, g._button_rect(1).get_center())
	assert_int(_cmds(s, "science_cancel").size()).is_equal(1)


# FT: FT-SCI-006, FT-SCI-013
# The hack grid: arrows, the d-pad and the stick step along known edges only; a tap on
# an adjacent node steps there; hidden nodes show "?" and can be stepped onto.
func test_hack_minigame_moves_along_known_edges() -> void:
	var known: int = (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8) | (1 << 2)
	var s: StationScreen = await _screen(_hack_block(7, known))
	var p: SciencePanel = _sci(s)
	p.refresh()
	assert_bool(p.hack_game.visible).is_true()
	assert_int(p.hack_game.step_target(HackGame.RIGHT)).is_equal(8)
	assert_int(p.hack_game.step_target(HackGame.UP)).is_equal(2)
	assert_int(p.hack_game.step_target(HackGame.DOWN)).is_equal(-1)
	# Arrow keys.
	assert_bool(s.dispatch(_ev("sci_right", "kbm", s))).is_true()
	assert_int(_cmds(s, "science_hack_move")[0][1][0]["node"]).is_equal(8)
	# No edge down: the press is taken but nothing is sent.
	assert_bool(s.dispatch(_ev("sci_down", "kbm", s))).is_true()
	assert_int(_cmds(s, "science_hack_move").size()).is_equal(1)
	# The d-pad: up is the ping outside a hack and a step up inside one.
	assert_bool(s.dispatch(_ev("sci_ping", "pad", s))).is_true()
	assert_int(_cmds(s, "science_ping").size()).is_equal(0)
	assert_int(_cmds(s, "science_hack_move")[1][1][0]["node"]).is_equal(2)
	# A tap on the hidden node 9, the goal, from node 8 once the route stands there.
	p.hack_game.node = 8
	_tap(p.hack_game, p.hack_game.node_centre(9))
	assert_int(_cmds(s, "science_hack_move")[2][1][0]["node"]).is_equal(9)
	# A tap on a far node does nothing; the cancel button cancels the hack.
	_tap(p.hack_game, p.hack_game.node_centre(0))
	assert_int(_cmds(s, "science_hack_move").size()).is_equal(3)
	_tap(p.hack_game, p.hack_game._button_rect().get_center())
	assert_int(_cmds(s, "science_cancel").size()).is_equal(1)
	# The stick: one move per deflection.
	p._stick_move(0.9, 0.0)
	p._stick_move(0.9, 0.0)
	assert_int(_cmds(s, "science_hack_move").size()).is_equal(4)
	p._stick_move(0.0, 0.0)
	p._stick_move(-0.9, 0.0)
	assert_int(_cmds(s, "science_hack_move").size()).is_equal(5)


# FT: FT-SCI-013
# The controller cursor snaps to a contact within reach; a mouse needs to be on it.
func test_controller_cursor_snaps_to_the_nearest_contact() -> void:
	var s: StationScreen = await _screen()
	var p: SciencePanel = _sci(s)
	p.refresh()
	var item: Dictionary = p.radar.item_at(Vector2.ZERO)
	assert_dict(item).is_empty()
	# Put the cursor 40 px from H2's blip: within snap reach, not within a mouse's.
	var layout: Array = p.radar._layout()
	var h2: Dictionary = layout.filter(func(e: Dictionary) -> bool: return e["item"]["id"] == H2)[0]
	var at: Vector2 = h2["pos"] + Vector2(0.0, 40.0)
	var local: Vector2 = p.radar.get_global_transform() * at
	p._cursor = p.get_global_transform().affine_inverse() * local
	assert_dict(p.item_at(p._cursor)).is_equal({"kind": "contact", "id": H2})
	assert_dict(p.item_at(p._cursor + Vector2(0, 1))).is_empty()


func _tap(c: Control, at: Vector2) -> void:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = at
	mb.pressed = true
	c._gui_input(mb)
	mb.pressed = false
	c._gui_input(mb)
