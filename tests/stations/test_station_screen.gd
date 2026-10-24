extends GdUnitTestSuite
## StationScreen: panels per entry, focus, intent routing and the common actions on the
## shared selection, marks, pings, alert and claims.


## A panel that records the intents it gets and answers item_at with `item`.
class RecordingPanel:
	extends StationPanel
	var got: Array[String] = []
	var item: Dictionary = {}
	var chips: bool = false
	var requests: int = 0

	## Ids, releases suffixed "/up".
	func handle_intent(ev: Dictionary) -> bool:
		got.append(ev["id"] if ev.get("pressed", true) else ev["id"] + "/up")
		return true

	func item_at(_pos: Vector2) -> Dictionary:
		return item

	func has_request_chip() -> bool:
		return chips

	func send_request() -> void:
		requests += 1

	func claim_item() -> String:
		return "flight" if station == "helm" else ""


func _screen(entry: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry)
	var s: StationScreen = auto_free(StationScreen.new())
	s.panel_factory = func(_st: String) -> StationPanel: return RecordingPanel.new()
	s.setup(ctx)
	add_child(s)
	return s


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


# FT: FT-JNT-001, FT-M1-006
func test_single_station_is_one_panel_and_a_joint_view_two() -> void:
	assert_int(_screen("helm").panels.size()).is_equal(1)
	var t: StationScreen = _screen("tactical")
	assert_array(t.stations).is_equal(["helm", "weapons"])
	assert_int(t.panels.size()).is_equal(2)
	assert_bool(t.panels[0].focused and not t.panels[0].docked).is_true()
	assert_bool(t.panels[1].docked).is_true()
	assert_int(_screen("all").panels.size()).is_equal(6)
	# Seats without functional stations get a panel of their own id.
	assert_array(_screen("viewer").stations).is_equal(["viewer"])


# FT: FT-JNT-001, FT-JNT-007
func test_station_intents_reach_only_the_focused_panel_but_live_ones_always() -> void:
	var s: StationScreen = _screen("tactical")
	var helm: RecordingPanel = s.panels[0]
	var weapons: RecordingPanel = s.panels[1]
	s.dispatch(_ev("focus_2", "kbm", s))
	assert_str(s.focused_station()).is_equal("weapons")
	assert_bool(s.dispatch(_ev("align", "kbm", s))).is_false()
	assert_bool(s.dispatch(_ev("fire", "kbm", s))).is_true()
	# Helm's always-live set still reaches Helm with Weapons focused.
	assert_bool(s.dispatch(_ev("face", "pad", s))).is_true()
	assert_bool(s.dispatch(_ev("all_stop", "kbm", s))).is_true()
	assert_array(helm.got).is_equal(["face", "all_stop"])
	assert_array(weapons.got).is_equal(["fire"])
	s.dispatch(_ev("focus_1", "pad", s))
	assert_str(s.focused_station()).is_equal("helm")


# FT: FT-STN-008
func test_any_crew_station_sets_the_alert_and_viewers_cannot() -> void:
	var s: StationScreen = _screen("systems")
	s.dispatch(_ev("alert_cycle", "kbm", s))
	s.dispatch(_ev("alert_red", "pad", s))
	s.top_bar.alert_picked.emit(CrewState.ALERT_NORMAL)
	(
		assert_array(_sent(s, "set_alert").map(func(c: Array) -> int: return c[1][0]))
		. is_equal([1, 2, 0])
	)
	for seat: String in ["viewer", "captain"]:
		var v: StationScreen = _screen(seat)
		v.dispatch(_ev("alert_cycle", "kbm", v))
		v.top_bar.alert_picked.emit(CrewState.ALERT_RED)
		assert_array(_sent(v, "set_alert")).is_empty()
		v._process(0.0)
		assert_bool(v.top_bar.can_set_alert).is_false()


# FT: FT-STN-003, FT-STN-009, FT-SPA-013, FT-SPA-016
func test_select_ping_and_mark_under_the_reticle() -> void:
	var s: StationScreen = _screen("weapons")
	var p: RecordingPanel = s.panels[0]
	p.item = {"kind": "contact", "id": StationFixture.H2}
	assert_bool(s.dispatch(_ev("select", "pad", s))).is_true()
	assert_dict(s.ctx.crew.selection).is_equal({"kind": "contact", "id": StationFixture.H2})
	s.dispatch(_ev("ping", "pad", s))
	s.dispatch(_ev("mark", "pad", s))
	assert_array(_sent(s, "ping")[0][1]).is_equal(["contact", StationFixture.H2, 0, Vector3.ZERO])
	assert_array(_sent(s, "place_mark")[0][1]).is_equal(
		[-1, "", StationFixture.H2, 0, Vector3.ZERO]
	)
	# Nothing under the reticle: select falls through (LMB fires in the turret), ping and
	# mark use the selection.
	p.item = {}
	assert_bool(s.dispatch(_ev("select", "pad", s))).is_false()
	s.dispatch(_ev("ping", "pad", s))
	assert_int(_sent(s, "ping").size()).is_equal(2)


# FT: FT-SPA-022
func test_a_ninth_mark_is_refused_with_a_toast() -> void:
	var s: StationScreen = _screen("helm")
	var marks: Array = []
	for slot: int in CrewState.MAX_MARKS:
		marks.append({"slot": slot, "name": "", "contact": -1, "site": 0, "x": 0, "y": 0, "z": 0})
	s.ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 0)
	var toasts: Array = []
	s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
	s.ctx.crew.select("contact", StationFixture.H2)
	s.dispatch(_ev("mark", "kbm", s))
	assert_array(_sent(s, "place_mark")).is_empty()
	# The screen raises the toast itself (the crew signal is the server's refusal).
	assert_array(toasts).is_empty()
	# Viewers place no marks at all.
	var v: StationScreen = _screen("viewer")
	v.ctx.crew.select("contact", StationFixture.H2)
	v.dispatch(_ev("mark", "kbm", v))
	assert_array(_sent(v, "place_mark")).is_empty()


# FT: FT-STN-009, FT-SPA-009
func test_cycle_select_pinged_claim_request_and_strip() -> void:
	var s: StationScreen = _screen("helm")
	s.dispatch(_ev("cycle_target", "kbm", s))
	# Nearest first: F4 at 600 m.
	assert_int(s.ctx.crew.selection["id"]).is_equal(StationFixture.F4)
	s.dispatch(_ev("claim", "kbm", s))
	assert_array(_sent(s, "claim")[0][1]).is_equal(["flight"])
	s.ctx.crew.claims["flight"] = {"session": StationFixture.SESSION, "name": "Ana"}
	s.dispatch(_ev("claim", "pad", s))
	assert_array(_sent(s, "release_claim")[0][1]).is_equal(["flight"])
	var p: RecordingPanel = s.panels[0]
	assert_bool(s.dispatch(_ev("request", "kbm", s))).is_false()
	p.chips = true
	s.dispatch(_ev("request", "kbm", s))
	assert_int(p.requests).is_equal(1)
	var strip: bool = s.radar.side_strip
	s.dispatch(_ev("radar_strip", "kbm", s))
	assert_bool(s.radar.side_strip).is_equal(not strip)
	# Accept and decline go to the focused panel.
	s.dispatch(_ev("accept", "kbm", s))
	assert_array(p.got).is_equal(["accept"])


# FT: FT-STN-009
# Snapshots list the own ship among the contacts; cycling never selects it.
func test_cycle_target_skips_the_own_ship() -> void:
	var s: StationScreen = _screen("helm")
	var v: NetViewState = StationFixture.view()
	v.contacts["model"][s.ctx.crew.ship] = [v.kin["pos"], Vector3i.ZERO, StationFixture.TICK]
	v.contacts["info"][s.ctx.crew.ship] = [2, "Kestrel"]
	s.ctx.interp = SnapshotInterpolator.new()
	s.ctx.interp.push(v, StationFixture.NOW_MS - 100)
	s.ctx.interp.push(v, StationFixture.NOW_MS)
	s.ctx.interp.update(StationFixture.NOW_MS)
	assert_array(s.ctx.interp.contact_ids()).contains([s.ctx.crew.ship])
	assert_array(s.contacts_by_range()).is_equal(
		[StationFixture.F4, StationFixture.H2, StationFixture.U3]
	)


# FT: FT-STN-011
func test_overlay_key_asks_for_the_controls_tab() -> void:
	var s: StationScreen = _screen("helm")
	var asked: Array[bool] = []
	s.help_requested.connect(func() -> void: asked.append(true))
	s.dispatch(_ev("overlay", "pad", s))
	s.dispatch(_ev("overlay", "kbm", s))
	assert_array(asked).has_size(2)


func _key(code: Key, pressed: bool, alt: bool = false) -> InputEventKey:
	var k: InputEventKey = InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = pressed
	k.alt_pressed = alt
	return k


# FT: FT-STN-009, FT-JNT-007, FT-STN-008
# Real key events through the matcher: F2 focuses Weapons, Space still reaches Helm,
# Alt+A sets the alert.
func test_device_events_route_through_the_binding_table() -> void:
	var s: StationScreen = _screen("tactical")
	s.feed(_key(KEY_F2, true))
	s.feed(_key(KEY_F2, false))
	assert_str(s.focused_station()).is_equal("weapons")
	s.feed(_key(KEY_SPACE, true))
	s.feed(_key(KEY_L, true))
	assert_array((s.panels[0] as RecordingPanel).got).is_equal(["all_stop"])
	s.feed(_key(KEY_ALT, true, true))
	s.feed(_key(KEY_A, true, true))
	assert_int(_sent(s, "set_alert").size()).is_equal(1)


func _trigger(value: float) -> InputEventJoypadMotion:
	var m: InputEventJoypadMotion = InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_TRIGGER_RIGHT
	m.axis_value = value
	return m


# FT: FT-JNT-001, FT-STN-014
# F1 while Weapons holds fire: the fire ends on Weapons, it doesn't stick.
func test_a_focus_switch_releases_a_held_fire() -> void:
	var s: StationScreen = _screen("tactical")
	var weapons: RecordingPanel = s.panels[1]
	s.focus(1)
	s.feed(_trigger(1.0))
	assert_array(weapons.got).is_equal(["fire"])
	s.feed(_key(KEY_F1, true))
	assert_str(s.focused_station()).is_equal("helm")
	assert_array(weapons.got).is_equal(["fire", "fire/up"])
	assert_bool(s.ctx.matcher.is_held("fire")).is_false()


# FT: FT-STN-014
# Losing the window or a pad coming or going releases what was held.
func test_focus_loss_and_pad_changes_release_held_inputs() -> void:
	var s: StationScreen = _screen("weapons")
	var p: RecordingPanel = s.panels[0]
	for why: Callable in [
		func() -> void: s._notification(NOTIFICATION_APPLICATION_FOCUS_OUT),
		func() -> void: s._notification(Window.NOTIFICATION_WM_WINDOW_FOCUS_OUT),
		func() -> void: Input.joy_connection_changed.emit(0, false),
	]:
		p.got.clear()
		s.feed(_trigger(1.0))
		why.call()
		assert_array(p.got).is_equal(["fire", "fire/up"])
		# The pad's raw state is gone too: the trigger must come up and press again.
		s.feed(_trigger(1.0))
		assert_array(p.got).is_equal(["fire", "fire/up", "fire"])
		s.feed(_trigger(0.0))


# FT: FT-STN-011, FT-M1-012
# The menu or the outcome card take the input: held intents end when one opens, and
# only Menu and the overlay key reach the screen meanwhile.
func test_blockers_stop_the_input_feed() -> void:
	var s: StationScreen = _screen("weapons")
	var p: RecordingPanel = s.panels[0]
	var menu: Control = auto_free(Control.new())
	menu.visible = false
	s.blockers = [menu]
	s.feed(_trigger(1.0))
	menu.visible = true
	s.feed(_trigger(0.0))
	assert_array(p.got).is_equal(["fire", "fire/up"])
	s.feed(_trigger(1.0))
	s.feed(_key(KEY_T, true))
	assert_array(p.got).is_equal(["fire", "fire/up"])
	assert_array(s.ctx.crew.selection.keys()).is_empty()
	menu.visible = false
	var card: Control = auto_free(Control.new())
	s.blockers = [card]
	var menus: Array = []
	s.menu_requested.connect(func() -> void: menus.append(true))
	s.feed(_key(KEY_T, false))
	s.feed(_key(KEY_ESCAPE, true))
	assert_array(menus).is_equal([true])
	s.feed(_key(KEY_ESCAPE, false))
	s.feed(_trigger(0.0))
	card.visible = false
	s.feed(_trigger(1.0))
	assert_array(p.got).is_equal(["fire", "fire/up", "fire"])


# FT: FT-M1-012
# A screen freed while blocked (the outcome card just before a run reset) must not leave
# the shared matcher restricted for the next run's screen.
func test_a_new_screen_starts_unblocked() -> void:
	var s: StationScreen = _screen("weapons")
	var card: Control = auto_free(Control.new())
	s.blockers = [card]
	s.feed(_trigger(0.0))
	var ctx: StationContext = s.ctx
	remove_child(s)
	var s2: StationScreen = auto_free(StationScreen.new())
	s2.panel_factory = func(_st: String) -> StationPanel: return RecordingPanel.new()
	s2.setup(ctx)
	add_child(s2)
	s2.feed(_key(KEY_T, true))
	assert_array(s2.ctx.crew.selection.keys()).is_not_empty()


# FT: FT-STN-009, FT-STN-014
# A select that found an item eats the click: a toggle bound to the same button doesn't
# flip (D176).
func test_a_consumed_select_cancels_the_toggle_flip() -> void:
	var s: StationScreen = _screen("weapons")
	var p: RecordingPanel = s.panels[0]
	s.ctx.settings.bindings.rebind("fire", "pad", PackedStringArray(["A"]))
	s.ctx.settings.bindings.set_toggle("fire", true)
	p.item = {"kind": "contact", "id": StationFixture.H2}
	var a: InputEventJoypadButton = InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	s.feed(a)
	assert_dict(s.ctx.crew.selection).is_equal({"kind": "contact", "id": StationFixture.H2})
	assert_array(p.got).is_empty()
	assert_bool(s.ctx.matcher.is_held("fire")).is_false()
