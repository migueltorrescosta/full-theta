extends GdUnitTestSuite
## Weapons on a phone (#28, owner pick B): docked rails in landscape, a reduced upright
## layout, touch targets inside the safe area and out of the gesture band, and touch
## controls that send what the keys and the pad send. The fixture's corvette has one bow
## mount; U3 sits out of its arc.
# FT: FT-STN-005

const SETTINGS: String = "user://test_weapons_touch.cfg"
## The mockups' iPhone insets [left, top, right, bottom].
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, insets: Array, mine: bool = true) -> StationScreen:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("weapons", SETTINGS)
	if mine:
		ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	ctx.crew.select("contact", StationFixture.U3)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	_vp.add_child(s)
	_panel(s).set_process(false)
	for i: int in 3:
		await get_tree().process_frame
	_panel(s).step(0.016)
	return s


func _panel(s: StationScreen) -> WeaponsPanel:
	return s.panels[0] as WeaponsPanel


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


## A finger down (or up) at `global` (viewport px), finger `index`.
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
	var at: Vector2 = c.get_global_rect().get_center()
	_touch(at, true)
	_touch(at, false)


func _assert_touch_rules(s: StationScreen, what: String) -> Dictionary:
	var report: Dictionary = TapAudit.check(s)
	assert_array(report["targets"]).is_not_empty()
	for rule: String in ["under_min", "under_primary", "in_band", "outside_safe", "tight"]:
		(
			assert_array(report[rule])
			. override_failure_message("%s: %s breaks %s" % [what, report[rule], rule])
			. is_empty()
		)
	return report


# FT: FT-STN-005, FT-WPN-001, FT-WPN-002, FT-WPN-004, FT-WPN-006
# Landscape: docked rails, the screen's radar column gives way to the rail radar, every
# target at least 48 px with 8 px gaps, none under an inset or in the gesture band, a
# 152 x 100 FIRE and an aiming view of about 400 px between the rails.
func test_phone_landscape_docked_rails() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	assert_int(s.form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	assert_bool(p.full_screen()).is_true()
	var t: WeaponsTouch = p.touch()
	assert_object(t).is_not_null()
	assert_bool(t.layout.docked).is_true()
	assert_bool(s.radar.is_visible_in_tree()).is_false()
	assert_object(t.radar).is_not_null()
	assert_bool(t.radar.is_visible_in_tree()).is_true()
	assert_float(t.radar.size.x).is_greater_equal(156.0)
	_assert_touch_rules(s, "landscape")
	var fire: Rect2 = t.fire_button.get_global_rect()
	assert_float(fire.size.x).is_greater_equal(150.0)
	assert_float(fire.size.y).is_greater_equal(WeaponsTouch.FIRE_H)
	# FIRE under the right thumb, the mount button top left.
	assert_float(fire.position.x).is_greater_equal(t.stage.get_global_rect().end.x)
	assert_float(t.mount_button.get_global_rect().end.x).is_less_equal(
		t.stage.get_global_rect().position.x
	)
	assert_float(t.stage.size.x).is_between(380.0, 420.0)
	assert_str(t.mount_button.text).is_equal("1 bow · ready\nheat 15% · 380/400")
	assert_str(t.claim_button.text).is_equal("Release")
	assert_str(t.ammo_button.text).is_equal("Mass driver ▸")
	assert_str(t.target_label.text).starts_with("Target U3")


# FT: FT-STN-005, FT-WPN-001, FT-WPN-002
# Upright: the reduced layout under the "turn sideways" banner keeps every action; the
# screen keeps its own radar under the panel.
func test_phone_portrait_reduced_layout() -> void:
	var s: StationScreen = await _screen(Vector2i(390, 844), PORTRAIT)
	var p: WeaponsPanel = _panel(s)
	assert_int(s.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	assert_bool(s.rotate_banner.visible).is_true()
	var t: WeaponsTouch = p.touch()
	assert_object(t).is_not_null()
	assert_object(t.layout).is_null()
	assert_object(t.radar).is_null()
	assert_bool(s.radar.is_visible_in_tree()).is_true()
	for b: RailButton in [
		t.mount_button, t.claim_button, t.ammo_button, t.guided_button, t.fire_button
	]:
		assert_bool(b.is_visible_in_tree()).is_true()
	_assert_touch_rules(s, "portrait")
	# The buttons sit under the view, FIRE at the right.
	var view: Rect2 = t.stage.get_global_rect()
	assert_float(t.mount_button.get_global_rect().position.y).is_greater_equal(view.end.y)
	assert_float(t.fire_button.get_global_rect().end.x).is_greater(view.get_center().x)


# FT: FT-STN-005
# Rotating swaps the arrangement; a tablet keeps today's layout without rails (D223), and
# so does a window too small to be a phone.
func test_rotation_and_other_forms() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	assert_int(p.touch().form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	SafeArea.simulate(PORTRAIT)
	_vp.size = Vector2i(390, 844)
	for i: int in 3:
		await get_tree().process_frame
	assert_int(p.touch().form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	SafeArea.simulate([])
	_vp.size = Vector2i(1280, 720)
	for i: int in 3:
		await get_tree().process_frame
	assert_object(p.touch()).is_null()
	assert_bool(s.radar.is_visible_in_tree()).is_true()
	assert_object(p._view.get_parent()).is_same(p)
	_vp.size = Vector2i(64, 64)
	for i: int in 3:
		await get_tree().process_frame
	assert_object(p.touch()).is_null()


# FT: FT-STN-005, FT-WPN-003, FT-WPN-006, FT-WPN-008
# The rail buttons send what the keys send: FIRE held fires like LMB, the ammo button is
# `ammo_next`, Guided is `fire_guided` (refused alike while U3 is out of arc), the
# mount button is `mount_next`, Release is the screen's `claim`. A rail tap never also
# reaches the screen as a select or a fire.
func test_rail_buttons_send_the_key_intents() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	var t: WeaponsTouch = p.touch()
	var toasts: Array = []
	s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
	# U3 is out of arc: aim straight ahead first, so FIRE can fire.
	p.set_aim_dir(0, s.ctx.interp.own_rotation() * Vector3.FORWARD)
	var at: Vector2 = t.fire_button.get_global_rect().get_center()
	_touch(at, true)
	p.step(0.016)
	var fired: Array = _commands(s, "fire")
	assert_int(fired.size()).is_equal(1)
	assert_int(int(fired[0]["mount_index"])).is_equal(0)
	_touch(at, false)
	p.step(0.016)
	assert_bool(p._firing).is_false()
	# Ammo: the next type, as Q does.
	_tap(t.ammo_button)
	var switched: Array = _commands(s, "set_ammo_type")
	assert_int(switched.size()).is_equal(1)
	assert_int(int(switched[0]["ammo_type"])).is_equal(1)
	# Guided: the same answer as G (U3 is out of arc, so a toast and no shot).
	toasts.clear()
	_tap(t.guided_button)
	var by_touch: Array = toasts.duplicate()
	toasts.clear()
	p.handle_intent({"id": "fire_guided", "pressed": true, "device": IntentTable.KBM})
	assert_array(by_touch).is_not_empty()
	assert_array(by_touch).is_equal(toasts)
	assert_array(_commands(s, "fire_guided")).is_empty()
	# One mount: the mount button keeps it.
	_tap(t.mount_button)
	assert_int(p.mount).is_equal(0)
	# Release, as K does.
	_tap(t.claim_button)
	assert_array(StationFixture.sent(s.ctx).of("release_claim")).has_size(1)
	# None of the taps selected or fired through the screen.
	assert_int(int(s.ctx.crew.selection.get("id", -1))).is_equal(StationFixture.U3)
	assert_int(_commands(s, "fire").size()).is_equal(1)
	# The keyboard's fire hold sends the same command.
	var k: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	_panel(k).set_aim_dir(0, k.ctx.interp.own_rotation() * Vector3.FORWARD)
	_panel(k).handle_intent({"id": "fire", "pressed": true, "device": IntentTable.KBM})
	_panel(k).step(0.016)
	assert_array(_commands(k, "fire")).is_equal(fired)


# FT: FT-STN-005, FT-WPN-001, FT-WPN-009
# A finger dragged across the view turns the aim by the angle it covers on screen (right
# is right) and sends `aim_mount`; a tap on a bracket selects its contact and fires nothing.
func test_drag_aims_and_tap_selects() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	var t: WeaponsTouch = p.touch()
	var fwd: Vector3 = s.ctx.interp.own_rotation() * Vector3.FORWARD
	p.set_aim_dir(0, fwd)
	p.step(0.016)
	var sent: int = _commands(s, "aim_mount").size()
	var before: Vector3 = p.aim_dir(0)
	var c: Vector2 = t.stage.get_global_rect().get_center()
	_touch(c, true)
	_drag(c, c + Vector2(20, 0))
	_drag(c + Vector2(20, 0), c + Vector2(40, 0))
	_touch(c + Vector2(40, 0), false)
	var f: float = (t.stage.size.y / 2.0) / tan(deg_to_rad(p.fov) / 2.0)
	assert_float(before.angle_to(p.aim_dir(0))).is_equal_approx(40.0 / f, 2e-3)
	p._flush_aims(s.ctx.now_ms(), true)
	assert_int(_commands(s, "aim_mount").size()).is_greater(sent)
	var seen: Variant = p.project(p.aim_dir(0))
	assert_object(seen).is_not_null()
	# A tap on the U3 bracket (no drag) selects it; nothing fires.
	s.ctx.crew.select("contact", StationFixture.H2)
	p.set_aim_dir(0, fwd)
	p.step(0.016)
	var u3: Dictionary = {}
	for target: Dictionary in p._targets:
		if int(target["item"]["id"]) == StationFixture.U3:
			u3 = target
	assert_dict(u3).is_not_empty()
	var at: Vector2 = p._overlay.get_global_transform() * (u3["pos"] as Vector2)
	_touch(at, true)
	_touch(at, false)
	assert_int(int(s.ctx.crew.selection["id"])).is_equal(StationFixture.U3)
	assert_array(_commands(s, "fire")).is_empty()


# FT: FT-WPN-005
# The out-of-arc warning moves below any bracket or chip it would cover (it hid U3's chip
# on a phone).
func test_out_of_arc_warning_clears_the_chips() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	var arc: String = p.out_of_arc_text()
	assert_str(arc).starts_with("U3 out of arc")
	var r: Rect2 = p.arc_warning_rect(p.get_theme_default_font(), arc)
	assert_array(p._targets).is_not_empty()
	for target: Dictionary in p._targets:
		assert_bool((target["rect"] as Rect2).intersects(r)).is_false()
	assert_float(r.position.y).is_greater_equal(0.0)
	assert_float(r.end.y).is_less(p._overlay.size.y / 2.0)
