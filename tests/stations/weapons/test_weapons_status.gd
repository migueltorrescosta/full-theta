extends GdUnitTestSuite
## C6, phone Weapons: heat as a word and a colour, rounds named, FIRE saying why it can't
## shoot, one Claim button whatever the state, an arrow at the reticle toward an out-of-arc
## target. The fixture's corvette has one bow mount (40 heat limit, 400 rounds); U3 sits out of
## its arc. A free mount fires without a claim (V29), so "free" is no reason to block FIRE.
# FT: FT-STN-005, FT-WPN-005

const SETTINGS: String = "user://test_weapons_status.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const MOUNTS: StationViews.Section = StationViews.Section.MOUNTS

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(mine: bool, select: bool = true) -> StationScreen:
	SafeArea.simulate(LANDSCAPE)
	_vp = auto_free(SubViewport.new())
	_vp.size = Vector2i(844, 390)
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("weapons", SETTINGS)
	if mine:
		ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	if select:
		ctx.crew.select("contact", StationFixture.U3)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	_vp.add_child(s)
	(s.panels[0] as WeaponsPanel).set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _set_mount(s: StationScreen, key: String, value: Variant) -> void:
	s.ctx.view.blocks[MOUNTS]["mounts"][0][key] = value


func _frame(s: StationScreen) -> WeaponsTouch:
	var p: WeaponsPanel = s.panels[0] as WeaponsPanel
	p.step(0.016)
	return p.touch()


func test_heat_reads_as_a_word_and_a_colour() -> void:
	var s: StationScreen = await _screen(true)
	var p: WeaponsPanel = s.panels[0] as WeaponsPanel
	# 6 of 40: cool, plain text.
	assert_str(WeaponsStatus.heat_word(p, 0)).is_equal("cool")
	assert_str(WeaponsStatus.heat_role(p, 0)).is_equal("text")
	_set_mount(s, "heat", 30.0)
	assert_str(WeaponsStatus.heat_word(p, 0)).is_equal("warm")
	assert_str(WeaponsStatus.heat_role(p, 0)).is_equal("warn")
	_set_mount(s, "heat", 40.0)
	assert_str(WeaponsStatus.heat_word(p, 0)).is_equal("HOT")
	assert_str(WeaponsStatus.heat_role(p, 0)).is_equal("danger_text")
	var t: WeaponsTouch = _frame(s)
	assert_str(t.mount_button.text).contains("heat 100% HOT")
	assert_bool(t.mount_button.has_theme_color_override("font_color")).is_true()


func test_ammo_is_labelled() -> void:
	var s: StationScreen = await _screen(true)
	var p: WeaponsPanel = s.panels[0] as WeaponsPanel
	assert_str(WeaponsStatus.mount_text(p, 0)).contains("380/400 rounds")
	assert_str(WeaponsStatus.mount_text(p, 0, true)).is_equal(
		"1 bow · ready\nheat 15% cool · 380/400 rounds"
	)


func test_fire_says_why_it_cannot_shoot() -> void:
	var s: StationScreen = await _screen(true)
	var p: WeaponsPanel = s.panels[0] as WeaponsPanel
	# In arc (the bow's rest direction): FIRE, red.
	assert_str(WeaponsStatus.fire_block(p, 0)).is_empty()
	var t: WeaponsTouch = _frame(s)
	assert_str(t.fire_button.text).is_equal("FIRE")
	assert_int(t.fire_button.role).is_equal(RailButton.Role.DANGER)
	_set_mount(s, "heat", 40.0)
	t = _frame(s)
	assert_str(t.fire_button.text).is_equal("FIRE\nhot")
	assert_int(t.fire_button.role).is_equal(RailButton.Role.PLAIN)
	_set_mount(s, "heat", 6.0)
	_set_mount(s, "ammo", 0)
	assert_str(WeaponsStatus.fire_text(p, 0)).is_equal("FIRE\nempty")
	_set_mount(s, "ammo", 380)
	# Aimed out of the arc (the ship turned away): the reason names it.
	_set_mount(s, "barrel", Vector3.BACK)
	p.set_aim_dir(0, Vector3.BACK)
	assert_str(WeaponsStatus.fire_text(p, 0)).is_equal("FIRE\nout of arc")


func test_a_free_mount_still_fires_and_a_held_one_says_so() -> void:
	var free: StationScreen = await _screen(false)
	var p: WeaponsPanel = free.panels[0] as WeaponsPanel
	assert_str(WeaponsStatus.fire_block(p, 0)).is_empty()
	assert_str(_frame(free).fire_button.text).is_equal("FIRE")
	var held: StationScreen = await _screen(false)
	held.ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION + 1, "name": "Bo"}
	var q: WeaponsPanel = held.panels[0] as WeaponsPanel
	assert_str(WeaponsStatus.fire_block(q, 0)).is_equal("taken")
	assert_str(_frame(held).fire_button.text).is_equal("FIRE\nheld")


func test_claim_is_one_button_in_every_state() -> void:
	var mine: StationScreen = await _screen(true)
	var t: WeaponsTouch = _frame(mine)
	assert_str(t.claim_button.text).is_equal("✓ Claim")
	assert_int(t.claim_button.role).is_equal(RailButton.Role.ACCENT)
	var free: StationScreen = await _screen(false)
	t = _frame(free)
	assert_str(t.claim_button.text).is_equal("Claim")
	assert_bool(t.claim_button.disabled).is_false()
	var other: StationScreen = await _screen(false)
	other.ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION + 1, "name": "Bo"}
	t = _frame(other)
	assert_str(t.claim_button.text).is_equal("Bo")
	assert_bool(t.claim_button.disabled).is_true()


func test_an_arrow_at_the_reticle_points_to_the_out_of_arc_target() -> void:
	var s: StationScreen = await _screen(true)
	var p: WeaponsPanel = s.panels[0] as WeaponsPanel
	_frame(s)
	# U3 sits out of the arc: the arrow points toward it, as a unit vector.
	assert_str(p.out_of_arc_text()).is_not_empty()
	assert_float(WeaponsStatus.arc_arrow_dir(p).length()).is_equal_approx(1.0, 0.001)
	# No target, no arrow.
	var none: StationScreen = await _screen(true, false)
	assert_vector(WeaponsStatus.arc_arrow_dir(none.panels[0] as WeaponsPanel)).is_equal(
		Vector2.ZERO
	)
