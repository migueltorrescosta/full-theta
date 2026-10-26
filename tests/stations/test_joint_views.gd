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
# ShipIntents. A request between the view's own stations is a direct action, not a chip
# (tests/stations/test_request_chips.gd sends them); the chips for other stations stay.
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
		assert_bool(p.has_request_chip()).is_true()
	var to_helm: Array = weapons.request_chips().filter(
		func(c: ChipDef) -> bool: return c.id == &"bring_to_bear"
	)
	assert_int(to_helm.size()).is_equal(1)
	assert_str(String(to_helm[0].to_station)).is_equal("helm")


## Every catalogue entry that is a joint view: the 15 pairs (FT-NET-032).
func _views() -> Array[String]:
	var out: Array[String] = []
	for entry: String in StationViews.ENTRIES:
		if (StationViews.ENTRIES[entry][2] as Array).size() == 2:
			out.append(entry)
	return out


# FT: FT-NET-017, FT-NET-032, FT-JNT-001, FT-JNT-004
# All 15 views build as one screen of exactly two panels (never 3 or more stations): one top
# bar, one disc radar, the first station's panel in the main area, the second docked and the
# panels of the registry; F2 moves the focus.
func test_all_fifteen_views_are_modal_two_panel_screens() -> void:
	var views: Array[String] = _views()
	assert_int(views.size()).is_equal(15)
	var pairs: Dictionary = {}
	for entry: String in views:
		var stations: Array = StationViews.stations_of(entry)
		pairs[",".join(PackedStringArray(stations))] = true
		var s: StationScreen = _screen(entry)
		assert_array(s.stations).is_equal(stations)
		assert_int(s.panels.size()).is_equal(2)
		assert_int(_count(s, TopBar)).is_equal(1)
		assert_int(_count(s, DiscRadar)).is_equal(1)
		assert_object(s.panels[0].get_parent()).is_same(s._main)
		assert_object(s.panels[1].get_parent()).is_same(s._dock)
		for i: int in 2:
			assert_str(s.panels[i].station).is_equal(stations[i])
		_tap(s, "F2")
		assert_str(s.focused_station()).is_equal(stations[1])
		assert_object(s.panels[0].get_parent()).is_same(s._dock)
		assert_bool(s.panels[0].docked).is_true()
		_tap(s, "F1")
		assert_str(s.focused_station()).is_equal(stations[0])
		# The pair name is under the view name in the lobby (D186).
		var def: StationDef = StationViews.def(entry)
		assert_str(def.load_tag).is_not_empty()
	assert_int(pairs.size()).is_equal(15)


# FT: FT-NET-018, FT-JNT-005, FT-JNT-004
# A view keeps every control of its stations and gets the union of their data: its
# sections, commands, claims and ship-wide controls contain each station's, and each
# panel reads its own station's blocks from the one snapshot.
func test_all_fifteen_views_keep_every_control_and_get_the_union() -> void:
	for entry: String in _views():
		var def: StationDef = StationViews.def(entry)
		for station: String in def.stations:
			var own: StationDef = StationViews.def(station)
			for kind: int in own.sections:
				assert_bool(kind in def.sections).override_failure_message(entry).is_true()
			for c: Variant in own.commands:
				assert_bool(c in def.commands).override_failure_message(entry).is_true()
			for c: Variant in own.claims:
				assert_bool(c in def.claims).override_failure_message(entry).is_true()
			for c: Variant in own.controls:
				assert_bool(c in def.controls).override_failure_message(entry).is_true()
		var s: StationScreen = _screen(entry)
		for p: StationPanel in s.panels:
			assert_bool(p.ctx.view == s.ctx.view).is_true()


# FT: FT-JNT-005, FT-STN-010, FT-PAIR-021
# Every chip between a view's own two stations runs as a direct command at any difficulty:
# nothing is sent as a chip and no toast says "do it yourself". Each chip's sender is the
# focused panel, with a contact selected for the chips that need one.
func test_every_chip_between_a_views_stations_is_a_direct_action() -> void:
	var expect: Dictionary = {
		"boost": "boost",
		"power": "set_pips",
		"bring_to_bear": "helm_align",
		"sensor_power": "set_pips",
		"scan_mark": "science_scan_mark",
		"fabricate_probe": "fabricate_probe",
	}
	var seen: Dictionary = {}
	for entry: String in _views():
		var stations: Array = StationViews.stations_of(entry)
		for chip: ChipDef in NetChips.def().chips:
			var from: String = String(chip.from_station)
			# Hold fire has no direct action: Parley's one player says so (next test).
			if chip.id == &"hold_fire":
				continue
			if not (from in stations and String(chip.to_station) in stations):
				continue
			var s: StationScreen = _screen(entry)
			var toasts: Array[String] = []
			s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
			s.focus(stations.find(from))
			s.ctx.crew.select("contact", StationFixture.H2)
			s.focused_panel().send_chip(chip)
			var id: String = String(chip.id)
			(
				assert_array(StationFixture.sent(s.ctx).of("send_chip"))
				. override_failure_message(entry + " " + id)
				. is_empty()
			)
			assert_array(toasts).override_failure_message(entry + " " + id).is_empty()
			(
				assert_int(_commands(s, expect[id]).size())
				. override_failure_message(entry + " " + id)
				. is_equal(1)
			)
			seen[id] = true
	# Every active chip belongs to some view, so all six are covered.
	assert_int(seen.size()).is_equal(6)


# FT: FT-JNT-005, FT-PAIR-021
# Hold fire in Parley (Weapons + Comms) is the one chip with no direct action: nothing is sent
# and the toast tells the player they hold both stations.
func test_hold_fire_in_parley_is_a_toast() -> void:
	var s: StationScreen = _screen("parley")
	var toasts: Array[String] = []
	s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
	var chip: ChipDef = NetChips.def().chips[NetChips.index_of("hold_fire")]
	s.focus(s.stations.find("comms"))
	s.ctx.crew.select("contact", StationFixture.H2)
	s.focused_panel().send_chip(chip)
	assert_array(StationFixture.sent(s.ctx).of("send_chip")).is_empty()
	assert_array(toasts).is_equal(["toast.chip_same_screen"])


# FT: FT-JNT-005
# "Bring mount N to bear" in a Helm + Weapons view aligns the requested mount, not the bow:
# the Align command names the weapons panel's selected mount.
func test_direct_bring_to_bear_names_the_requested_mount() -> void:
	var s: StationScreen = _screen("tactical")
	var weapons: WeaponsPanel = s.panels[s.stations.find("weapons")] as WeaponsPanel
	weapons.mount = weapons.mount_count() - 1
	var chip: ChipDef
	for c: ChipDef in NetChips.def().chips:
		if c.id == &"bring_to_bear":
			chip = c
	s.focus(s.stations.find("weapons"))
	s.ctx.crew.select("contact", StationFixture.H2)
	weapons.send_chip(chip)
	var aligns: Array = _commands(s, "helm_align")
	assert_int(aligns.size()).is_equal(1)
	assert_int(aligns[0]["mount_index"]).is_equal(weapons.mount)


# FT: FT-JNT-005
# The direct power chips respect the reactor: with the reactor full the request is refused
# with the "take it from something else" toast, and at the per-subsystem maximum with the
# "full power" toast; nothing is sent.
func test_direct_power_respects_the_reactor_and_the_maximum() -> void:
	var s: StationScreen = _screen("gunnery")
	var toasts: Array[String] = []
	s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
	var power: ChipDef
	for c: ChipDef in NetChips.def().chips:
		if c.id == &"power":
			power = c
	var rows: Array = s.ctx.view.blocks[StationViews.Section.ENGINEERING]["subsystems"]
	var used: int = 0
	for r: Dictionary in rows:
		used += int(r["pips"])
	rows[0]["pips"] += s.ctx.ship_def().power.reactor_pips - used
	s.focus(0)
	s.panels[0].send_chip(power)
	assert_array(_commands(s, "set_pips")).is_empty()
	assert_array(toasts).is_equal(["toast.eng_cap"])
	rows[0]["pips"] = 1
	rows[2]["pips"] = s.ctx.ship_def().power.max_pips_per_subsystem
	toasts.clear()
	s.panels[0].send_chip(power)
	assert_array(_commands(s, "set_pips")).is_empty()
	assert_array(toasts).is_equal(["toast.chip_pips_max"])


# FT: FT-JNT-004, FT-NET-018, FT-STN-001
# The four views with Comms (and Ops) show the ship's live cards as the Comms half, the real
# rows of the COMMS block; a view without Comms shows none.
func test_the_views_with_comms_show_the_real_cards() -> void:
	for entry: String in _views():
		var s: StationScreen = _screen(entry)
		var has_comms: bool = "comms" in s.stations
		assert_int(_count(s, CardList)).is_equal(1 if has_comms else 0)
		if has_comms:
			CommsFixture.install(s.ctx)
			var panel: CommsPanel = s.panels[s.stations.find("comms")] as CommsPanel
			panel.refresh(true)
			assert_int(panel.list._cards.size()).is_equal(4)
			assert_int(int(panel.list._cards[0]["id"])).is_equal(CommsFixture.MISSION)


## The physical inputs of one binding (as tests/input/test_binding_table.gd splits them).
static func _inputs(binding: String) -> Array:
	var out: Array = []
	for part: String in binding.trim_prefix("long ").split("/"):
		out.append(part.trim_prefix("-"))
	return out


# FT: FT-JNT-002, FT-JNT-001, FT-JNT-003
# The binding-table check for each view (tests/input/test_binding_table.gd covers the
# whole catalogue): with either panel focused, no physical input is bound to intents of
# both stations of the view that the screen routes at once, on either device. Inside one
# station an input may serve two modes (Science's dial and arrows); the common set and
# the pointer's select and fire (D176) are checked by the whole-catalogue test.
func test_no_key_is_used_by_both_panels_of_any_view() -> void:
	for entry: String in _views():
		var stations: Array = StationViews.stations_of(entry)
		for focused: String in stations:
			for device: String in IntentTable.DEVICES:
				var owner_of: Dictionary = {}
				for r: Dictionary in IntentTable.INTENTS:
					var target: String = IntentTable.target(r["id"], device, focused, stations)
					if target == "" or target == "screen":
						continue
					for b: String in IntentTable.defaults(r["id"], device):
						for i: String in _inputs(b):
							var first: String = owner_of.get(i, target)
							var msg: String = "%s %s %s: %s" % [entry, focused, device, i]
							assert_str(target).override_failure_message(msg).is_equal(first)
							owner_of[i] = target
