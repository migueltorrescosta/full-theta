extends GdUnitTestSuite
## The lobby with many ships on a phone (#28 follow-up, strand T): the ship buttons share
## one row that scrolls sideways, so up to six ships in teams mode keep Start fully visible
## above the gesture band in every language and both orientations; a ship button scrolled
## out of the row is no tap target, and the role texts still wrap to two lines (D293).

const SIZES: Array = [
	[Vector2i(844, 390), [47, 0, 47, 21]],
	[Vector2i(390, 844), [0, 47, 0, 34]],
]
const NAMES: Array = [StationFixture.SHIP_NAME, "Heron", "Osprey", "Merlin", "Swift", "Ibis"]
const AUDIT_KEYS: Array[String] = ["under_min", "under_primary", "in_band", "outside_safe", "tight"]


func after() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	LayoutMode.apply(get_tree().root)


## The host's lobby of `ships` ships in teams mode, two stations still open (as the L5 shot).
func _lobby(ships: int) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context("systems")
	ctx.crew.host = true
	ctx.crew.lobby[0]["started"] = false
	ctx.crew.lobby[0]["ready"] = false
	ctx.crew.lobby[0]["crew"] = 2
	ctx.crew.lobby[0]["uncovered"] = ["relay", "comms"]
	ctx.crew.lobby[0]["seats"] = [
		{"entry": "helm", "name": "Ana"},
		{"entry": "weapons", "name": "Bo"},
		{"entry": "systems", "name": "Cy"},
	]
	var teams: Array = [0, 1, 0, 1, 0, 1].slice(0, ships)
	StationFixture.fleet(ctx, "teams", NAMES.slice(0, ships), teams)
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	# The suite's node sits outside the window's theme: give the lobby the phone's own.
	l.theme = LayoutMode.theme_for(LayoutMode.Kind.PHONE)
	l.setup(ctx)
	add_child(l)
	return l


func _settle(l: LobbyScreen, case: Array) -> void:
	var size: Vector2i = case[0]
	SafeArea.simulate(case[1])
	LayoutMode.apply(get_tree().root)
	get_tree().root.size = size
	l.size = Vector2(size)
	for i: int in 6:
		await get_tree().process_frame


# FT: FT-GEN-001, FT-NET-015, FT-STN-015
# Four and six ships in teams mode, every language, both orientations: Start whole above the
# band, the lobby no wider than the screen, TapAudit clean, the role texts at two lines.
func test_start_stays_visible_with_many_ships() -> void:
	var old: Vector2i = get_tree().root.size
	LayoutMode.forced = LayoutMode.Kind.PHONE
	var failures: PackedStringArray = []
	for lang: String in I18n.LANGUAGES:
		I18n.apply(lang)
		for ships: int in [4, 6]:
			for case: Array in SIZES:
				var l: LobbyScreen = _lobby(ships)
				await _settle(l, case)
				var at: String = "%s %d ships %s" % [lang, ships, case[0]]
				var start: Button = l.find_child("Start", true, false)
				var tap: Rect2 = SafeArea.tap_rect(l)
				if not start.is_visible_in_tree() or not tap.encloses(start.get_global_rect()):
					failures.append("%s: Start at %s" % [at, start.get_global_rect()])
				var layout: Control = l.find_child("Layout", true, false)
				if layout.get_global_rect().end.x > tap.end.x + 0.5:
					failures.append("%s: %s" % [at, _too_wide(layout, tap.end.x)])
				var report: Dictionary = TapAudit.check(l)
				for key: String in AUDIT_KEYS:
					if not (report[key] as Array).is_empty():
						failures.append("%s %s: %s" % [at, key, report[key]])
				for id: String in LobbyScreen.GRID_STATIONS:
					var role: Label = l.find_child("Entry_" + id, true, false).find_child(
						"Role", true, false
					)
					if role.get_line_count() > LobbyScreen.ROLE_LINES:
						failures.append("%s %s: %d lines" % [at, id, role.get_line_count()])
				l.queue_free()
	get_tree().root.size = old
	assert_array(failures).is_empty()


# FT: FT-GEN-001
# The ship row scrolls sideways: a ship scrolled out of view is no tap target, and choosing
# a ship scrolls its button into view.
func test_a_scrolled_away_ship_is_no_tap_target() -> void:
	var old: Vector2i = get_tree().root.size
	LayoutMode.forced = LayoutMode.Kind.PHONE
	var l: LobbyScreen = _lobby(6)
	await _settle(l, SIZES[1])
	var scroll: ScrollContainer = l.find_child("ShipScroll", true, false)
	assert_object(scroll).is_not_null()
	assert_bool(scroll.is_visible_in_tree()).is_true()
	var texts: Array = TapAudit.targets(l).map(func(t: Dictionary) -> String: return t["text"])
	var last: Button = l.find_child("Ship_5", true, false)
	assert_bool(last.is_visible_in_tree()).is_true()
	assert_bool(scroll.get_global_rect().intersects(last.get_global_rect())).is_false()
	assert_array(texts).not_contains([last.text])
	assert_array(texts).contains([(l.find_child("Ship_0", true, false) as Button).text])
	last.pressed.emit()
	for i: int in 4:
		await get_tree().process_frame
	assert_bool(scroll.get_global_rect().encloses(last.get_global_rect())).is_true()
	get_tree().root.size = old


## The widest rows under `root`, for a failure message.
func _too_wide(root: Control, right: float) -> String:
	var out: PackedStringArray = []
	for c: Node in root.find_children("*", "Control", true, false):
		var ctl: Control = c
		if ctl.is_visible_in_tree() and ctl.get_global_rect().end.x > right + 0.5:
			out.append("%s %.0f" % [ctl.name, ctl.get_combined_minimum_size().x])
	return ", ".join(out.slice(0, 12))
