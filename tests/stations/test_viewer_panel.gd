extends GdUnitTestSuite
## The main screen (ViewerPanel) on the station fixture: layout, the forward camera's
## stabilisation and comfort roll locks, and the switch to chase while decoupled or
## rolling fast.

const SETTINGS: String = "user://test_viewer_panel.cfg"


func before() -> void:
	I18n.apply("en")
	# gdUnit's 64 x 64 window is a phone on its side; these check the desktop layout (#28).
	LayoutMode.forced = LayoutMode.Kind.DESKTOP


func after() -> void:
	LayoutMode.forced = -1


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## `roll_deg_s`: the own ship's roll rate (body z) from the start, before the first frame.
func _screen(roll_deg_s: float = 0.0) -> StationScreen:
	var ctx: StationContext = StationFixture.context("viewer", SETTINGS)
	ctx.settings.mark_tooltip_seen("viewer")
	ctx.view.kin["ang"] = NetCodec.quant_ang(Vector3(0.0, 0.0, deg_to_rad(roll_deg_s)))
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _viewer(s: StationScreen) -> ViewerPanel:
	return s.panels[0] as ViewerPanel


# FT: FT-MSC-001, FT-MSC-003, FT-STN-001, FT-STN-002
func test_forward_view_wide_radar_and_callsign_rail() -> void:
	var s: StationScreen = await _screen()
	var v: ViewerPanel = _viewer(s)
	assert_object(v).is_not_null()
	# The main screen takes the whole width: no side column, its own wide radar.
	assert_bool(s.radar.is_visible_in_tree()).is_false()
	assert_float(v.size.x).is_equal(1280.0)
	assert_float(v.radar.size.x).is_greater(v.radar.size.y * 2.5)
	assert_float(v.radar.global_position.y).is_greater(v.global_position.y + v.size.y / 2.0)
	assert_bool(s.top_bar.is_visible_in_tree()).is_true()
	assert_bool(v.chase).is_false()
	# The rail lists contacts nearest first, with clock and range band.
	var rail: Array = v.rail_items().map(func(it: Dictionary) -> String: return it["label"])
	assert_array(rail).is_equal(["F4", "H2", "U3"])
	assert_str(ChipText.chip("H2", v.rail_items()[1]["local"])).is_equal("H2 · 4 high · mid")
	# Pings and marks reach the main screen too (FT-MSC-003).
	var marks: Array = v.radar.picture.items.filter(
		func(it: Dictionary) -> bool: return it["kind"] == "mark"
	)
	assert_int(marks.size()).is_equal(1)


# FT: FT-MSC-001, FT-STN-017
func test_forward_camera_rolls_with_the_deck_or_the_comfort_lock() -> void:
	var s: StationScreen = await _screen()
	var v: ViewerPanel = _viewer(s)
	var ship: Basis = Basis(s.ctx.interp.own_rotation())
	v.update_view(0.016)
	# Deck plane (comfort off): the camera is the ship's frame, looking out of the bow.
	assert_bool(v.camera.basis.is_equal_approx(ship)).is_true()
	assert_float(v.camera.fov).is_equal(ViewerPanel.FOV_DEG)
	assert_float(v.camera.position.dot(-ship.z)).is_greater(0.0)
	# Comfort, target lock: the selected target ship's deck stays level (its NEAR
	# orientation), still looking out of the bow.
	var h2_rot: Quaternion = Quaternion(Vector3.FORWARD, 0.5)
	s.ctx.view.near[StationFixture.H2] = [NetCodec.pack_quat(h2_rot), Vector3i.ZERO, 0]
	s.ctx.settings.comfort = true
	s.ctx.settings.roll_lock = "target"
	s.ctx.settings.reduced_fov = true
	s.ctx.crew.select("contact", StationFixture.H2)
	v.update_view(0.016)
	var h2_up: Vector3 = NetCodec.unpack_quat(NetCodec.pack_quat(h2_rot)) * Vector3.UP
	assert_vector(-v.camera.basis.z).is_equal_approx(-ship.z, Vector3.ONE * 1e-4)
	assert_float(v.camera.basis.x.dot(h2_up)).is_equal_approx(0.0, 1e-4)
	assert_float(v.camera.basis.y.dot(h2_up)).is_greater(0.0)
	assert_bool(v.camera.basis.is_equal_approx(ship)).is_false()
	assert_float(v.camera.fov).is_equal_approx(
		ViewerPanel.FOV_DEG * ComfortCamera.REDUCED_FOV, 1e-4
	)
	# Reference plane: the player's plane stays level (its up has no sideways part).
	s.ctx.settings.roll_lock = "reference"
	s.ctx.settings.reference_plane = Quaternion(Vector3.FORWARD, 0.7)
	v.update_view(0.016)
	var ref_up: Vector3 = s.ctx.settings.reference_plane * Vector3.UP
	assert_float(v.camera.basis.x.dot(ref_up)).is_equal_approx(0.0, 1e-4)
	assert_bool(v.camera.basis.is_equal_approx(ship)).is_false()
	# Comfort off again: the deck, whatever the lock says.
	s.ctx.settings.comfort = false
	v.update_view(0.016)
	assert_bool(v.camera.basis.is_equal_approx(ship)).is_true()


# FT: FT-MSC-001
func test_switches_to_chase_while_decoupled_or_rolling_fast() -> void:
	var s: StationScreen = await _screen()
	var v: ViewerPanel = _viewer(s)
	var clock: StationFixture.Clock = StationFixture.clock(s.ctx)
	var ship: Basis = Basis(s.ctx.interp.own_rotation())
	# Rolling at 60°/s (body z) from the snapshot: chase, behind and above the ship.
	s.ctx.view.kin["ang"] = NetCodec.quant_ang(Vector3(0.0, 0.0, deg_to_rad(60.0)))
	v.update_view(0.016)
	assert_bool(v.chase).is_true()
	assert_float(v.camera.position.dot(ship.z)).is_greater(5.0)
	# 40°/s is not calm yet; under 30°/s for 1.5 s brings the forward view back.
	s.ctx.view.kin["ang"] = NetCodec.quant_ang(Vector3(0.0, 0.0, deg_to_rad(40.0)))
	v.update_view(0.016)
	clock.ms += 2000
	v.update_view(0.016)
	assert_bool(v.chase).is_true()
	s.ctx.view.kin["ang"] = Vector3i.ZERO
	v.update_view(0.016)
	clock.ms += 1400
	v.update_view(0.016)
	assert_bool(v.chase).is_true()
	clock.ms += 100
	v.update_view(0.016)
	assert_bool(v.chase).is_false()
	# Decoupled (STATUS): chase while it lasts, forward 1.5 s after.
	s.ctx.view.blocks[StationViews.Section.STATUS]["decoupled"] = true
	v.update_view(0.016)
	clock.ms += 5000
	v.update_view(0.016)
	assert_bool(v.chase).is_true()
	s.ctx.view.blocks[StationViews.Section.STATUS]["decoupled"] = false
	v.update_view(0.016)
	clock.ms += ViewerPanel.FORWARD_AFTER_MS
	v.update_view(0.016)
	assert_bool(v.chase).is_false()


# FT: FT-MSC-001
# The fixture ship is yawed, pitched and rolled. Rolling fast from its very first frame,
# the chase camera starts on the ship's deck, not on world up (D124: there is none).
func test_first_chase_frame_keeps_the_ships_up() -> void:
	var s: StationScreen = await _screen(60.0)
	var v: ViewerPanel = _viewer(s)
	var ship: Basis = Basis(s.ctx.interp.own_rotation())
	assert_bool(v.chase).is_true()
	assert_vector(v.camera.basis.y).is_equal_approx(ship.y, Vector3.ONE * 1e-4)
	assert_vector(-v.camera.basis.z).is_equal_approx(-ship.z, Vector3.ONE * 1e-4)


# FT: FT-MSC-004, FT-STN-008
func test_viewers_only_watch() -> void:
	var s: StationScreen = await _screen()
	var mark: Dictionary = {"id": "mark", "target": "screen", "pressed": true, "device": "pad"}
	s.ctx.crew.select("contact", StationFixture.H2)
	s.dispatch(mark)
	s.dispatch({"id": "alert_cycle", "target": "screen", "pressed": true, "device": "kbm"})
	assert_array(StationFixture.sent(s.ctx).sent).is_empty()
