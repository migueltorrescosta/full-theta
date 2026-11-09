extends GdUnitTestSuite
## C4, Engineering's rail: a button that acts on the picked part names it on a second line,
## a button that can't act is greyed with the reason there, and a tablet gets the Helm and
## Weapons rail pattern (two docked rails, TabletDock) instead of the desktop layout alone.
## The fixture's corvette: engines (40 %, crew A on them, no fault), 6 spare parts, 10 of 12
## reactor pips used.
# FT: FT-STN-005, FT-ENG-002, FT-ENG-004, FT-ENG-008

const SETTINGS: String = "user://test_engineering_rail.cfg"
const ENG: StationViews.Section = StationViews.Section.ENGINEERING
const INSETS: Array = [0, 0, 0, 24]

var _vp: SubViewport


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _open(size: Vector2i, tablet: bool = false) -> StationScreen:
	if tablet:
		LayoutMode.forced = LayoutMode.Kind.TOUCH
	SafeArea.simulate([47, 0, 47, 21] if not tablet else INSETS)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("engineering", SETTINGS)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	if tablet:
		s.theme = LayoutMode.theme_for(LayoutMode.Kind.TOUCH)
	_vp.add_child(s)
	for i: int in 4:
		await get_tree().process_frame
	return s


func _panel(s: StationScreen) -> EngineeringPanel:
	return s.focused_panel() as EngineeringPanel


func _refresh(s: StationScreen) -> void:
	_panel(s).update_rails()
	await get_tree().process_frame


func test_buttons_on_the_picked_part_name_it() -> void:
	var s: StationScreen = await _open(Vector2i(844, 390))
	var e: EngineeringPanel = _panel(s)
	e.model.select(2)
	await _refresh(s)
	assert_str((e.touch_buttons["pip_add"] as RailButton).text).is_equal("Power +\nWPN")
	assert_str((e.touch_buttons["harden"] as RailButton).text).is_equal("Harden\nWPN")
	# Not on a part: the plain label.
	assert_str((e.touch_buttons["boost"] as RailButton).text).is_equal("Boost")
	e.model.select(0)
	await _refresh(s)
	assert_str((e.touch_buttons["pip_add"] as RailButton).text).is_equal("Power +\nENG")


func test_a_button_that_cannot_act_says_why() -> void:
	var s: StationScreen = await _open(Vector2i(844, 390))
	var e: EngineeringPanel = _panel(s)
	var blocks: Dictionary = s.ctx.view.blocks[ENG]
	# Engines have no fault: Cause is greyed with its reason.
	e.model.select(0)
	await _refresh(s)
	var cause: RailButton = e.touch_buttons["cause_next"]
	assert_bool(cause.disabled).is_true()
	assert_str(cause.text).is_equal("Cause\nno fault")
	blocks["subsystems"][0]["fault"] = true
	await _refresh(s)
	assert_bool(cause.disabled).is_false()
	# The reactor makes pips and takes none; an intact part needs no repair.
	e.model.select(5)
	await _refresh(s)
	assert_str(e.model.why_not("pip_add")).is_equal("reactor")
	assert_str((e.touch_buttons["pip_remove"] as RailButton).text).is_equal("Power -\nreactor")
	e.model.select(1)
	assert_str(e.model.why_not("dispatch_nearest")).is_equal("whole")
	# Reactor cap: 10 of 12 pips used, two more fit and then none.
	e.model.select(4)
	assert_str(e.model.why_not("pip_add")).is_empty()
	blocks["subsystems"][4]["pips"] = 3
	assert_str(e.model.why_not("pip_add")).is_equal("cap")
	# No spare parts: Harden, Repair and Probe say so.
	blocks["spare_parts"] = 0
	e.model.select(0)
	for id: String in ["harden", "dispatch_nearest", "fabricate_probe"]:
		var why: String = e.model.why_not(id)
		assert_str(why).override_failure_message(id).is_equal("no_parts")


# P9: one rule: an action the rail greys refuses with the toast of the same reason, and the
# reactor cap is a hint only (the server refuses it, D380).
func test_the_actions_refuse_with_the_rails_reason() -> void:
	var s: StationScreen = await _open(Vector2i(844, 390))
	var e: EngineeringPanel = _panel(s)
	var blocks: Dictionary = s.ctx.view.blocks[ENG]
	var toasts: Array[String] = []
	s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
	e.model.select(1)
	assert_str(e.model.why_not("dispatch_nearest")).is_equal("whole")
	assert_bool(e.model.dispatch_nearest()).is_false()
	blocks["subsystems"][1]["hardened"] = 40
	assert_str(e.model.why_not("harden")).is_equal("hardened")
	assert_bool(e.model.harden(1)).is_false()
	e.model.select(5)
	assert_bool(e.model.set_pips(5, 2)).is_false()
	assert_array(toasts).is_equal(["toast.eng_whole", "toast.eng_hardened", "toast.eng_reactor"])
	e.model.select(4)
	blocks["subsystems"][4]["pips"] = 3
	assert_str(e.model.why_not("pip_add")).is_equal("cap")
	assert_bool(e.model.set_pips(4, 4)).is_true()


func test_a_tablet_takes_the_rail_pattern() -> void:
	for size: Vector2i in [Vector2i(1180, 820), Vector2i(820, 1180)]:
		var s: StationScreen = await _open(size, true)
		var e: EngineeringPanel = _panel(s)
		assert_object(e.tablet_ui).override_failure_message(str(size)).is_not_null()
		assert_object(s.tablet_dock).is_same(e.tablet_ui.dock)
		assert_int(e.tablet_ui.buttons.size()).is_equal(10)
		assert_bool(e.tablet_ui.dock.portrait).is_equal(size.y > size.x)
		# A compact bottom bar in either orientation (w5): the panel keeps its height, and
		# every button sits inside the bar.
		assert_vector(e.tablet_ui.dock.reserve()).is_equal(Vector2(0.0, EngineeringTablet.BAR_H))
		var bar: Rect2 = e.tablet_ui.dock.left.get_global_rect()
		for b: RailButton in e.tablet_ui.buttons.values():
			(
				assert_bool(
					(
						b.get_global_rect().end.y <= bar.end.y + 0.5
						and b.get_global_rect().size.y > 0.0
					)
				)
				. override_failure_message("%s %s" % [size, b.name])
				. is_true()
			)
		# Every button sends its intent like the phone's rail does.
		await _refresh(s)
		var from: int = StationFixture.sent(s.ctx).sent.size()
		(e.tablet_ui.buttons["boost"] as RailButton).pressed.emit()
		assert_int(StationFixture.sent(s.ctx).sent.size()).is_greater(from)
		assert_bool(s.tablet_dock.is_inside_tree()).is_true()
		var report: Dictionary = TapAudit.check(s.tablet_dock)
		assert_array(StationFixture.rule_breaks(report, str(size))).is_empty()
		s.queue_free()
		await get_tree().process_frame


func test_a_desktop_has_no_rails() -> void:
	var s: StationScreen = await _open(Vector2i(1280, 720))
	assert_object(_panel(s).tablet_ui).is_null()
	assert_object(s.tablet_dock).is_null()
