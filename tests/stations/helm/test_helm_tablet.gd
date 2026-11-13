extends GdUnitTestSuite
## Helm on a tablet (#32, D324): two opaque docked rails at the screen's edges with the
## whole tablet screen between them (upright: one bottom bar), no pages, no banner. Every
## control sends the intent its key or stick sends; every target clears the touch rules on
## an iPad (1180x820, 820x1180) and an Android tablet (1280x800).
# FT: FT-STN-005

const SETTINGS: String = "user://test_helm_tablet.cfg"
const INSETS: Array = [0, 0, 0, 24]
const SIZES: Array = [Vector2i(1180, 820), Vector2i(820, 1180), Vector2i(1280, 800)]
const KEYS: Dictionary = {
	"all_stop": "Space",
	"align": "L",
	"dock": "H",
	"jump": "J",
	"shield_track": "G",
	"decoupled": "Tab",
	"chase_camera": "C",
}

var _vp: SubViewport
var _screen: StationScreen
var _panel: HelmPanel
## Intent ids the touch controls fired, in order.
var _fired: Array[String] = []


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## A Helm screen on a touch tablet of `size`.
func _open(size: Vector2i, kind: int = LayoutMode.Kind.TOUCH) -> void:
	LayoutMode.forced = kind
	SafeArea.simulate(INSETS)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("helm", SETTINGS)
	ctx.settings.mark_hint_seen("helm")
	_screen = StationScreen.new()
	_screen.setup(ctx)
	_screen.theme = LayoutMode.theme_for(LayoutMode.Kind.TOUCH)
	_vp.add_child(_screen)
	_panel = _screen.panels[0] as HelmPanel
	await _frames()
	if _ui() != null:
		var sink: Callable = _ui().touch.sink
		_ui().touch.sink = func(ev: IntentEvent) -> void:
			_fired.append(ev.id)
			sink.call(ev)


func _frames(n: int = 3) -> void:
	for i: int in n:
		await get_tree().process_frame
	_panel._process(0.016)


func _ui() -> HelmTouch:
	return _panel.tablet_ui


func _cmds(kind: String) -> Array:
	var out: Array = []
	for s: Array in StationFixture.sent(_screen.ctx).of("command"):
		if s[1][0]["kind"] == kind:
			out.append(s[1][0])
	return out


func _touch(c: Control, at: Vector2, down: bool, index: int = 0) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = down
	c._gui_input(t)


func _drag(c: Control, at: Vector2, index: int = 0) -> void:
	var d: InputEventScreenDrag = InputEventScreenDrag.new()
	d.index = index
	d.position = at
	c._gui_input(d)


func _tap(b: Control) -> void:
	assert_bool(b.is_visible_in_tree()).override_failure_message("%s hidden" % b).is_true()
	_touch(b, b.size / 2.0, true)
	_touch(b, b.size / 2.0, false)


## A dockable site whose zone holds the ship: Dock shows (C3).
func _near_dock() -> void:
	_screen.ctx.snap.sites = [
		{
			"id": 0,
			"name_key": "Yard",
			"kind": &"station",
			"dockable": true,
			"radius": 3000.0,
			"pos": StationFixture.OWN_POS + Vector3(0.0, 0.0, -1000.0)
		}
	]
	_screen.ctx.interp.revision += 1


func _key(name: String, pressed: bool = true) -> void:
	var k: InputEventKey = InputEventKey.new()
	k.physical_keycode = OS.find_keycode_from_string(name)
	k.pressed = pressed
	_screen.feed(k)


func _audit_ok(report: Dictionary, what: String) -> void:
	assert_array(StationFixture.rule_breaks(report, what)).is_empty()


## True when the two rectangles share no area.
func _apart(a: Rect2, b: Rect2) -> bool:
	return not a.intersects(b)


# FT: FT-STN-005
# The dock: two opaque docked rails, no pages, no banner, no phone frame; the top bar, the
# shield ring and the HUD stay clear of them, in both orientations. No radar column (C14):
# the radar is an inset at the view's top right, the ring under it.
func test_rails_dock_and_leave_the_screen_unobstructed() -> void:
	for size: Vector2i in SIZES:
		await _open(size)
		var what: String = "%s" % size
		assert_object(_ui()).override_failure_message(what).is_not_null()
		assert_object(_panel.touch_ui).is_null()
		assert_object(_panel.pages).is_null()
		assert_bool(_panel.in_frame).is_false()
		assert_int(_screen.form).is_equal(LayoutMode.Form.TABLET)
		assert_bool(_screen.rotate_banner.visible).override_failure_message(what).is_false()
		var dock: TabletDock = _ui().dock
		assert_object(_screen.tablet_dock).is_same(dock)
		assert_bool(dock.left.docked and dock.right.docked).is_true()
		assert_bool(dock.portrait).is_equal(size.y > size.x)
		for r: TouchRail in [dock.left, dock.right]:
			var rect: Rect2 = r.get_global_rect()
			assert_bool(_apart(rect, _screen.top_bar.get_global_rect())).is_true()
			assert_bool(_apart(rect, _panel.get_global_rect())).is_true()
		assert_bool(_screen.radar.is_visible_in_tree()).override_failure_message(what).is_false()
		var inset: Rect2 = _ui().radar_box.get_global_rect()
		var view: Rect2 = _panel.get_global_rect()
		assert_bool(_ui().radar_box.is_visible_in_tree()).override_failure_message(what).is_true()
		assert_bool(view.encloses(inset)).override_failure_message(what).is_true()
		assert_float(view.end.x - inset.end.x).is_less_equal(UiTheme.TOUCH_GAP + 1.0)
		(
			assert_bool(_apart(inset, _panel.ring.get_global_rect()))
			. override_failure_message(what)
			. is_true()
		)
		# A view about 672 px wide on a 1024 px tablet (C14).
		assert_float(view.size.x).is_equal_approx(
			size.x - 2.0 * TabletDock.RAIL_WIDTH if size.x > size.y else size.x, 1.0
		)
		assert_bool(_panel.ring.is_visible_in_tree()).is_true()
		assert_object(_panel.ring.get_parent()).is_same(_panel)
		assert_bool(_panel.hud.visible).is_true()
		# The ring and the HUD's view are inside the panel, between the rails.
		assert_bool(_panel.get_global_rect().encloses(_panel.ring.get_global_rect())).is_true()
		_vp.queue_free()
		_screen = null


# FT: FT-STN-005
# The left rail's stick sits at the rail's lower corner with the throttle on its inner side;
# the right rail's Slide stick at its lower corner; upright they are the bar's two ends.
func test_sticks_sit_at_the_lower_corners() -> void:
	for size: Vector2i in SIZES:
		await _open(size)
		var dock: TabletDock = _ui().dock
		var turn: Rect2 = _ui().turn.get_global_rect()
		var slide: Rect2 = _ui().slide.get_global_rect()
		var left: Rect2 = dock.left.get_global_rect()
		var right: Rect2 = dock.right.get_global_rect()
		assert_float(turn.end.y).is_greater(left.end.y - 24.0)
		assert_float(slide.end.y).is_greater(right.end.y - 24.0)
		assert_bool(left.encloses(turn)).is_true()
		assert_bool(right.encloses(slide)).is_true()
		var throttle: Rect2 = _ui().throttle.get_global_rect()
		assert_float(throttle.position.x).is_greater_equal(turn.end.x - 1.0)
		if size.y > size.x:
			assert_float(turn.position.x - left.position.x).is_less(24.0)
			assert_float(right.end.x - slide.end.x).is_less(24.0)
		_vp.queue_free()
		_screen = null


# FT: FT-STN-005
# Every target (the rails' and the screen's own) clears the touch rules: 44 px for any
# target, 48 px for the rails' controls, 8 px between targets, inside the safe area and
# above the gesture band.
func test_tap_audit_passes_in_both_orientations() -> void:
	for size: Vector2i in SIZES:
		await _open(size)
		_audit_ok(TapAudit.check(_screen.tablet_dock), "rails %s" % size)
		var targets: int = TapAudit.targets(_screen.tablet_dock).size()
		# Five buttons (Dock and Jump hide: no dock near, no jump target, C3), two sticks, the
		# throttle, All stop and Approach.
		assert_int(targets).is_equal(10)
		_audit_ok(TapAudit.check(_screen), "screen %s" % size)
		_vp.queue_free()
		_screen = null


# FT: FT-HLM-014, FT-HLM-007, FT-HLM-010, FT-HLM-013, FT-HLM-016, FT-HLM-002, FT-HLM-006
func test_button_taps_send_what_their_keys_send() -> void:
	for size: Vector2i in [SIZES[0], SIZES[1]]:
		await _open(size)
		_near_dock()
		for id: String in KEYS:
			# (Jump shows with a jump target selected, C3)
			_screen.ctx.crew.select(
				"site" if id == "jump" else "contact", 0 if id == "jump" else StationFixture.H2
			)
			await _frames(1)
			StationFixture.sent(_screen.ctx).sent.clear()
			var chase: bool = _panel.chase
			_key(KEYS[id])
			_key(KEYS[id], false)
			var by_key: Array = StationFixture.sent(_screen.ctx).of("command")
			var chase_by_key: bool = _panel.chase
			_panel.chase = chase
			StationFixture.sent(_screen.ctx).sent.clear()
			_fired.clear()
			_tap(_ui().buttons[id])
			var by_touch: Array = StationFixture.sent(_screen.ctx).of("command")
			assert_array(by_touch).override_failure_message(id).is_equal(by_key)
			assert_bool(_panel.chase).override_failure_message(id).is_equal(chase_by_key)
			assert_array(_fired).override_failure_message(id).contains([id])
		_vp.queue_free()
		_screen = null


# FT: FT-HLM-005, FT-HLM-015
func test_face_and_approach_are_held_like_their_keys() -> void:
	await _open(SIZES[0])
	_screen.ctx.crew.select("contact", StationFixture.H2)
	for id: String in ["approach", "face"]:
		var b: RailButton = _ui().buttons[id]
		_touch(b, b.size / 2.0, true)
		await _frames(1)
		assert_bool(_cmds("helm_input").back()[id]).override_failure_message(id).is_true()
		_touch(b, b.size / 2.0, false)
		await _frames(1)
		assert_bool(_cmds("helm_input").back()[id]).override_failure_message(id).is_false()


# FT: FT-STN-005
# Turn is the left stick (yaw, pitch), Slide the right (sway, heave: up lifts); both at once.
func test_stick_drags_send_the_pad_axes() -> void:
	for size: Vector2i in [SIZES[0], SIZES[1]]:
		await _open(size)
		var turn: VirtualStick = _ui().turn
		var slide: VirtualStick = _ui().slide
		_touch(turn, turn.size / 2.0, true, 0)
		_drag(turn, turn.size / 2.0 + Vector2(0.5, 0.3) * turn.radius(), 0)
		_touch(slide, slide.size / 2.0, true, 1)
		_drag(slide, slide.size / 2.0 + Vector2(0.4, -0.6) * slide.radius(), 1)
		var m: InputMatcher = _screen.ctx.matcher
		assert_float(m.axis("helm_yaw")).is_greater(0.1)
		assert_float(m.axis("helm_pitch")).is_not_equal(0.0)
		assert_float(m.axis("helm_sway")).is_greater(0.1)
		assert_float(m.axis("helm_heave")).is_greater(0.1)
		_touch(turn, turn.size / 2.0, false, 0)
		_touch(slide, slide.size / 2.0, false, 1)
		assert_dict(_panel.input_command()).is_equal(HelmPanel._neutral())
		_vp.queue_free()
		_screen = null


# FT: FT-STN-005, FT-SIM-004
# The throttle asks for speed as W does (helm_surge) until the setpoint gets there.
func test_throttle_ramps_the_setpoint_like_the_w_key() -> void:
	await _open(SIZES[0])
	var th: ThrottleSlider = _ui().throttle
	_touch(th, Vector2(th.size.x / 2.0, th.track().position.y), true)
	_touch(th, Vector2(th.size.x / 2.0, th.track().position.y), false)
	await _frames(1)
	assert_float(_panel.input_command()["throttle"]).is_equal(1.0)


# FT: FT-STN-005
# A pointer never steers on a tablet with the rails: the sticks do.
func test_the_pointer_does_not_steer() -> void:
	await _open(SIZES[0])
	assert_bool(_panel.mouse_steers()).is_false()
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	_panel._on_gui_input(mb)
	assert_bool(_panel.mouse_steers()).is_false()


# FT: FT-STN-005
# A rotation rebuilds the dock for the new orientation (and the room it reserves); a desktop
# or an unfocused panel has none, and the screen is whole again.
func test_rotation_rebuilds_and_desktop_has_no_rails() -> void:
	await _open(SIZES[0])
	assert_bool(_ui().dock.portrait).is_false()
	var width: float = _panel.get_global_rect().size.x
	_vp.size = SIZES[1]
	await _frames()
	assert_bool(_ui().dock.portrait).is_true()
	assert_object(_screen.tablet_dock).is_same(_ui().dock)
	var bar: Rect2 = _ui().dock.left.get_global_rect()
	assert_float(bar.size.y).is_equal(TabletDock.BAR_H)
	assert_float(bar.position.y).is_greater(_panel.get_global_rect().end.y - 1.0)
	_vp.size = SIZES[0]
	await _frames()
	assert_bool(_ui().dock.portrait).is_false()
	assert_float(_panel.get_global_rect().size.x).is_equal_approx(width, 1.0)
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	_vp.size = Vector2i(1280, 720)
	await _frames()
	assert_object(_ui()).is_null()
	assert_object(_screen.tablet_dock).is_null()
	assert_float(_panel.get_global_rect().size.x).is_greater(width)


# FT: FT-STN-005
# w5: on every tablet size (the classic iPad's too) a phone-like view keeps the thrust cross
# at the top left, and the flight read-out, the cross, the compass with its chip and the
# shield ring with its caption keep apart.
func test_hud_read_outs_keep_apart() -> void:
	for size: Vector2i in SIZES + [Vector2i(768, 1024), Vector2i(1024, 768)]:
		await _open(size)
		var what: String = "%s" % size
		var hud: HelmHud = _panel.hud
		var area: Rect2 = hud.area()
		if hud.touch_layout():
			assert_float(hud.thrust_rect().get_center().x).override_failure_message(what).is_less(
				area.get_center().x
			)
		var boxes: Array[Rect2] = [hud.readout_rect(), hud.thrust_rect(), hud._ring_rect()]
		var compass: Array[Rect2] = hud.compass_boxes()
		boxes.append(compass[0].grow(-2.0))
		boxes.append(compass[1])
		for i: int in boxes.size():
			for j: int in range(i + 1, boxes.size()):
				if i == 0 and j == 4:
					continue  # the chip under the compass may share the read-out's rows
				(
					assert_bool(boxes[i].intersects(boxes[j]))
					. override_failure_message("%s: %d and %d overlap" % [what, i, j])
					. is_false()
				)
		_vp.queue_free()
		_screen = null


# FT: FT-STN-005, FT-SPA-007
# R05-10: the corner inset takes a finger like the phone's radar: lifted on a blip it selects
# it; the mouse a finger emulates does not select a second time.
func test_a_finger_on_the_corner_inset_selects() -> void:
	await _open(Vector2i(1024, 768))
	var inset: RadarInset = _ui().radar_box
	assert_bool(inset.is_visible_in_tree()).is_true()
	var radar: DiscRadar = inset.radar
	_screen.ctx.crew.selection = {}
	var at: Vector2 = Vector2(-1.0, -1.0)
	for x: int in range(0, int(radar.size.x), 4):
		for y: int in range(0, int(radar.size.y), 4):
			var item: Dictionary = radar.item_at(Vector2(x, y))
			if at.x < 0.0 and not item.is_empty() and item["kind"] == "contact":
				at = Vector2(x, y)
	assert_float(at.x).is_greater_equal(0.0)
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	mb.device = InputEvent.DEVICE_ID_EMULATION
	inset._on_radar_input(mb)
	assert_bool(_screen.ctx.crew.selection.is_empty()).is_true()
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = at
	t.pressed = false
	inset._on_radar_input(t)
	assert_bool(_screen.ctx.crew.selection.is_empty()).is_false()


# FT: FT-HLM-013, FT-HLM-016
# C3 (ux-07): Dock shows only near a dock (Leave dock while docked) and Jump only with a jump
# target selected; the other buttons keep their order.
func test_dock_and_jump_show_only_when_they_can_work() -> void:
	await _open(SIZES[0])
	_screen.ctx.crew.select("contact", StationFixture.H2)
	await _frames(1)
	assert_bool(_ui().buttons["dock"].visible).is_false()
	assert_bool(_ui().buttons["jump"].visible).is_false()
	_near_dock()
	_screen.ctx.crew.select("site", 0)
	await _frames(1)
	assert_bool(_ui().buttons["dock"].visible).is_true()
	assert_str(_ui().buttons["dock"].text).is_equal("Dock here")
	assert_bool(_ui().buttons["jump"].visible).is_true()
	# Dock here docks at the site whose zone holds the ship, selected or not.
	_screen.ctx.crew.select("contact", StationFixture.H2)
	StationFixture.sent(_screen.ctx).sent.clear()
	_tap(_ui().buttons["dock"])
	assert_int(_cmds("helm_dock").back()["site_id"]).is_equal(0)
	_screen.ctx.snap.blocks[StationCatalogue.Section.HELM]["docked_site"] = 0
	await _frames(1)
	assert_str(_ui().buttons["dock"].text).is_equal("Leave dock")
	var order: Array[String] = []
	for b: Node in _ui().buttons["face"].get_parent().get_children():
		order.append(String(b.name))
	assert_array(order).is_equal(
		["face", "align", "shield_track", "dock", "jump", "chase_camera", "decoupled"]
	)


# FT: FT-STN-005
# C3: a Shakedown step that names Dock or Jump shows the button even where it can't work yet,
# so a lesson never names a hidden control.
func test_a_lesson_step_shows_its_rare_button() -> void:
	await _open(SIZES[0])
	_screen.ctx.crew.select("contact", StationFixture.H2)
	for id: String in ["dock", "jump"]:
		_screen.ctx.training["helm"] = {
			"line": "", "intent": id, "text": "", "example": "train.ex." + id, "done": false
		}
		await _frames(1)
		assert_bool(_ui().buttons[id].visible).override_failure_message(id).is_true()
	_screen.ctx.training.erase("helm")
	await _frames(1)
	assert_bool(_ui().buttons["dock"].visible).is_false()
