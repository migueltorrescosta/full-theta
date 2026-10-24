extends GdUnitTestSuite
## The first visit to a station opens the controls overlay by itself (FT-STN-012, D185).

const CFG: String = "user://test_first_visit_help.cfg"


func before() -> void:
	I18n.apply("en")


func _screen(ctx: StationContext) -> StationScreen:
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	return s


func _fresh(entry: String) -> StationContext:
	var ctx: StationContext = StationFixture.context(entry, CFG)
	ctx.settings.reset_tooltips()
	return ctx


func _texts(s: StationScreen) -> Array[String]:
	var out: Array[String] = []
	for l: Node in s.overlay.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


# FT: FT-STN-012, FT-M1-019
func test_opens_once_per_client_and_station_headed_by_the_role() -> void:
	var ctx: StationContext = _fresh("helm")
	var s: StationScreen = _screen(ctx)
	assert_bool(s.overlay.visible).is_true()
	assert_bool(s.blocked()).is_true()
	assert_array(_texts(s)).contains([tr("role.helm")])
	assert_bool(ctx.settings.tooltip_seen("helm")).is_true()
	# Dismiss with the overlay key; the visit is recorded, so a new screen stays quiet.
	s.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	assert_bool(s.overlay.visible).is_false()
	assert_bool(_screen(ctx).overlay.visible).is_false()
	var saved: ClientSettings = ClientSettings.new(CFG)
	saved.load_file()
	assert_bool(saved.tooltip_seen("helm")).is_true()
	# Another station has its own first visit.
	assert_bool(_screen(_fresh("weapons")).overlay.visible).is_true()


# FT: FT-STN-012
func test_reset_tooltips_reenables_it() -> void:
	var ctx: StationContext = _fresh("helm")
	_screen(ctx)
	assert_bool(_screen(ctx).overlay.visible).is_false()
	ctx.settings.reset_tooltips()
	assert_bool(_screen(ctx).overlay.visible).is_true()


# FT: FT-STN-012, FT-JNT-001
func test_a_joint_view_opens_it_for_each_station_on_its_first_focus() -> void:
	var ctx: StationContext = _fresh("tactical")
	var s: StationScreen = _screen(ctx)
	assert_array(_texts(s)).contains([tr("role.tactical")])
	s.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	assert_bool(ctx.settings.tooltip_seen("weapons")).is_false()
	s.focus(1)
	assert_bool(s.overlay.visible).is_true()
	assert_bool(ctx.settings.tooltip_seen("weapons")).is_true()
	s.dispatch({"id": "overlay", "target": "screen", "pressed": true})
	s.focus(0)
	assert_bool(s.overlay.visible).is_false()
