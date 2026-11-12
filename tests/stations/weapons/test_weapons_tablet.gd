extends GdUnitTestSuite
## Weapons on a tablet (#32, D324): two opaque docked rails at the screen's edges
## with the whole tablet screen between them (upright: one bottom bar), an Aim stick plus a
## drag on the view, no pages, no banner. Every control sends the intent its key or pad button
## sends; every target clears the touch rules on an iPad (1180x820, 820x1180) and an Android
## tablet (1280x800). The fixture's corvette has one bow mount; U3 sits out of its arc.
# FT: FT-STN-005

const SETTINGS: String = "user://test_weapons_tablet.cfg"
const INSETS: Array = [0, 0, 0, 24]
const SIZES: Array = [Vector2i(1180, 820), Vector2i(820, 1180), Vector2i(1280, 800)]

var _vp: SubViewport
var _screen: StationScreen
var _heard: Array[String] = []


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _open(size: Vector2i, kind: int = LayoutMode.Kind.TOUCH) -> void:
	LayoutMode.forced = kind
	SafeArea.simulate(INSETS)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("weapons", SETTINGS)
	ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	ctx.crew.select("contact", StationFixture.U3)
	_screen = auto_free(StationScreen.new())
	_screen.setup(ctx)
	_screen.theme = LayoutMode.theme_for(LayoutMode.Kind.TOUCH)
	_vp.add_child(_screen)
	_panel().set_process(false)
	_panel().touch_intent.connect(func(id: String) -> void: _heard.append(id))
	await _frames(3)
	_panel().step(0.016)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _panel() -> WeaponsPanel:
	return _screen.panels[0] as WeaponsPanel


func _ui() -> WeaponsTablet:
	return _panel().tablet()


func _commands(kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(_screen.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


func _touch(global: Vector2, pressed: bool, index: int = 0) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = index
	t.position = global
	t.pressed = pressed
	_vp.push_input(t, true)


func _drag(from: Vector2, to: Vector2, index: int = 0) -> void:
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.index = index
	d.position = to
	d.relative = to - from
	_vp.push_input(d, true)


func _tap(c: Control) -> void:
	assert_bool(c.is_visible_in_tree()).override_failure_message("%s hidden" % c).is_true()
	var at: Vector2 = c.get_global_rect().get_center()
	_touch(at, true)
	_touch(at, false)


func _audit_ok(report: Dictionary, what: String) -> void:
	assert_array(StationFixture.rule_breaks(report, what)).is_empty()


# FT: FT-STN-005
# The dock: two opaque docked rails, no pages, no banner, no phone frame; the top bar and
# the screen's radar stay clear of them, in both orientations; the aim pad covers the view.
func test_rails_dock_and_leave_the_screen_unobstructed() -> void:
	for size: Vector2i in SIZES:
		await _open(size)
		var what: String = "%s" % size
		assert_object(_ui()).override_failure_message(what).is_not_null()
		assert_object(_panel().touch()).is_null()
		assert_object(_panel().pages).is_null()
		assert_int(_screen.form).is_equal(LayoutMode.Form.TABLET)
		assert_bool(_screen.rotate_banner.visible).override_failure_message(what).is_false()
		var dock: TabletDock = _ui().dock
		assert_object(_screen.tablet_dock).is_same(dock)
		assert_bool(dock.left.docked and dock.right.docked).is_true()
		assert_bool(dock.portrait).is_equal(size.y > size.x)
		for r: TouchRail in [dock.left, dock.right]:
			var rect: Rect2 = r.get_global_rect()
			assert_bool(rect.intersects(_screen.top_bar.get_global_rect())).is_false()
			assert_bool(rect.intersects(_screen.radar.get_global_rect())).is_false()
			assert_bool(rect.intersects(_panel().get_global_rect())).is_false()
		assert_bool(_screen.radar.is_visible_in_tree()).is_true()
		assert_bool(_ui().pad.is_visible_in_tree()).is_true()
		assert_bool(_panel().get_global_rect().encloses(_ui().pad.get_global_rect())).is_true()
		_vp.queue_free()


# FT: FT-STN-005
# Aim at the left rail's lower corner, FIRE at the right rail's.
func test_aim_and_fire_sit_at_the_lower_corners() -> void:
	for size: Vector2i in SIZES:
		await _open(size)
		var left: Rect2 = _ui().dock.left.get_global_rect()
		var right: Rect2 = _ui().dock.right.get_global_rect()
		var aim: Rect2 = _ui().aim.get_global_rect()
		var fire: Rect2 = _ui().fire_button.get_global_rect()
		assert_bool(left.encloses(aim)).is_true()
		assert_bool(right.encloses(fire)).is_true()
		assert_float(aim.end.y).is_greater(left.end.y - 24.0)
		assert_float(fire.end.y).is_greater(right.end.y - 24.0)
		if size.y > size.x:
			assert_float(aim.position.x - left.position.x).is_less(24.0)
			assert_float(right.end.x - fire.end.x).is_less(24.0)
		_vp.queue_free()


# FT: FT-STN-005
func test_tap_audit_passes_in_both_orientations() -> void:
	for size: Vector2i in SIZES:
		await _open(size)
		_audit_ok(TapAudit.check(_screen.tablet_dock), "rails %s" % size)
		# Mount 1 (one mount), Ammo, Guided, Fire all, Claim, FIRE and the Aim stick.
		assert_int(TapAudit.targets(_screen.tablet_dock).size()).is_equal(7)
		_audit_ok(TapAudit.check(_screen), "screen %s" % size)
		_vp.queue_free()


# FT: FT-WPN-003, FT-WPN-004, FT-WPN-008
func test_button_taps_send_what_their_keys_send() -> void:
	for size: Vector2i in [SIZES[0], SIZES[1]]:
		await _open(size)
		_heard.clear()
		_tap(_ui().mount_buttons[0])
		_tap(_ui().ammo_button)
		_tap(_ui().guided_button)
		_tap(_ui().claim_button)
		assert_array(_heard).is_equal(["mount_1", "ammo_next", "fire_guided", "claim"])
		# One mount: Mount 2 to 4 have no button.
		for i: int in range(1, 4):
			assert_bool(_ui().mount_buttons[i].visible).is_false()
		_vp.queue_free()


# FT: FT-WPN-001
# FIRE and Fire all are held: pressed on the finger's down, released on its up, as LMB and RMB.
func test_fire_and_fire_all_are_held() -> void:
	await _open(SIZES[0])
	for pair: Array in [[_ui().fire_button, "fire"], [_ui().fire_all_button, "fire_all"]]:
		var b: RailButton = pair[0]
		var at: Vector2 = b.get_global_rect().get_center()
		_heard.clear()
		_touch(at, true)
		assert_array(_heard).override_failure_message(pair[1]).is_equal([pair[1]])
		assert_bool(_panel()._firing if pair[1] == "fire" else _panel()._firing_all).is_true()
		_touch(at, false)
		assert_bool(_panel()._firing if pair[1] == "fire" else _panel()._firing_all).is_false()


# FT: FT-STN-005, FT-WPN-009
# The Aim stick drives the pad's aim axes; the aim turns as it does on a pad stick.
func test_the_aim_stick_drives_the_aim_axes() -> void:
	await _open(SIZES[0])
	var aim: VirtualStick = _ui().aim
	var at: Vector2 = aim.get_global_rect().get_center()
	_touch(at, true)
	_drag(at, at + Vector2(0.6, -0.4) * aim.radius())
	var m: InputMatcher = _screen.ctx.matcher
	assert_float(m.axis("aim_x")).is_greater(0.1)
	assert_float(m.axis("aim_y")).is_not_equal(0.0)
	var before: Vector3 = _panel().aim_dir(_panel().mount)
	_panel().step(0.2)
	assert_float(_panel().aim_dir(_panel().mount).angle_to(before)).is_greater(0.0)
	_touch(at, false)
	assert_float(m.axis("aim_x")).is_equal(0.0)
	assert_float(m.axis("aim_y")).is_equal(0.0)


# FT: FT-STN-005, FT-WPN-009
# A finger dragged across the view still aims, and a tap on it is a select, as on a phone.
func test_dragging_the_view_aims_and_a_tap_selects() -> void:
	await _open(SIZES[0])
	var pad: WeaponsAimPad = _ui().pad
	var centre: Vector2 = pad.get_global_rect().get_center()
	var before: Vector3 = _panel().aim_dir(_panel().mount)
	_touch(centre, true)
	_drag(centre, centre + Vector2(60.0, 0.0))
	_touch(centre + Vector2(60.0, 0.0), false)
	assert_float(_panel().aim_dir(_panel().mount).angle_to(before)).is_greater(0.0)
	# A tap (no movement) reaches the select path, never fire; U3 stays selected on empty sky.
	var taps: Array[Vector2] = []
	pad.tapped.connect(func(p: Vector2) -> void: taps.append(p))
	_touch(centre, true)
	_touch(centre, false)
	assert_int(taps.size()).is_equal(1)
	assert_bool(_screen.ctx.crew.is_selected("contact", StationFixture.U3)).is_true()
	# A finger on the view never fires (LMB is FIRE on a desktop).
	assert_bool(_panel()._firing).is_false()


# FT: FT-STN-005
# A rotation rebuilds the dock; a desktop has none and the screen is whole again.
func test_rotation_rebuilds_and_desktop_has_no_rails() -> void:
	await _open(SIZES[0])
	assert_bool(_ui().dock.portrait).is_false()
	var width: float = _panel().get_global_rect().size.x
	_vp.size = SIZES[1]
	await _frames(3)
	assert_bool(_ui().dock.portrait).is_true()
	assert_object(_screen.tablet_dock).is_same(_ui().dock)
	_vp.size = SIZES[0]
	await _frames(3)
	assert_bool(_ui().dock.portrait).is_false()
	assert_float(_panel().get_global_rect().size.x).is_equal_approx(width, 1.0)
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	_vp.size = Vector2i(1280, 720)
	await _frames(3)
	assert_object(_ui()).is_null()
	assert_object(_screen.tablet_dock).is_null()


# FT: FT-STN-005
# FIRE says why it can't shoot, as on the phone, and greys then (a free mount fires, V29).
func test_fire_says_why_it_cannot_shoot() -> void:
	await _open(SIZES[0])
	var fire: RailButton = _ui().fire_button
	_panel().step(0.016)
	assert_str(fire.text).is_equal("FIRE")
	assert_int(fire.role).is_equal(RailButton.Role.DANGER)
	var mount: Dictionary = _screen.ctx.snap.blocks[StationCatalogue.Section.MOUNTS]["mounts"][0]
	mount["heat"] = 40.0
	_panel().step(0.016)
	assert_str(fire.text).is_equal("FIRE\nhot")
	assert_int(fire.role).is_equal(RailButton.Role.PLAIN)
	mount["heat"] = 0.0
	mount["ammo"] = 0
	_panel().step(0.016)
	assert_str(fire.text).is_equal("FIRE\nempty")
