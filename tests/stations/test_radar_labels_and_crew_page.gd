extends GdUnitTestSuite
## C11 (R22-8, R22-10, R26-6): the radar's two boxes say what they are, every station's Crew
## page starts with Ping and Mark, and the radar legend shows once per client.

const SETTINGS: String = "user://test_radar_labels.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(entry: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


# FT: FT-SPA-027
func test_radar_boxes_are_labelled() -> void:
	var radar: DiscRadar = auto_free(DiscRadar.new())
	assert_str(radar._range_text()).is_equal("Range 10 km")
	assert_str(SiteBanner.text({"label": "Kappa"})).is_equal("Zone: Kappa")


# FT: FT-STN-012
# Ping and Mark are the first two buttons of every station's Crew page; a station's own
# requests follow them.
func test_crew_pages_start_with_ping_and_mark() -> void:
	for entry: String in ["science", "comms", "relay"]:
		var s: StationScreen = await _screen(entry)
		var page: CrewPage = CrewPage.new(s.focused_panel())
		var kinds: Array = page.entries().map(func(e: Array) -> String: return str(e[0]))
		assert_array(kinds.slice(0, 2)).override_failure_message(entry).is_equal(["ping", "mark"])
		page.free()


# FT: FT-STN-012
# The legend shows once, on the first visit of any station; the menu's "Show first-visit
# hints again" brings it back; a tap closes it.
func test_radar_legend_shows_once_and_a_tap_closes_it() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var settings: ClientSettings = ClientSettings.new(SETTINGS)
	var legend: RadarLegend = RadarLegend.show_once(host, settings)
	assert_object(legend).is_not_null()
	assert_str(legend.text).contains("Drift").contains("Zone").contains("mark")
	assert_object(RadarLegend.show_once(host, settings)).is_null()
	legend.pressed.emit()
	await get_tree().process_frame
	assert_bool(is_instance_valid(legend)).is_false()
	settings.reset_hints()
	assert_object(RadarLegend.show_once(host, settings)).is_not_null()
	# A parent that is not on screen shows nothing and keeps the legend for later.
	host.visible = false
	settings.reset_hints()
	assert_object(RadarLegend.show_once(host, settings)).is_null()
	assert_bool(settings.hint_seen(RadarLegend.KEY)).is_false()
