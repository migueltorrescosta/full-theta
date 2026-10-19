extends GdUnitTestSuite
## Joint views (T055, §5.9): Tactical, Systems and Ops as one StationScreen with the
## real panels on the station fixture; devices go through the matcher and the one
## binding table, checks read what the panels send.

const JOINT: Dictionary = {
	"tactical": ["helm", "weapons"],
	"systems": ["engineering", "science"],
	"ops": ["relay", "comms"],
}


func before() -> void:
	I18n.apply("en")


func _screen(entry: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, "user://test_joint_views.cfg")
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	# The tests step the panels themselves.
	for p: StationPanel in s.panels:
		p.set_process(false)
	return s


func _key(s: StationScreen, name: String, pressed: bool = true, alt: bool = false) -> void:
	var k: InputEventKey = InputEventKey.new()
	k.physical_keycode = OS.find_keycode_from_string(name)
	k.pressed = pressed
	k.alt_pressed = alt
	s.feed(k)


func _tap(s: StationScreen, name: String) -> void:
	_key(s, name)
	_key(s, name, false)


func _pad(s: StationScreen, button: JoyButton, pressed: bool = true) -> void:
	var b: InputEventJoypadButton = InputEventJoypadButton.new()
	b.button_index = button
	b.pressed = pressed
	s.feed(b)


func _mouse(s: StationScreen, button: MouseButton, pressed: bool) -> void:
	var m: InputEventMouseButton = InputEventMouseButton.new()
	m.button_index = button
	m.pressed = pressed
	s.feed(m)


func _motion(s: StationScreen, rel: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.relative = rel
	s.feed(m)


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


## Nodes of a script class under n (n included).
func _count(n: Node, type: Script) -> int:
	var count: int = 1 if is_instance_of(n, type) else 0
	for c: Node in n.get_children():
		count += _count(c, type)
	return count


## Moves contact `id` to a ship-frame offset (m), at rest.
func _place(ctx: StationContext, id: int, local: Vector3) -> void:
	var p: Vector3 = StationFixture.OWN_POS + StationFixture.own_rotation() * local
	ctx.view.contacts["model"][id] = [
		NetCodec.quant_pos(p.x, p.y, p.z, ctx.view.p_units),
		NetCodec.quant_vel(Vector3.ZERO),
		StationFixture.TICK
	]
	ctx.interp = SnapshotInterpolator.new()
	ctx.interp.p_units = ctx.view.p_units
	ctx.interp.push(ctx.view, StationFixture.NOW_MS - 100)
	ctx.interp.push(ctx.view, StationFixture.NOW_MS)
	ctx.interp.update(StationFixture.NOW_MS)


# FT: FT-JNT-001, FT-JNT-003, FT-M1-006, FT-NET-018
# Each M1 joint view is one screen: one top bar, one disc radar, its first station's
# panel focused in the main area and the other docked; F1/F2, View + LB/RB and a tap on
# the docked panel move the focus, and the focused panel takes its station's bindings.
func test_tactical_systems_and_ops_are_one_screen_with_a_docked_panel() -> void:
	for entry: String in JOINT:
		var s: StationScreen = _screen(entry)
		assert_array(s.stations).is_equal(JOINT[entry])
		assert_int(_count(s, TopBar)).is_equal(1)
		assert_int(_count(s, DiscRadar)).is_equal(1)
		assert_object(s.panels[0].get_parent()).is_same(s._main)
		assert_object(s.panels[1].get_parent()).is_same(s._dock)
		assert_bool(s.panels[1].docked).is_true()
		_tap(s, "F2")
		assert_str(s.focused_station()).is_equal(JOINT[entry][1])
		assert_object(s.panels[1].get_parent()).is_same(s._main)
		_pad(s, JOY_BUTTON_BACK)
		_pad(s, JOY_BUTTON_LEFT_SHOULDER)
		_pad(s, JOY_BUTTON_LEFT_SHOULDER, false)
		_pad(s, JOY_BUTTON_BACK, false)
		assert_str(s.focused_station()).is_equal(JOINT[entry][0])
		var tap: InputEventMouseButton = InputEventMouseButton.new()
		tap.button_index = MOUSE_BUTTON_LEFT
		tap.pressed = true
		s._on_panel_input(tap, s.panels[1])
		assert_str(s.focused_station()).is_equal(JOINT[entry][1])
		# The top bar names both stations and stars the focused one.
		s._process(0.0)
		assert_str(s.top_bar._stations.text).is_equal(
			"%s + %s*" % [tr("station." + JOINT[entry][0]), tr("station." + JOINT[entry][1])]
		)


# FT: FT-JNT-007, FT-STN-008
# With Weapons focused, Helm keeps its always-live set (translation on KB/M, face,
# all-stop), and alert, ping and panel switch work whatever has the focus.
func test_the_always_live_set_works_whatever_has_focus() -> void:
	var s: StationScreen = _screen("tactical")
	var helm: HelmPanel = s.panels[0]
	_tap(s, "F2")
	assert_str(s.focused_station()).is_equal("weapons")
	_key(s, "W")
	_key(s, "F")
	helm._process(0.016)
	var input: Dictionary = _commands(s, "helm_input").back()
	assert_float(input["throttle"]).is_equal(1.0)
	assert_bool(input["face"]).is_true()
	_tap(s, "Space")
	assert_int(_commands(s, "helm_all_stop").size()).is_equal(1)
	# A Helm key that isn't live (L, Align) does nothing while Weapons has the focus.
	s.ctx.crew.select("contact", StationFixture.H2)
	_tap(s, "L")
	assert_array(_commands(s, "helm_align")).is_empty()
	for entry: String in JOINT:
		var j: StationScreen = _screen(entry)
		for focus: int in 2:
			j.focus(focus)
			_key(j, "Alt", true, true)
			_key(j, "A", true, true)
			_key(j, "A", false, true)
			_key(j, "Alt", false)
			j.ctx.crew.select("contact", StationFixture.H2)
			_mouse(j, MOUSE_BUTTON_MIDDLE, true)
			_mouse(j, MOUSE_BUTTON_MIDDLE, false)
		assert_int(StationFixture.sent(j.ctx).of("set_alert").size()).is_equal(2)
		assert_int(StationFixture.sent(j.ctx).of("ping").size()).is_equal(2)
		_tap(j, "F1")
		assert_int(j.focus_index).is_equal(0)


# FT: FT-JNT-008
# Tactical: Helm focus shows the cockpit, the mouse flies the ship, and the KB/M fire
# button fires the claimed mounts at the selected target (the controller's RT stays
# Helm's throttle); Weapons focus shows the turret, the mouse aims and Helm's rotation
# is neutral, so flight assist holds the attitude.
func test_tactical_cockpit_fires_claimed_mounts_and_turret_aims() -> void:
	var s: StationScreen = _screen("tactical")
	var helm: HelmPanel = s.panels[0]
	var weapons: WeaponsPanel = s.panels[1]
	var ctx: StationContext = s.ctx
	assert_bool(helm._container.visible).is_true()
	assert_bool(weapons._view.visible).is_false()
	_motion(s, Vector2(60, 0))
	helm._process(0.016)
	assert_float((_commands(s, "helm_input").back()["rotation"] as Vector3).y).is_not_zero()
	# H2 just off the bow, in the mount's arc, selected; mount 0 is ours.
	ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	_place(ctx, StationFixture.H2, Vector3(60.0, 40.0, -1500.0))
	ctx.crew.select("contact", StationFixture.H2)
	_mouse(s, MOUSE_BUTTON_LEFT, true)
	weapons.step(0.016)
	assert_int(_commands(s, "fire").size()).is_equal(1)
	assert_vector(weapons.aim_dir(0)).is_equal_approx(
		weapons.lead_dir(0, StationFixture.H2) as Vector3, Vector3.ONE * 1e-3
	)
	_mouse(s, MOUSE_BUTTON_LEFT, false)
	assert_str(IntentTable.target("fire", IntentTable.PAD, "helm", s.stations)).is_empty()
	# Someone else's mount: the cockpit fires nothing.
	ctx.crew.claims["mount:0"] = {"session": 99, "name": "Bo"}
	StationFixture.clock(ctx).ms += 1000
	_mouse(s, MOUSE_BUTTON_LEFT, true)
	weapons.step(0.016)
	_mouse(s, MOUSE_BUTTON_LEFT, false)
	assert_int(_commands(s, "fire").size()).is_equal(1)
	ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	# Weapons focus: the turret is shown and the mouse aims, not steers.
	_tap(s, "F2")
	assert_bool(helm._container.visible).is_false()
	assert_bool(weapons._view.visible).is_true()
	var aim: Vector3 = weapons.aim_dir(0)
	_motion(s, Vector2(60, 0))
	helm._process(0.016)
	weapons.step(0.1)
	assert_vector(_commands(s, "helm_input").back()["rotation"]).is_equal(Vector3.ZERO)
	assert_bool(weapons.aim_dir(0).is_equal_approx(aim)).is_false()


# FT: FT-JNT-005
# A joint view gets the union of its stations' data: Tactical's one snapshot feeds
# Helm's HELM block and Weapons' MOUNTS block, and both panels send through the one
# ShipIntents. M1 has no request chips (§7.4 comes with #9), so no request runs between
# joint stations yet; StationPanel.send_request documents the direct-action rule.
func test_a_joint_view_gets_the_union_of_its_stations_data() -> void:
	var def: StationDef = StationViews.def("tactical")
	assert_bool(StationViews.Section.HELM in def.sections).is_true()
	assert_bool(StationViews.Section.MOUNTS in def.sections).is_true()
	var s: StationScreen = _screen("tactical")
	var helm: HelmPanel = s.panels[0]
	var weapons: WeaponsPanel = s.panels[1]
	assert_dict(helm.helm_block()).is_not_empty()
	assert_dict(weapons._mount_row(0)).is_not_empty()
	_tap(s, "Space")
	weapons.ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	_place(s.ctx, StationFixture.H2, Vector3(60.0, 40.0, -1500.0))
	weapons.fire_claimed_at(StationFixture.H2)
	assert_int(_commands(s, "helm_all_stop").size()).is_equal(1)
	assert_int(_commands(s, "fire").size()).is_equal(1)
	for p: StationPanel in s.panels:
		assert_bool(p.has_request_chip()).is_false()
