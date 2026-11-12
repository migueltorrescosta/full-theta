extends GdUnitTestSuite
## The lobby's role summaries on phones (P28-Lobby, #28): each wraps to at most two lines in
## both orientations, in every launch language, and the whole
## lobby (Start included) stays inside the safe area above the gesture band.

const SIZES: Array = [
	[Vector2i(844, 390), [47, 0, 47, 21]],
	[Vector2i(390, 844), [0, 47, 0, 34]],
]


func after() -> void:
	I18n.apply("en")


func _lobby() -> LobbyScreen:
	var ctx: StationContext = StationFixture.context("helm")
	ctx.crew.lobby[0]["started"] = false
	StationFixture.fleet(ctx, "teams", [StationFixture.SHIP_NAME, "Heron", "Osprey"], [0, 1, 1])
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	# The suite's node sits outside the window's theme: give the lobby the phone's own.
	l.theme = LayoutMode.theme_for(LayoutMode.Kind.PHONE)
	l.setup(ctx)
	add_child(l)
	return l


# FT: FT-STN-015, FT-NET-015
func test_role_summaries_fit_their_lines_and_start_stays_on_screen() -> void:
	var old: Vector2i = get_tree().root.size
	LayoutMode.forced = LayoutMode.Kind.PHONE
	var failures: PackedStringArray = []
	for lang: String in I18n.LANGUAGES:
		I18n.apply(lang)
		for case: Array in SIZES:
			var size: Vector2i = case[0]
			SafeArea.simulate(case[1])
			LayoutMode.apply(get_tree().root)
			get_tree().root.size = size
			var l: LobbyScreen = _lobby()
			l.size = Vector2(size)
			for i: int in 6:
				await get_tree().process_frame
			var lines: int = LobbySeatGrid.ROLE_LINES
			for id: String in LobbySeatGrid.GRID_STATIONS:
				var cell: Node = l.find_child("Seat_" + id, true, false)
				var role: Label = cell.find_child("Role", true, false) as Label
				if role.max_lines_visible != lines or role.get_line_count() > lines:
					failures.append("%s %s %s: %d lines" % [lang, size, id, role.get_line_count()])
			var report: Dictionary = TapAudit.check(l)
			for key: String in ["under_min", "under_primary", "in_band", "outside_safe", "tight"]:
				if not (report[key] as Array).is_empty():
					failures.append("%s %s %s: %s" % [lang, size, key, report[key]])
			l.queue_free()
	SafeArea.simulate([])
	LayoutMode.forced = -1
	get_tree().root.size = old
	LayoutMode.apply(get_tree().root)
	assert_array(failures).is_empty()


# FT: FT-STN-013
# T3: on a short screen (853 x 480 at 150 %) the role description wraps instead of being cut.
func test_the_summary_role_wraps_on_a_short_desktop_screen() -> void:
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	var l: LobbyScreen = _lobby()
	l._arrange(true)
	var role: Label = l.find_child("SummaryRole", true, false) as Label
	assert_bool(role.clip_text).is_false()
	assert_int(role.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_int(role.max_lines_visible).is_equal(LobbySeatGrid.ROLE_LINES)
	LayoutMode.forced = -1
