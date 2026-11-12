extends GdUnitTestSuite
## C11 (R22-8, R26-6): the radar's two boxes say what they are, every station's Crew page
## holds its shares only (C4: Ping and Mark are on the selection sheet; ux-13: requests at
## the top of the view), and the radar legend shows once per client.

const SETTINGS: String = "user://test_radar_labels.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(seat: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(seat, SETTINGS)
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
	radar.size = Vector2(400, 400)
	assert_str(radar._range_text()).is_equal("Range 10 km")
	assert_str(SiteBanner.text({"label": "Kappa"})).is_equal("Zone: Kappa")


# FT: FT-STN-012, FT-PAIR-007
# Every station's Crew page holds its Share buttons and nothing else: no Ping, no Mark, no
# request chip.
func test_crew_pages_hold_the_shares_only() -> void:
	for seat: String in ["science", "comms", "relay", "engineering", "helm", "weapons"]:
		var s: StationScreen = await _screen(seat)
		var page: CrewPage = CrewPage.new(s.focused_panel())
		var kinds: Array = page.entries().map(func(e: Array) -> String: return str(e[0]))
		if seat in ["science", "relay"]:
			assert_array(kinds).override_failure_message(seat).is_not_empty()
		assert_array(kinds.filter(func(k: String) -> bool: return k != "share")).is_empty()
		page.free()


# FT: FT-STN-012, FT-STN-005, FT-PAIR-007
# The Crew page rebuilds its buttons only when what it shows changes (R20-12): a frame with
# nothing new keeps the same buttons and fits nothing again; a share's seconds left update
# the text in place.
func test_crew_page_refits_only_on_a_change() -> void:
	var s: StationScreen = await _screen("relay")
	var host: VBoxContainer = auto_free(VBoxContainer.new())
	host.size = Vector2(300, 300)
	add_child(host)
	var page: CrewPage = CrewPage.new(s.focused_panel())
	host.add_child(page)
	page.refresh()
	await get_tree().process_frame
	page.refresh()
	var first: RailButton = page.button("share")
	var fitted: Array = page._fitted
	page.refresh()
	assert_object(page.button("share")).is_same(first)
	assert_bool(page._fitted == fitted).is_true()
	var id: String = page.entries()[0][1]
	s.ctx.crew.shares[StringName(id)] = s.ctx.now_ms() + 12000
	page.refresh()
	assert_object(page.button("share")).is_same(first)
	assert_str(first.text).ends_with("· 12 s")


# FT: FT-STN-012
# The legend shows once, on the first visit of any station; the menu's "Show first-visit
# hints again" brings it back; a tap closes it.
func test_radar_legend_shows_once_and_a_tap_closes_it() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var settings: ClientSettings = ClientSettings.new(SETTINGS)
	var legend: ControlsHint = ControlsHint.show_radar_legend(host, settings)
	assert_object(legend).is_not_null()
	assert_str(legend.text).contains("Drift").contains("Zone").contains("mark")
	assert_object(ControlsHint.show_radar_legend(host, settings)).is_null()
	legend.pressed.emit()
	await get_tree().process_frame
	assert_bool(is_instance_valid(legend)).is_false()
	settings.reset_hints()
	assert_object(ControlsHint.show_radar_legend(host, settings)).is_not_null()
	# A parent that is not on screen shows nothing and keeps the legend for later.
	host.visible = false
	settings.reset_hints()
	assert_object(ControlsHint.show_radar_legend(host, settings)).is_null()
	assert_bool(settings.hint_seen(ControlsHint.RADAR_KEY)).is_false()


# FT: FT-STN-012
# w5: on a first visit the first-seat card and the radar legend stack top down, one under
# the other, for Science, Relay and Comms.
func test_first_visit_chips_stack_without_overlap() -> void:
	for seat: String in ["science", "relay", "comms"]:
		var ctx: StationContext = StationFixture.context(seat, SETTINGS)
		ctx.settings.reset_hints()
		var s: StationScreen = auto_free(StationScreen.new())
		s.setup(ctx)
		add_child(s)
		s.set_anchors_preset(Control.PRESET_TOP_LEFT)
		s.size = Vector2(1280, 720)
		for i: int in 4:
			await get_tree().process_frame
		var chips: Array[Control] = []
		for n: String in ["FirstSeatCard", "RadarLegend"]:
			var c: Control = s.find_child(n, true, false)
			assert_object(c).override_failure_message("%s %s" % [seat, n]).is_not_null()
			chips.append(c)
		for i: int in 1:
			var upper: Rect2 = chips[i].get_global_rect()
			var lower: Rect2 = chips[i + 1].get_global_rect()
			(
				assert_float(lower.position.y)
				. override_failure_message(
					"%s: %s under %s" % [seat, chips[i + 1].name, chips[i].name]
				)
				. is_greater_equal(upper.end.y)
			)
		s.queue_free()
		await get_tree().process_frame
		if FileAccess.file_exists(SETTINGS):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
