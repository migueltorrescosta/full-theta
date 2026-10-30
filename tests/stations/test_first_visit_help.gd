extends GdUnitTestSuite
## The first visit to a station shows the Controls chip (FT-STN-012, P28-Help), never the
## menu; tapping the chip asks for the menu's Controls tab.

const CFG: String = "user://test_first_visit_help.cfg"


func before() -> void:
	I18n.apply("en")


## A screen in the tree; `asked` counts the chips it showed, and tapping each asks for help.
func _screen(ctx: StationContext, asked: Array[bool]) -> StationScreen:
	var s: StationScreen = auto_free(StationScreen.new())
	var helped: Array[bool] = []
	s.help_requested.connect(func() -> void: helped.append(true))
	s.child_entered_tree.connect(
		func(n: Node) -> void:
			if n is ControlsChip:
				asked.append(true)
	)
	s.setup(ctx)
	add_child(s)
	# Help never opens by itself.
	assert_array(helped).is_empty()
	var chip: ControlsChip = s.find_child("ControlsChip", true, false) as ControlsChip
	if chip != null:
		chip.pressed.emit()
		assert_array(helped).has_size(1)
	return s


func _fresh(entry: String) -> StationContext:
	var ctx: StationContext = StationFixture.context(entry, CFG)
	ctx.settings.reset_tooltips()
	return ctx


# FT: FT-STN-012, FT-M1-019
func test_asks_once_per_client_and_station() -> void:
	var ctx: StationContext = _fresh("helm")
	var asked: Array[bool] = []
	_screen(ctx, asked)
	assert_array(asked).has_size(1)
	assert_bool(ctx.settings.tooltip_seen("helm")).is_true()
	# The visit is recorded, so a new screen stays quiet.
	_screen(ctx, asked)
	assert_array(asked).has_size(1)
	var saved: ClientSettings = ClientSettings.new(CFG)
	saved.load_file()
	assert_bool(saved.tooltip_seen("helm")).is_true()
	# Another station has its own first visit.
	_screen(_fresh("weapons"), asked)
	assert_array(asked).has_size(2)


# FT: FT-STN-012
func test_reset_tooltips_reenables_it() -> void:
	var ctx: StationContext = _fresh("helm")
	var asked: Array[bool] = []
	_screen(ctx, asked)
	_screen(ctx, asked)
	assert_array(asked).has_size(1)
	ctx.settings.reset_tooltips()
	_screen(ctx, asked)
	assert_array(asked).has_size(2)


# FT: FT-STN-012, FT-JNT-001
func test_a_joint_view_asks_for_each_station_on_its_first_focus() -> void:
	var ctx: StationContext = _fresh("tactical")
	var asked: Array[bool] = []
	var s: StationScreen = _screen(ctx, asked)
	assert_array(asked).has_size(1)
	assert_bool(ctx.settings.tooltip_seen("weapons")).is_false()
	s.focus(1)
	assert_array(asked).has_size(2)
	assert_bool(ctx.settings.tooltip_seen("weapons")).is_true()
	s.focus(0)
	assert_array(asked).has_size(2)


# FT: FT-STN-012, FT-TST-021
# The browser test hooks (?pick=) switch the first-visit chip off, so it never covers the
# station the test photographs.
func test_browser_test_hooks_skip_the_first_visit_chip() -> void:
	var ctx: StationContext = _fresh("helm")
	ctx.settings.skip_first_visit_help = true
	var asked: Array[bool] = []
	_screen(ctx, asked)
	assert_array(asked).is_empty()
