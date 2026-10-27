extends GdUnitTestSuite
## The main screen's five views (FT-MSC-002, FT-MSC-006): forward, chase, tactical, target
## and status render from the view the Captain (or Relay) chose, a plain viewer is
## read-only, and the status view shows hull, shields, subsystem health, objectives and
## the alert level.

const SETTINGS: String = "user://test_main_screen_views.cfg"


func before() -> void:
	I18n.apply("en")
	# gdUnit's 64 x 64 window is a phone on its side; these check the desktop layout (#28).
	LayoutMode.forced = LayoutMode.Kind.DESKTOP


func after() -> void:
	LayoutMode.forced = -1


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(entry: String = StationViews.VIEWER) -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _show(s: StationScreen, view: int) -> ViewerPanel:
	s.ctx.crew.handle_event(
		{"type": "main_view", "payload": {"ship": 0, "view": view, "by": "x"}}, 1
	)
	var v: ViewerPanel = s.panels[0] as ViewerPanel
	v.update_view(0.016)
	await get_tree().process_frame
	return v


# FT: FT-MSC-002
func test_each_view_shows_its_parts() -> void:
	var s: StationScreen = await _screen()
	var v: ViewerPanel = await _show(s, MainScreen.View.FORWARD)
	assert_bool(v._view_box.visible).is_true()
	assert_bool(v.status_view.visible).is_false()
	assert_bool(v.chase).is_false()
	# Chase stays chase even with the ship calm.
	await _show(s, MainScreen.View.CHASE)
	assert_bool(v.chase).is_true()
	assert_bool(v._view_box.visible).is_true()
	# Tactical: only the rail and the radar, which takes the freed height.
	var wide: float = v.radar.size.y
	await _show(s, MainScreen.View.TACTICAL)
	assert_bool(v._view_box.visible).is_false()
	assert_bool(v.status_view.visible).is_false()
	assert_float(v.radar.size.y).is_greater(wide * 1.5)
	# Status: the sheet instead of the 3D view.
	await _show(s, MainScreen.View.STATUS)
	assert_bool(v._view_box.visible).is_false()
	assert_bool(v.status_view.visible).is_true()
	# Target: the 3D view again, on the selected contact.
	s.ctx.crew.select("contact", StationFixture.U3)
	await _show(s, MainScreen.View.TARGET)
	assert_bool(v._view_box.visible).is_true()
	assert_int(v.view_id).is_equal(MainScreen.View.TARGET)
	assert_str(v._target_item()["label"]).is_equal("U3")
	var to_target: Vector3 = (v._target_item()["world"] as Vector3) - v.camera.position
	assert_float((-v.camera.basis.z).dot(to_target.normalized())).is_greater(0.999)
	# With nothing selected the nearest contact is the target (F4 is 600 m out).
	s.ctx.crew.select("", -1)
	await _show(s, MainScreen.View.TARGET)
	assert_str(v._target_item()["label"]).is_equal("F4")


# FT: FT-MSC-004
func test_a_plain_viewer_is_read_only() -> void:
	var s: StationScreen = await _screen()
	var v: ViewerPanel = s.panels[0] as ViewerPanel
	assert_bool(v.interactive).is_false()
	assert_dict(v.item_at(Vector2(640.0, 300.0))).is_empty()
	assert_dict(v.item_at(v.radar.position + v.radar.size / 2.0)).is_empty()


# FT: FT-MSC-006
func test_status_view_shows_hull_shields_subsystems_objectives_and_alert() -> void:
	var s: StationScreen = await _screen()
	var def: ShipDef = s.ctx.ship_def()
	assert_object(def).is_not_null()
	var status: Dictionary = (
		(s.ctx.view.blocks[StationViews.Section.STATUS] as Dictionary).duplicate()
	)
	status["hull"] = def.hull_max * 0.92
	status["shields"] = def.shields.max_strength * 0.7
	s.ctx.view.blocks[StationViews.Section.STATUS] = status
	var rows: Array = []
	for i: int in def.subsystems.size():
		rows.append({"health": def.subsystems[i].health_max * (0.5 if i == 0 else 1.0)})
	s.ctx.view.blocks[StationViews.Section.CAPTAIN] = {
		"subsystems": rows,
		"objectives": [{"kind": Objectives.Kind.DESTROY_HOSTILES, "left": 2}],
	}
	s.ctx.crew.handle_event({"type": "alert", "payload": {"ship": 0, "level": 2, "by": "Ana"}}, 1)
	var v: ViewerPanel = await _show(s, MainScreen.View.STATUS)
	var m: Dictionary = v.status_view._model
	assert_float(m["hull"]).is_equal_approx(0.92, 0.001)
	assert_float(m["shields"]).is_equal_approx(0.7, 0.001)
	assert_int(m["alert"]).is_equal(CrewState.ALERT_RED)
	assert_int((m["subsystems"] as Array).size()).is_equal(def.subsystems.size())
	assert_float(m["subsystems"][0]["frac"]).is_equal_approx(0.5, 0.001)
	assert_str(m["subsystems"][0]["id"]).is_equal(str(def.subsystems[0].id))
	assert_array(m["objectives"]).is_equal(["Stop the hostile ships (2 left)"])
	# No data yet: empty bars rather than errors.
	var empty: Dictionary = StatusView.model({}, {}, null, 0)
	assert_float(empty["hull"]).is_equal(0.0)
	assert_array(empty["subsystems"]).is_empty()


# FT: FT-MSC-005, FT-RLY-010
# The client only offers the switch to the Captain, and to Relay while no Captain is
# seated (the lobby event names the Captain); the server decides.
func test_who_may_switch_on_the_client() -> void:
	var cap: StationContext = StationFixture.context(StationViews.CAPTAIN, SETTINGS)
	assert_bool(cap.crew.may_switch_main_view()).is_true()
	var relay: StationContext = StationFixture.context("relay", SETTINGS)
	assert_bool(relay.crew.may_switch_main_view()).is_true()
	relay.crew.lobby[0]["captain"] = "Rui"
	assert_bool(relay.crew.may_switch_main_view()).is_false()
	var helm: StationContext = StationFixture.context("helm", SETTINGS)
	assert_bool(helm.crew.may_switch_main_view()).is_false()
	# Relay's Alt+n goes to the server only without a Captain.
	var sent: StationFixture.RecordingClient = StationFixture.sent(relay)
	var panel: RelayPanel = RelayPanel.new()
	panel.setup(relay, "relay")
	assert_bool(panel.handle_intent({"id": "main_view_3", "pressed": true})).is_true()
	assert_int(sent.of("set_main_view").size()).is_equal(0)
	relay.crew.lobby[0]["captain"] = ""
	assert_bool(panel.handle_intent({"id": "main_view_3", "pressed": true})).is_true()
	assert_array(sent.of("set_main_view")[0][1]).is_equal([MainScreen.View.TACTICAL])
	panel.free()


# FT: FT-STN-001
# The top bar on a real ship definition shows the hull as a percentage (it showed
# "Hull 100000000" before).
func test_top_bar_shows_hull_as_a_percentage_of_the_ships_maximum() -> void:
	var s: StationScreen = await _screen("helm")
	var def: ShipDef = s.ctx.ship_def()
	var status: Dictionary = (
		(s.ctx.view.blocks[StationViews.Section.STATUS] as Dictionary).duplicate()
	)
	status["hull"] = def.hull_max
	status["shields"] = def.shields.max_strength * 0.5
	s.ctx.view.blocks[StationViews.Section.STATUS] = status
	s._process(0.016)
	assert_str(s.top_bar._hull.text).is_equal("Hull 100%")
	assert_str(s.top_bar._shields.text).is_equal("Shields 50%")


# FT: FT-MSC-002
# The target view draws its target even beyond NEAR's range (H2 is 2.3 km out, NEAR sees
# 2 km): before, the view showed an empty sky with the label and bracket only. Other
# views still draw only contacts with a NEAR orientation.
func test_target_view_draws_a_target_beyond_near_range() -> void:
	var s: StationScreen = await _screen()
	assert_bool(s.ctx.view.near.has(StationFixture.H2)).is_false()
	s.ctx.crew.select("contact", StationFixture.H2)
	var v: ViewerPanel = await _show(s, MainScreen.View.FORWARD)
	assert_bool(v._space.ships.has(StationFixture.H2)).is_false()
	await _show(s, MainScreen.View.TARGET)
	assert_bool(v._space.ships.has(StationFixture.H2)).is_true()
	await _show(s, MainScreen.View.FORWARD)
	assert_bool(v._space.ships.has(StationFixture.H2)).is_false()


# FT: FT-PAIR-019
# The status bars colour by D193's bands, split at 75, 50 and 25 % (edges belong to the
# better band).
func test_status_bars_follow_the_health_bands() -> void:
	assert_str(StatusView.bar_role(1.0)).is_equal("ok")
	assert_str(StatusView.bar_role(0.75)).is_equal("ok")
	assert_str(StatusView.bar_role(0.7)).is_equal("warn")
	assert_str(StatusView.bar_role(0.5)).is_equal("warn")
	assert_str(StatusView.bar_role(0.3)).is_equal("warn")
	assert_str(StatusView.bar_role(0.2)).is_equal("danger")
