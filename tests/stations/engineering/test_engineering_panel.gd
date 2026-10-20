extends GdUnitTestSuite
## Engineering (T053): the panel on the station fixture (m1_corvette, the fixture's
## ENGINEERING block), driven through intents on KB/M and controller and through the
## cutaway and board's pointer input; sends are recorded by the fixture's client.

const KIND = SubsystemDef.Kind

var _toasts: Array[String] = []


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	_toasts = []


func _screen(entry: String = "engineering") -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry)
	ctx.crew.toast.connect(func(key: String, _a: Dictionary) -> void: _toasts.append(key))
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1280, 720)
	add_child(host)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	host.add_child(s)
	await await_idle_frame()
	return s


func _panel(s: StationScreen) -> EngineeringPanel:
	return s.panels[s.stations.find("engineering")] as EngineeringPanel


## Routes an intent like the matcher would, from `device`.
func _press(s: StationScreen, id: String, device: String = "kbm") -> bool:
	return (
		s
		. dispatch(
			{
				"id": id,
				"group": IntentTable.row(id)["group"],
				"target": IntentTable.target(id, device, s.focused_station(), s.stations),
				"kind": IntentTable.row(id)["kind"],
				"pressed": true,
				"value": 1.0,
				"device": device,
			}
		)
	)


func _commands(s: StationScreen) -> Array:
	return StationFixture.sent(s.ctx).of("command").map(
		func(c: Array) -> Dictionary: return c[1][0]
	)


func _click(c: Control, pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = button
	mb.pressed = pressed
	mb.position = pos
	c._gui_input(mb)


func _drag(c: Control, from: Vector2, to: Vector2) -> void:
	_click(c, from, MOUSE_BUTTON_LEFT, true)
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = to
	mm.relative = to - from
	c._gui_input(mm)
	_click(c, to, MOUSE_BUTTON_LEFT, false)


func _hit(s: StationScreen, ship: int, pos: Vector3) -> void:
	var p: Dictionary = {
		"ship": ship, "faction": 0, "other": 2, "value": 1.0, "vector": pos, "tag": 0
	}
	s.ctx.crew.handle_event({"type": "hit", "payload": p}, s.ctx.now_ms())


# FT: FT-ENG-001, FT-M1-004
func test_cutaway_shows_health_heat_and_recent_hits_and_rotates() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	assert_object(e.ship_def).is_not_null()
	assert_int(e.count()).is_equal(6)
	assert_float(e.health_frac(0)).is_equal_approx(0.4, 1e-6)
	assert_float(e.heat_frac(3)).is_equal_approx(0.8, 1e-6)
	# Hits on the own ship are kept with their ship-frame point; others' are not.
	_hit(s, StationFixture.SHIP, Vector3(0, 1, 16))
	_hit(s, 2, Vector3(0, 0, -10))
	assert_int(e.hits.size()).is_equal(1)
	assert_vector(e.hits[0]["pos"]).is_equal(Vector3(0, 1, 16))
	# Every subsystem disc is where the hit test finds it.
	var cut: EngineeringCutaway = e.cutaway
	assert_vector(cut.size).is_not_equal(Vector2.ZERO)
	for i: int in e.count():
		assert_int(cut.subsystem_at(cut.subsystem_pos(i))).is_equal(i)
	# Right-drag turns the cutaway; the right stick too.
	var before: Vector2 = cut.subsystem_pos(0)
	_click(cut, Vector2(400, 300), MOUSE_BUTTON_RIGHT, true)
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.relative = Vector2(60, 20)
	cut._gui_input(mm)
	_click(cut, Vector2(460, 320), MOUSE_BUTTON_RIGHT, false)
	assert_vector(cut.subsystem_pos(0)).is_not_equal(before)
	var yaw: float = cut.yaw
	cut.rotate_by(Vector2(0.5, 0.0))
	assert_float(cut.yaw).is_not_equal(yaw)
	# Hits fade out.
	StationFixture.clock(s.ctx).ms += EngineeringPanel.HIT_MS + 1
	e._process(0.016)
	assert_array(e.hits).is_empty()


# FT: FT-ENG-002
func test_pips_through_intents_within_cap_and_max_with_overcharge() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	assert_int(e.pips_used()).is_equal(10)
	# KB/M: 2 selects thrusters, + adds a pip (above nominal 2: overcharge).
	assert_bool(_press(s, "subsystem_2")).is_true()
	assert_int(e.selected).is_equal(1)
	assert_bool(_press(s, "pip_add")).is_true()
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "set_pips", "subsystem_kind": KIND.THRUSTERS, "pips": 3}
	)
	assert_int(e.pips_of(1)).is_equal(3)
	assert_bool(e.pips_of(1) > e.ship_def.subsystems[1].nominal_pips).is_true()
	_press(s, "pip_add")
	assert_int(e.pips_of(1)).is_equal(4)
	# The per-subsystem maximum: nothing more is sent.
	var n: int = _commands(s).size()
	_press(s, "pip_add")
	assert_int(_commands(s).size()).is_equal(n)
	# Controller: d-pad right to weapons, RT adds: over the reactor cap (12), refused here.
	assert_bool(_press(s, "subsystem_next", "pad")).is_true()
	assert_int(e.selected).is_equal(2)
	_press(s, "pip_add", "pad")
	assert_int(_commands(s).size()).is_equal(n)
	assert_array(_toasts).contains(["toast.eng_cap"])
	_press(s, "pip_remove", "pad")
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "set_pips", "subsystem_kind": KIND.WEAPONS, "pips": 1}
	)
	# The reactor takes no pips.
	_press(s, "subsystem_6")
	_press(s, "pip_add")
	assert_array(_toasts).contains(["toast.eng_reactor"])
	# A click on a pip box sets the column to it; on the top lit one turns it off.
	var b: EngineeringBoard = e.board
	_click(b, b._pip_rect(4, 1).get_center(), MOUSE_BUTTON_LEFT, true)
	assert_int(e.selected).is_equal(4)
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "set_pips", "subsystem_kind": KIND.SENSORS, "pips": 2}
	)
	_click(b, b._pip_rect(4, 1).get_center(), MOUSE_BUTTON_LEFT, true)
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "set_pips", "subsystem_kind": KIND.SENSORS, "pips": 1}
	)
	# The sent value shows until the snapshot agrees or PENDING_MS passes.
	StationFixture.clock(s.ctx).ms += EngineeringPanel.PENDING_MS + 1
	assert_int(e.pips_of(1)).is_equal(2)
	# Boost (O / LB+RT), once at a time.
	_press(s, "boost")
	assert_dict(_commands(s)[-1]).is_equal({"kind": "boost"})
	s.ctx.view.blocks[StationViews.Section.ENGINEERING]["boost_ticks"] = 300
	assert_bool(e.is_boosted(0) and not e.is_boosted(2)).is_true()
	_press(s, "boost", "pad")
	assert_dict(_commands(s)[-1]).is_equal({"kind": "boost"})
	assert_array(_toasts).contains(["toast.eng_boosting"])


# FT: FT-ENG-003
func test_shield_power_and_tightness() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	assert_float(e.shield_frac()).is_equal_approx(0.7, 1e-6)
	_press(s, "shield_tighter")
	assert_dict(_commands(s)[-1]).is_equal({"kind": "set_shield", "power": -1, "tightness": 2.0})
	_press(s, "shield_wider", "pad")
	_press(s, "shield_wider", "pad")
	assert_dict(_commands(s)[-1]).is_equal({"kind": "set_shield", "power": -1, "tightness": 1.0})
	# A click on a tightness step; the range ends at the ship's tightness_max.
	var b: EngineeringBoard = e.board
	_click(b, b._step_rect(b._steps() - 1).get_center(), MOUSE_BUTTON_LEFT, true)
	assert_dict(_commands(s)[-1]).is_equal({"kind": "set_shield", "power": -1, "tightness": 4.0})
	var n: int = _commands(s).size()
	_press(s, "shield_tighter")
	assert_int(_commands(s).size()).is_equal(n)
	# Shield power is the shield subsystem's pips.
	_press(s, "subsystem_4")
	_press(s, "pip_remove")
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "set_pips", "subsystem_kind": KIND.SHIELDS, "pips": 1}
	)


# FT: FT-ENG-004
func test_drag_a_crew_to_a_subsystem_and_back_and_controller_dispatch() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	var cut: EngineeringCutaway = e.cutaway
	assert_int(e.crew_job(0)).is_equal(0)
	assert_int(e.crew_job(1)).is_equal(-1)
	# Crew B, idle in the bay, dragged onto weapons.
	_drag(cut, cut.token_pos(1), cut.subsystem_pos(2))
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "dispatch_repair", "crew": 1, "subsystem_id": "weapons"}
	)
	assert_str(e.claim_item()).is_equal("crew:1")
	# Crew A, on the engines, dragged off the ship: called back.
	_drag(cut, cut.token_pos(0), Vector2(cut.size.x - 10, 40))
	assert_dict(_commands(s)[-1]).is_equal({"kind": "recall_repair", "crew": 0})
	# Right-click a working crew also calls it back.
	_click(cut, cut.token_pos(0), MOUSE_BUTTON_RIGHT, true)
	_click(cut, cut.token_pos(0), MOUSE_BUTTON_RIGHT, false)
	assert_dict(_commands(s)[-1]).is_equal({"kind": "recall_repair", "crew": 0})
	# A whole subsystem needs no crew.
	var n: int = _commands(s).size()
	_drag(cut, cut.token_pos(1), cut.subsystem_pos(1))
	assert_int(_commands(s).size()).is_equal(n)
	assert_array(_toasts).contains(["toast.eng_whole"])
	# Controller: B sends the idle crew to the selected subsystem.
	_press(s, "subsystem_3", "pad")
	assert_bool(_press(s, "dispatch_nearest", "pad")).is_true()
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "dispatch_repair", "crew": 1, "subsystem_id": "weapons"}
	)
	# The left stick moves a cursor that snaps to the nearest subsystem.
	var target: Vector2 = cut.subsystem_pos(0)
	cut.cursor = target + Vector2(20, 0)
	assert_int(cut.move_cursor(Vector2(-18, 0))).is_equal(0)
	# Crews another player holds are skipped; with none free, a toast.
	s.ctx.view.ownership = {"claims": {"crew:1": [99, "Bo"]}, "writers": {}}
	assert_bool(e.crew_taken(1)).is_true()
	_press(s, "subsystem_3", "pad")
	_press(s, "dispatch_nearest", "pad")
	assert_dict(_commands(s)[-1]).is_equal(
		{"kind": "dispatch_repair", "crew": 0, "subsystem_id": "weapons"}
	)
	# No parts, no repair (D115).
	s.ctx.view.blocks[StationViews.Section.ENGINEERING]["spare_parts"] = 0
	n = _commands(s).size()
	_drag(cut, cut.token_pos(0), cut.subsystem_pos(2))
	assert_int(_commands(s).size()).is_equal(n)
	assert_array(_toasts).contains(["toast.eng_no_parts"])


# FT: FT-ENG-005
func test_faults_repair_queue_and_spares_list() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	var faults: Array = e.fault_lines().map(func(l: Array) -> String: return l[0])
	assert_array(faults).is_equal(["Engines 40%", "Weapons 75%", "Shields running hot"])
	# A heat fault event lists the subsystem as overheated for a while.
	var p: Dictionary = {"ship": 0, "faction": 0, "other": -1, "value": 110.0, "tag": "weapons"}
	s.ctx.crew.handle_event({"type": "fault", "payload": p}, s.ctx.now_ms())
	assert_str(e.fault_lines()[1][0]).is_equal("Weapons overheated (75%)")
	var queue: Array = e.queue_lines().map(func(l: Array) -> String: return l[0])
	assert_array(queue).is_equal(
		["1. ENG 40%  A", "2. WPN 75%  waiting", "Crew A: ENG", "Crew B: idle"]
	)
	e._process(0.0)
	var shown: Array = e._lists.get_children().map(func(l: Label) -> String: return l.text)
	assert_array(shown).contains(["Faults", "Repairs", "Spare parts: 6", "Engines 40%"])


func test_reserved_keys_and_claims_and_wheel_over_the_radar() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	# Harden and probes come later (FT-ENG-008): H and P are taken but do nothing yet.
	assert_bool(_press(s, "harden")).is_true()
	assert_bool(_press(s, "fabricate_probe", "pad")).is_true()
	assert_array(_commands(s)).is_empty()
	assert_array(_toasts).contains(["toast.eng_later"])
	# K claims the picked crew.
	_press(s, "claim")
	assert_array(StationFixture.sent(s.ctx).of("claim")).is_equal([["claim", ["crew:0"]]])
	# A wheel turn outside the panel (the radar zooms) changes no pips.
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.global_position = s.radar.get_global_rect().get_center()
	e._input(wheel)
	assert_bool(_press(s, "pip_add")).is_false()
	assert_array(_commands(s)).is_empty()


# FT: FT-JNT-001
func test_systems_joint_view_focused_and_docked() -> void:
	var s: StationScreen = await _screen("systems")
	var e: EngineeringPanel = _panel(s)
	assert_bool(e.focused and e.cutaway.visible and not e.board.compact).is_true()
	s.focus(1)
	assert_bool(e.docked and not e.cutaway.visible and e.board.compact).is_true()
	# Docked, its station intents don't reach it.
	assert_bool(_press(s, "pip_add")).is_false()
	s.focus(0)
	assert_bool(_press(s, "pip_add")).is_true()


# FT: FT-ENG-002
func test_a_ship_without_subsystems_ignores_selection_and_pips() -> void:
	var s: StationScreen = await _screen()
	var p: EngineeringPanel = _panel(s)
	var def: ShipDef = p.ship_def.duplicate()
	def.subsystems = []
	p.ship_def = def
	assert_bool(_press(s, "subsystem_next")).is_false()
	assert_bool(_press(s, "subsystem_prev")).is_false()
	_press(s, "pip_add")
	await await_idle_frame()
	assert_array(_commands(s)).is_empty()
