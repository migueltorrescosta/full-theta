extends GdUnitTestSuite
## The first visit to a station asks for the menu's Controls tab (FT-STN-012, D185); the
## shell's tests cover the menu opening itself.

const CFG: String = "user://test_first_visit_help.cfg"


func before() -> void:
	I18n.apply("en")


## A screen in the tree; `asked` counts its requests for the Controls tab.
func _screen(ctx: StationContext, asked: Array[bool]) -> StationScreen:
	var s: StationScreen = auto_free(StationScreen.new())
	s.help_requested.connect(func() -> void: asked.append(true))
	s.setup(ctx)
	add_child(s)
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
