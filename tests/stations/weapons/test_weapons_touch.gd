extends GdUnitTestSuite
## Weapons on a phone (#28 follow-up, D287, D289): one right rail over a full-width view on
## its side, a controls block under the view upright, the pages Fire, Mounts and Crew,
## touch targets inside the safe area and out of the gesture band on every page, read-outs
## under the view-top row, and touch controls that send what the keys and the pad send.
## The fixture's corvette has one bow mount; U3 sits out of its arc.
# FT: FT-STN-005

const SETTINGS: String = "user://test_weapons_touch.cfg"
## The mockups' iPhone insets [left, top, right, bottom].
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
const AUDIT: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]

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
	await _frames(3)
	_panel(s).step(0.016)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _panel(s: StationScreen) -> WeaponsPanel:
	return s.panels[0] as WeaponsPanel


func _page(s: StationScreen, i: int) -> void:
	_panel(s).pages.current = i
	_panel(s).step(0.016)
	await _frames(2)
	_panel(s).step(0.016)


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
	for rule: String in AUDIT:
		(
			assert_array(report[rule])
			. override_failure_message("%s: %s breaks %s" % [what, report[rule], rule])
			. is_empty()
		)
	return report


## Every visible text of the panel at least 12 px; the mount card's and rows' numbers 14.
func _assert_text_sizes(p: WeaponsPanel, what: String) -> void:
	var stack: Array[Node] = [p.touch()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var c: Control = n as Control
		if c == null or not c.is_visible_in_tree() or not (c is Label or c is Button):
			continue
		var px: int = c.get_theme_font_size(&"font_size")
		(
			assert_int(px)
			. override_failure_message("%s: %s at %d px" % [what, c.name, px])
			. is_greater_equal(12)
		)
	var t: WeaponsTouch = p.touch()
	assert_int(t.mount_button.get_theme_font_size(&"font_size")).is_greater_equal(14)
	assert_int(t.target_label.get_theme_font_size(&"font_size")).is_greater_equal(14)


# FT: FT-STN-005, FT-WPN-001, FT-WPN-002, FT-WPN-004, FT-WPN-006
# On its side: one overlay rail at the right over a full-width view, the screen's radar
# column hidden for the inset at the view's bottom left, FIRE under the right thumb, the
# panel in the frame with the pages Fire, Mounts and Crew, and read-outs under the
# view-top row.
func test_phone_landscape_one_right_rail() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	assert_int(s.form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	assert_bool(p.in_frame).is_true()
	assert_bool(p.full_screen()).is_true()
	var t: WeaponsTouch = p.touch()
	assert_object(t).is_not_null()
	assert_bool(t.layout.docked).is_false()
	assert_object(t.layout.left).is_null()
	assert_bool(s.radar.is_visible_in_tree()).is_false()
	assert_bool(t.radar.is_visible_in_tree()).is_true()
	# The view is full width; the rail's free part is the view_rect.
	assert_float(t.stage.size.x).is_equal(p.size.x)
	var view: Rect2 = p.view_rect()
	var rail: Rect2 = t.layout.right.get_global_rect()
	assert_float((p.get_global_transform() * view.end).x).is_less_equal(rail.position.x)
	# FIRE under the right thumb, the radar at the bottom left of the view.
	var fire: Rect2 = t.fire_button.get_global_rect()
	assert_float(fire.size.x).is_greater_equal(150.0)
	assert_float(fire.size.y).is_greater_equal(WeaponsTouch.FIRE_H)
	assert_bool(rail.encloses(fire)).is_true()
	var radar: Rect2 = t.radar_box.get_global_rect()
	assert_float(radar.size.x).is_equal(WeaponsTouch.RADAR_W)
	assert_float(radar.position.x).is_less(s._main.get_global_rect().get_center().x)
	# Pages: Fire first and current; its zone in the rail; the tabs in the top bar.
	assert_array(p.pages.titles()).is_equal(["Fire", "Mounts", "Crew"])
	assert_int(p.pages.current).is_equal(WeaponsTouch.Page.FIRE)
	assert_int(s.top_bar.tabs.tab_count()).is_equal(3)
	for b: RailButton in [
		t.mount_button,
		t.ammo_button,
		t.guided_button,
		t.fire_all_button,
		t.claim_button,
		t.fire_button
	]:
		assert_bool(b.is_visible_in_tree()).override_failure_message(b.name).is_true()
		assert_bool(rail.encloses(b.get_global_rect())).is_true()
	assert_bool(t.mount_list.is_visible_in_tree()).is_false()
	assert_str(t.mount_button.text).is_equal("1 bow · ready\nheat 15% · 380/400")
	assert_str(t.claim_button.text).is_equal("Release")
	assert_str(t.ammo_button.text).is_equal("Mass driver ▸")
	assert_str(t.target_label.text).starts_with("Target U3")
	# Read-outs under the view-top row (the selection chip shows U3).
	assert_float(p.top_reserve).is_greater(0.0)
	var top: float = (p.get_global_transform() * view.position).y + p.top_reserve
	assert_float(t.target_label.get_global_rect().position.y).is_greater_equal(top)
	assert_float(s.frame.selection_chip.get_global_rect().end.y).is_less_equal(top)
	# The shares are on the Crew page: no Share opener on the screen.
	assert_bool(p.shows_shares).is_true()
	assert_bool(s.share_opener.is_visible_in_tree()).is_false()


# FT: FT-STN-005, FT-WPN-001, FT-WPN-002
# Upright: the view on top with the radar inset, the controls block under it (the page
# zone at the left, the mount card and FIRE at the right), the tabs in the bottom tab bar,
# the "turn sideways" banner.
func test_phone_portrait_controls_block_and_bottom_tabs() -> void:
	var s: StationScreen = await _screen(Vector2i(390, 844), PORTRAIT)
	var p: WeaponsPanel = _panel(s)
	assert_int(s.form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	assert_bool(s.rotate_banner.visible).is_true()
	var t: WeaponsTouch = p.touch()
	assert_object(t.layout).is_null()
	assert_bool(t.radar.is_visible_in_tree()).is_true()
	assert_bool(s.radar.is_visible_in_tree()).is_false()
	assert_bool(s.frame.bottom_tabs.is_visible_in_tree()).is_true()
	assert_int(s.frame.bottom_tabs.tab_count()).is_equal(3)
	var view: Rect2 = t.stage.get_global_rect()
	assert_bool(view.encloses(t.radar_box.get_global_rect())).is_true()
	for b: RailButton in [
		t.mount_button, t.claim_button, t.ammo_button, t.guided_button, t.fire_all_button
	]:
		assert_bool(b.is_visible_in_tree()).is_true()
		assert_float(b.get_global_rect().position.y).is_greater_equal(view.end.y)
	var fire: Rect2 = t.fire_button.get_global_rect()
	assert_float(fire.position.x).is_greater(view.get_center().x)
	assert_float(fire.size.y).is_greater_equal(WeaponsTouch.FIRE_H)
	assert_float(fire.end.y).is_less_equal(
		s.frame.bottom_tabs.get_global_rect().position.y - UiTheme.TOUCH_GAP + 0.5
	)


# FT: FT-STN-005
# The touch rules hold on every page both ways up (48 px targets with 8 px gaps, none in the
# band or under an inset) and no text is under 12 px; each page shows only its own part.
func test_touch_rules_on_every_page_both_ways() -> void:
	for c: Array in [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], c[1])
		var p: WeaponsPanel = _panel(s)
		var t: WeaponsTouch = p.touch()
		# The frame puts the view-top row right under the "turn sideways" banner (0 px from
		# its ×, a Request to the frame's owner); the audit runs with the banner dismissed.
		s.rotate_banner.dismiss()
		await _frames(2)
		for i: int in p.pages.count():
			await _page(s, i)
			var what: String = "%s %s" % [c[0], p.pages.title(i)]
			_assert_touch_rules(s, what)
			_assert_text_sizes(p, what)
			assert_bool(t.fire_zone.is_visible_in_tree()).is_equal(i == WeaponsTouch.Page.FIRE)
			assert_bool(t.mount_list.is_visible_in_tree()).is_equal(i == WeaponsTouch.Page.MOUNTS)
			assert_bool(t.crew.is_visible_in_tree()).is_equal(i == WeaponsTouch.Page.CREW)
			assert_bool(t.target_label.visible).is_equal(i != WeaponsTouch.Page.MOUNTS)
			# FIRE and the radar never page away (FT-WPN-002).
			assert_bool(t.fire_button.is_visible_in_tree()).is_true()
			assert_bool(t.radar.is_visible_in_tree()).is_true()
			# The mount list stays clear of the radar inset.
			if t.mount_list.is_visible_in_tree():
				var list: Rect2 = t.mount_list.get_global_rect()
				assert_bool(list.intersects(t.radar_box.get_global_rect())).is_false()
				assert_float(list.size.y).is_greater_equal(WeaponsTouch.ROW_H)


# FT: FT-STN-005
# Rotating swaps the arrangement and keeps the panel's pages; a tablet keeps today's layout
# without rails or pages (D223), and so does a window too small to be a phone.
func test_rotation_and_other_forms() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	assert_int(p.touch().form).is_equal(LayoutMode.Form.PHONE_LANDSCAPE)
	SafeArea.simulate(PORTRAIT)
	_vp.size = Vector2i(390, 844)
	await _frames(3)
	assert_int(p.touch().form).is_equal(LayoutMode.Form.PHONE_PORTRAIT)
	assert_object(p.pages).is_same(p.touch().pages)
	SafeArea.simulate([])
	_vp.size = Vector2i(1280, 720)
	await _frames(3)
	assert_object(p.touch()).is_null()
	assert_object(p.pages).is_null()
	assert_bool(s.radar.is_visible_in_tree()).is_true()
	assert_object(p._view.get_parent()).is_same(p)
	_vp.size = Vector2i(64, 64)
	await _frames(3)
	assert_object(p.touch()).is_null()


# FT: FT-STN-005, FT-WPN-003, FT-WPN-006, FT-WPN-008
# The rail buttons send what the keys send: FIRE held fires like LMB, Fire all held fires
# like RMB, the ammo button is `ammo_next`, Guided is `fire_guided` (refused alike while U3
# is out of arc), the mount card is `mount_next`, Release is the screen's `claim`. A rail
# tap never also reaches the screen as a select or a fire.
func test_rail_buttons_send_the_key_intents() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	var t: WeaponsTouch = p.touch()
	var heard: Array[String] = []
	p.touch_intent.connect(func(id: String) -> void: heard.append(id))
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
	# Fire all held: every claimed mount fires at the target, as RMB does.
	at = t.fire_all_button.get_global_rect().get_center()
	_touch(at, true)
	assert_bool(p._firing_all).is_true()
	_touch(at, false)
	assert_bool(p._firing_all).is_false()
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
	# One mount: the mount card keeps it.
	_tap(t.mount_button)
	assert_int(p.mount).is_equal(0)
	# Release, as K does.
	_tap(t.claim_button)
	assert_array(StationFixture.sent(s.ctx).of("release_claim")).has_size(1)
	assert_array(heard).is_equal(
		["fire", "fire_all", "ammo_next", "fire_guided", "mount_next", "claim"]
	)
	# None of the taps selected or fired through the screen.
	assert_int(int(s.ctx.crew.selection.get("id", -1))).is_equal(StationFixture.U3)
	assert_int(_commands(s, "fire").size()).is_equal(1)
	# The keyboard's fire hold sends the same command.
	var k: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	_panel(k).set_aim_dir(0, k.ctx.interp.own_rotation() * Vector3.FORWARD)
	_panel(k).handle_intent({"id": "fire", "pressed": true, "device": IntentTable.KBM})
	_panel(k).step(0.016)
	assert_array(_commands(k, "fire")).is_equal(fired)


# FT: FT-STN-005, FT-WPN-004, FT-WPN-003
# The Mounts page lists every mount with its state and claimer: a row's tap looks through
# it (`mount_1`, as the 1 key), its Claim claims the mount (as K), its Release frees it.
func test_mount_list_looks_and_claims() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE, false)
	var p: WeaponsPanel = _panel(s)
	var t: WeaponsTouch = p.touch()
	var heard: Array[String] = []
	p.touch_intent.connect(func(id: String) -> void: heard.append(id))
	await _page(s, WeaponsTouch.Page.MOUNTS)
	assert_int(t.rows.size()).is_equal(p.mount_count())
	var look: RailButton = t.rows[0][0]
	var claim: RailButton = t.rows[0][1]
	assert_str(look.text).is_equal("1 bow · ready\nheat 15% · 380/400")
	assert_str(claim.text).is_equal("Claim")
	_tap(look)
	assert_array(heard).is_equal(["mount_1"])
	_tap(claim)
	assert_array(heard).is_equal(["mount_1", "mount_1", "claim"])
	assert_array(StationFixture.sent(s.ctx).of("claim")).is_equal([["claim", ["mount:0"]]])
	# Held by someone else: the row names them and can't be claimed.
	s.ctx.crew.claims["mount:0"] = {"session": 99, "name": "Bo"}
	p.step(0.016)
	assert_str(claim.text).is_equal("Bo")
	assert_bool(claim.disabled).is_true()


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
	assert_array(StationFixture.sent(s.ctx).of("ping")).is_empty()
	# A tap on the U3 bracket (no drag) selects it; nothing fires.
	s.ctx.crew.select("contact", StationFixture.H2)
	_look_at(p, StationFixture.U3)
	var at: Vector2 = _bracket(p, StationFixture.U3)
	_touch(at, true)
	_touch(at, false)
	assert_int(int(s.ctx.crew.selection["id"])).is_equal(StationFixture.U3)
	assert_array(_commands(s, "fire")).is_empty()


## Turns the camera mount's aim onto contact `id`, so its bracket sits mid-view (clear of
## the view-top row).
func _look_at(p: WeaponsPanel, id: int) -> void:
	var to: Vector3 = p.ctx.interp.offset_to(p.ctx.interp.contact_position(id))
	p.set_aim_dir(0, to.normalized())
	p.step(0.016)


## The viewport position of contact `id`'s bracket.
func _bracket(p: WeaponsPanel, id: int) -> Vector2:
	for target: Dictionary in p._targets:
		if int(target["item"]["id"]) == id:
			return p._overlay.get_global_transform() * (target["pos"] as Vector2)
	return Vector2(-1, -1)


# FT: FT-SPA-016, FT-SPA-013, FT-SPA-030, FT-STN-005
# A finger held still on the turret view pings what is under it (P28-Common); held then
# dragged it marks the contact it ends on (a forward view marks contacts only), and the aim
# doesn't move while it does; a quick tap only selects.
func test_long_press_on_the_view_pings_and_marks() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	var clock: StationFixture.Clock = StationFixture.clock(s.ctx)
	var lp: LongPress = s.frame.long_press
	s.ctx.crew.select("contact", StationFixture.H2)
	_look_at(p, StationFixture.U3)
	var u3: Vector2 = _bracket(p, StationFixture.U3)
	assert_bool(p.touch().stage.get_global_rect().has_point(u3)).is_true()
	var aim: Vector3 = p.aim_dir(0)
	_touch(u3, true)
	clock.ms += LongPress.HOLD_MS + 10
	lp.update(clock.ms)
	assert_bool(lp.is_armed()).is_true()
	_touch(u3, false)
	var pings: Array = StationFixture.sent(s.ctx).of("ping")
	assert_int(pings.size()).is_equal(1)
	assert_int(int(pings[0][1][1])).is_equal(StationFixture.U3)
	# Held beside U3, then dragged onto its bracket: a mark attached to U3.
	var from: Vector2 = u3 + Vector2(-60, 40)
	_touch(from, true)
	clock.ms += LongPress.HOLD_MS + 10
	lp.update(clock.ms)
	_drag(from, u3)
	_touch(u3, false)
	var marks: Array = StationFixture.sent(s.ctx).of("place_mark")
	assert_int(marks.size()).is_equal(1)
	assert_int(int(marks[0][1][2])).is_equal(StationFixture.U3)
	assert_float(p.aim_dir(0).angle_to(aim)).is_less(1e-4)
	assert_int(TouchInput.held).is_equal(0)
	# A quick tap selects and neither pings nor marks.
	_touch(u3, true)
	clock.ms += 100
	_touch(u3, false)
	assert_int(StationFixture.sent(s.ctx).of("ping").size()).is_equal(1)
	assert_int(int(s.ctx.crew.selection["id"])).is_equal(StationFixture.U3)


# FT: FT-WPN-005
# The out-of-arc warning sits under the view-top row, beside the rail, and moves below any
# bracket, chip or the target line it would cover (it hid U3's chip on a phone).
func test_out_of_arc_warning_clears_the_chips() -> void:
	for c: Array in [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], c[1])
		var p: WeaponsPanel = _panel(s)
		var arc: String = p.out_of_arc_text()
		assert_str(arc).starts_with("U3 out of arc")
		var r: Rect2 = p.arc_warning_rect(p.get_theme_default_font(), arc)
		for target: Dictionary in p._targets:
			assert_bool((target["rect"] as Rect2).intersects(r)).is_false()
		var g: Rect2 = p._overlay.get_global_transform() * r
		assert_bool(g.intersects(p.touch().target_label.get_global_rect())).is_false()
		assert_bool(g.intersects(s.frame.selection_chip.get_global_rect())).is_false()
		var view: Rect2 = p.get_global_transform() * p.view_rect()
		assert_bool(view.encloses(g)).override_failure_message(str(c[0])).is_true()
		assert_float(r.end.y).is_less(p._overlay.size.y / 2.0)


# FT: FT-STN-010, FT-PAIR-012, FT-SPA-016, FT-STN-005
# The Crew page holds Weapons' requests (power from Engineering, bring the mount to bear
# from Helm), Ping and Mark on the selection; each sends what the chip key and the common
# keys send.
func test_crew_page_requests_ping_and_mark() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	var t: WeaponsTouch = p.touch()
	await _page(s, WeaponsTouch.Page.CREW)
	t.crew.refresh()
	await _frames(1)
	for id: String in ["power", "bring_to_bear"]:
		var b: RailButton = t.crew.button("chip", id)
		assert_object(b).override_failure_message(id).is_not_null()
		_tap(b)
	var chips: Array = StationFixture.sent(s.ctx).of("send_chip")
	assert_array(chips).is_equal(
		[["send_chip", ["power", -1]], ["send_chip", ["bring_to_bear", 0]]]
	)
	_tap(t.crew.button("ping"))
	assert_int(StationFixture.sent(s.ctx).of("ping").size()).is_equal(1)
	_tap(t.crew.button("mark"))
	var marks: Array = StationFixture.sent(s.ctx).of("place_mark")
	assert_int(marks.size()).is_equal(1)
	assert_int(int(marks[0][1][2])).is_equal(StationFixture.U3)


# FT: FT-STN-012, FT-STN-005
# The touch help picture (P28-Help) numbers the controls where they are: its Fire and Mounts
# callouts sit on the real controls of the 844 x 390 phone (within a few px), and every
# callout has a text.
func test_touch_help_matches_the_layout() -> void:
	var s: StationScreen = await _screen(Vector2i(844, 390), LANDSCAPE)
	var p: WeaponsPanel = _panel(s)
	var t: WeaponsTouch = p.touch()
	var fire: Array = WeaponsTouchHelp.callouts(WeaponsTouch.Page.FIRE)
	var real: Array[Control] = [
		t.mount_button, t.ammo_button, t.guided_button, t.fire_all_button, t.claim_button
	]
	real.append(t.fire_button)
	for i: int in real.size():
		var want: Rect2 = real[i].get_global_rect()
		var got: Rect2 = fire[i][0]
		var what: String = "%s: %s vs %s" % [fire[i][1], got, want]
		(
			assert_float(got.position.distance_to(want.position))
			. override_failure_message(what)
			. is_less(6.0)
		)
		assert_float(got.end.distance_to(want.end)).override_failure_message(what).is_less(6.0)
	await _page(s, WeaponsTouch.Page.MOUNTS)
	var rows: Array = WeaponsTouchHelp.callouts(WeaponsTouch.Page.MOUNTS)
	for i: int in 2:
		var want: Rect2 = (t.rows[0][i] as Control).get_global_rect()
		var got: Rect2 = rows[i][0]
		var what: String = "%s: %s vs %s" % [rows[i][1], got, want]
		(
			assert_float(got.position.distance_to(want.position))
			. override_failure_message(what)
			. is_less(6.0)
		)
		assert_float(got.end.distance_to(want.end)).override_failure_message(what).is_less(6.0)
	for page: int in WeaponsTouchHelp.PAGES.size():
		for c: Array in WeaponsTouchHelp.callouts(page):
			assert_str(c[1]).is_not_empty()
