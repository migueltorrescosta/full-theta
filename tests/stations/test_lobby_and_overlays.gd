extends GdUnitTestSuite
## LobbyScreen (the pause overlay is in test_pause_overlay.gd).


func before() -> void:
	I18n.apply("en")


func _lobby(seat: String) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context(seat)
	ctx.crew.lobby[0]["started"] = false
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	return l


func _cell(l: LobbyScreen, id: String) -> Button:
	return l.find_child("Seat_" + id, true, false)


func _picked(l: LobbyScreen, seat: String) -> void:
	l.ctx.crew.handle_event({"type": "picked", "payload": {"ship": 0, "seat": seat}}, 0)


func _sent_picks(l: LobbyScreen) -> Array:
	return StationFixture.sent(l.ctx).of("pick")


# FT: FT-STN-015, FT-NET-015
# The grid holds the six stations in order with name and role centred, each bordered in its
# load colour (a theme variation of the palette's load roles), Captain and Viewer below.
func test_grid_cells_show_name_role_and_load_border() -> void:
	var l: LobbyScreen = _lobby("viewer")
	var grid: GridContainer = l.find_child("Grid", true, false)
	var ids: Array[String] = []
	for c: Node in grid.get_children():
		ids.append(c.name.trim_prefix("Seat_"))
	assert_array(ids).is_equal(LobbySeatGrid.GRID_STATIONS)
	var tags: Dictionary = {
		"helm": "intense",
		"weapons": "intense",
		"engineering": "busy",
		"science": "busy",
		"relay": "light",
		"comms": "light",
	}
	var theme: Theme = UiTheme.build()
	for id: String in tags:
		var cell: Button = _cell(l, id)
		assert_str(cell.theme_type_variation).is_equal("LoadCell_" + tags[id])
		var style: StyleBoxFlat = theme.get_stylebox("normal", cell.theme_type_variation)
		assert_object(style.border_color).is_equal(Palette.color("load_" + tags[id]))
		assert_str((cell.find_child("Name", true, false) as Label).text).is_equal(
			tr("station." + id)
		)
		# The whole role summary, wrapped to two lines (P28-Lobby).
		var role: Label = cell.find_child("Role", true, false) as Label
		assert_str(role.text).is_equal(tr("role." + id))
		assert_int(role.max_lines_visible).is_equal(LobbySeatGrid.ROLE_LINES)
		assert_bool(cell.find_child("Take", true, false) == null).is_true()
	assert_bool(_cell(l, "captain") is Button).is_true()
	assert_bool(_cell(l, "viewer").button_pressed).is_true()


# FT: FT-NET-015, FT-STN-015
# D257: tapping a cell takes the seat and tapping it again leaves it, with no Take button;
# a cell is at least 44 px tall; the holder's name uses a colour that keeps 4.5:1 on the
# cell's fills.
func test_cell_tap_takes_and_leaves_a_seat_in_a_compact_cell() -> void:
	var l: LobbyScreen = _lobby("viewer")
	l.ctx.crew.lobby[0]["seats"] = [{"seat": "relay", "name": "Ana"}]
	l.refresh()
	var cell: Button = _cell(l, "science")
	await get_tree().process_frame
	assert_float(cell.custom_minimum_size.y).is_greater_equal(float(UiTheme.TOUCH_MIN))
	# Compact: the name and two lines of role text (16 px text here, outside the theme).
	assert_float(cell.custom_minimum_size.y).is_less_equal(80.0)
	assert_str((_cell(l, "relay").find_child("Crew", true, false) as Label).text).is_equal("Ana")
	cell.pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "science"])
	_picked(l, "science")
	assert_bool(cell.button_pressed).is_true()
	cell.pressed.emit()
	assert_int(StationFixture.sent(l.ctx).of("release_pick").size()).is_equal(1)
	_picked(l, "")
	assert_bool(cell.button_pressed).is_false()
	var crew_colour: Color = UiTheme.build().get_color("font_color", "CrewLabel")
	for fill: String in ["panel", "panel_focus", "background"]:
		assert_float(_contrast(crew_colour, Palette.color(fill))).is_greater_equal(4.5)


static func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var lin: Array[float] = []
	for v: float in [c.r, c.g, c.b]:
		lin.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


# FT: FT-STN-015
# #37 C9 (reverses D316's colour-only legend): each cell names its load as a word in its
# load colour, in the session's language; there is no legend row.
func test_each_cell_names_its_load_in_its_colour_and_follows_the_language() -> void:
	var l: LobbyScreen = _lobby("helm")
	assert_object(l.find_child("Legend", true, false)).is_null()
	for id: String in LobbySeatGrid.GRID_STATIONS:
		var tag: String = str(l.ctx.crew.def_of(id).get("load_tag", ""))
		var word: Label = _cell(l, id).find_child("Load", true, false)
		assert_str(word.text).override_failure_message(id).is_equal(tr("lobby.load_" + tag))
		assert_object(word.get_theme_color("font_color")).is_equal(Palette.color("load_" + tag))
	I18n.apply("pt_PT")
	var l2: LobbyScreen = _lobby("helm")
	var tag2: String = str(l2.ctx.crew.def_of("helm").get("load_tag", ""))
	var helm: Label = _cell(l2, "helm").find_child("Load", true, false)
	assert_str(helm.text).is_equal(TranslationServer.translate("lobby.load_" + tag2))
	assert_str(helm.text).is_not_equal("lobby.load_" + tag2)
	I18n.apply("en")


# FT: FT-NET-015, FT-NET-032, FT-JNT-006
# Each tap picks at once: one station, then the joint view of the pair; a third is
# refused and the other cells grey out; tapping a picked cell drops it; the last one
# released; Captain and Viewer replace station picks.
func test_taps_multi_select_up_to_two_and_pick_the_joint_view() -> void:
	var l: LobbyScreen = _lobby("viewer")
	_cell(l, "helm").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "helm"])
	_picked(l, "helm")
	assert_bool(_cell(l, "helm").button_pressed).is_true()
	assert_bool(_cell(l, "relay").disabled).is_false()
	_cell(l, "weapons").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "tactical"])
	_picked(l, "tactical")
	for id: String in ["engineering", "science", "relay", "comms"]:
		assert_bool(_cell(l, id).disabled).is_true()
		assert_bool(_cell(l, id).button_pressed).is_false()
	assert_bool(_cell(l, "helm").disabled).is_false()
	var picks: int = _sent_picks(l).size()
	_cell(l, "relay").pressed.emit()
	assert_int(_sent_picks(l).size()).is_equal(picks)
	assert_str((l.find_child("SummaryName", true, false) as Label).text).is_equal(
		"Tactical (Helm + Weapons)"
	)
	assert_str((l.find_child("SummaryRole", true, false) as Label).text).is_equal(
		tr("role.tactical")
	)
	_cell(l, "helm").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "weapons"])
	_picked(l, "weapons")
	assert_bool(_cell(l, "relay").disabled).is_false()
	_cell(l, "weapons").pressed.emit()
	assert_int(StationFixture.sent(l.ctx).of("release_pick").size()).is_equal(1)
	_picked(l, "")
	_cell(l, "captain").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "captain"])
	_picked(l, "captain")
	assert_bool(_cell(l, "weapons").button_pressed).is_false()
	assert_bool(_cell(l, "captain").button_pressed).is_true()
	_cell(l, "helm").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "helm"])
	assert_str((l.find_child("SummaryName", true, false) as Label).text).is_equal("Captain")


# FT: FT-NET-015, FT-NET-032
# A second tap before the server answered the first still makes the pair.
func test_a_quick_second_tap_adds_to_the_first() -> void:
	var l: LobbyScreen = _lobby("viewer")
	_cell(l, "science").pressed.emit()
	_cell(l, "relay").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "sensors"])
	# A refusal puts the screen back to what the server holds.
	l.ctx.crew.toast.emit("toast.captain_taken", {})
	assert_bool(_cell(l, "science").button_pressed).is_false()
	assert_bool(_cell(l, "viewer").button_pressed).is_true()


# FT: FT-NET-032
# Every pair of stations maps to its joint view seat.
func test_every_pair_maps_to_its_joint_view() -> void:
	var l: LobbyScreen = _lobby("viewer")
	var seen: Dictionary = {}
	for a: String in LobbySeatGrid.GRID_STATIONS:
		for b: String in LobbySeatGrid.GRID_STATIONS:
			if a < b:
				var seat: String = l.seat_for([a, b] as Array[String])
				assert_str(seat).is_not_empty()
				assert_bool(seen.has(seat)).is_false()
				seen[seat] = true
				assert_array(StationCatalogue.stations_of(seat)).contains_exactly_in_any_order(
					[a, b]
				)
	assert_int(seen.size()).is_equal(15)


# FT: FT-NET-015
# A cell lists the crewmates who picked it, a joint view's crew under both stations.
func test_cells_name_the_crewmates_from_the_seats() -> void:
	var l: LobbyScreen = _lobby("viewer")
	l.ctx.crew.lobby[0]["seats"] = [
		{"name": "Ana", "seat": "tactical"},
		{"name": "Bo", "seat": "helm"},
		{"name": "Cy", "seat": "captain"},
	]
	l.refresh()
	assert_str((_cell(l, "helm").find_child("Crew", true, false) as Label).text).is_equal("Ana, Bo")
	assert_str((_cell(l, "weapons").find_child("Crew", true, false) as Label).text).is_equal("Ana")
	assert_str((_cell(l, "science").find_child("Crew", true, false) as Label).text).is_empty()


# FT: FT-NET-017
# The dev seat exists only when the server offers it (--dev-all-stations) and this game was
# started with --dev (#35 A7): picking it shows all six cells selected; a tap on a cell,
# Captain or Viewer leaves it.
func test_dev_all_stations_seat_only_with_the_flag() -> void:
	assert_bool(_cell(_lobby("viewer"), "all").visible).is_false()
	ClientSettings.dev_flag = true
	var l: LobbyScreen = _lobby("viewer")
	assert_bool(_cell(l, "all").visible).is_true()
	var plain: StationContext = StationFixture.context("viewer")
	plain.crew.set_catalogue(StationFixture.catalogue(false))
	var l2: LobbyScreen = auto_free(LobbyScreen.new())
	l2.setup(plain)
	add_child(l2)
	assert_bool(_cell(l2, "all").visible).is_false()
	_cell(l, "all").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "all"])
	_picked(l, "all")
	for id: String in LobbySeatGrid.GRID_STATIONS:
		assert_bool(_cell(l, id).button_pressed).is_true()
		assert_bool(_cell(l, id).disabled).is_false()
	_cell(l, "science").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "science"])
	_picked(l, "science")
	assert_bool(_cell(l, "helm").button_pressed).is_false()
	_picked(l, "all")
	_cell(l, "viewer").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "viewer"])
	ClientSettings.dev_flag = false


# FT: FT-STN-013, FT-NET-015
# Landscape sizes use 3 columns, portrait 2, and the whole lobby fits the screen with no
# scrolling at the four reference sizes.
func test_grid_fits_every_reference_size_without_scrolling() -> void:
	for size: Vector2 in [
		Vector2(1920, 1080), Vector2(1024, 768), Vector2(768, 1024), Vector2(390, 844)
	]:
		var holder: Control = auto_free(Control.new())
		holder.size = size
		holder.theme = UiTheme.build()
		add_child(holder)
		var ctx: StationContext = StationFixture.context("viewer")
		ctx.crew.lobby[0]["started"] = false
		ctx.crew.lobby[0]["seats"] = [{"name": "Ana", "seat": "helm"}]
		var l: LobbyScreen = auto_free(LobbyScreen.new())
		l.setup(ctx)
		holder.add_child(l)
		l.size = size
		for i: int in 10:
			await get_tree().process_frame
		assert_int((l.find_child("Grid", true, false) as GridContainer).columns).is_equal(
			3 if size.x >= size.y else 2
		)
		var need: Vector2 = (
			(l.find_child("Layout", true, false) as Control).get_combined_minimum_size()
		)
		(
			assert_bool(need.y + 24.0 <= size.y and need.x + 24.0 <= size.x)
			. override_failure_message("%s needs %s" % [size, need])
			. is_true()
		)
		assert_object(l.find_child("Scroll", true, false)).is_null()


# FT: FT-STN-013
# The theme gives every touch variation a target of at least 44 px at 100 %.
func test_touch_variations_are_at_least_44_px() -> void:
	var holder: Control = auto_free(Control.new())
	holder.theme = UiTheme.build()
	add_child(holder)
	var controls: Array[Control] = [Button.new(), OptionButton.new(), CheckBox.new()]
	var variations: Array[String] = ["TouchButton", "TouchOptionButton", "TouchCheckBox"]
	for i: int in controls.size():
		if controls[i] is OptionButton:
			(controls[i] as OptionButton).add_item("Ag")
		else:
			(controls[i] as Button).text = "Ag"
		controls[i].theme_type_variation = variations[i]
		holder.add_child(controls[i])
		(
			assert_float(controls[i].get_combined_minimum_size().y)
			. override_failure_message(variations[i])
			. is_greater_equal(float(UiTheme.TOUCH_MIN))
		)


# FT: FT-NET-019
# #37 C1: a crew player gets Ready, never Start, while the host is here; the host's Start
# lights on a covered ship and greys with what it waits for; a viewer has neither.
func test_ready_for_crew_and_start_for_the_host() -> void:
	var l: LobbyScreen = _lobby("ops")
	assert_bool((l.find_child("Ready", true, false) as Button).visible).is_true()
	assert_bool((l.find_child("Start", true, false) as Button).visible).is_false()
	var host: LobbyScreen = _lobby("ops")
	host.ctx.crew.host = true
	host.refresh()
	var start: Button = host.find_child("Start", true, false)
	assert_bool((host.find_child("Ready", true, false) as Button).visible).is_false()
	assert_bool(start.disabled).is_false()
	start.pressed.emit()
	assert_array(StationFixture.sent(host.ctx).of("start")).is_equal([["start", []]])
	host.ctx.crew.lobby[0]["covered"] = false
	host.ctx.crew.lobby[0]["uncovered"] = ["comms"]
	host.refresh()
	assert_bool(start.disabled).is_true()
	assert_str(start.text).is_equal("Need Comms")
	assert_str((host.find_child("Coverage", true, false) as Label).text).contains("Comms")
	var viewer: LobbyScreen = _lobby("viewer")
	assert_bool((viewer.find_child("Ready", true, false) as Button).visible).is_false()
	assert_bool((viewer.find_child("Start", true, false) as Button).visible).is_false()


# FT: FT-NET-015
# A refresh updates the grid in place: the cell nodes survive a crew change, so a tap
# that lands around the `lobby` event still arrives (a rebuild eats the click).
func test_refresh_keeps_the_cell_buttons() -> void:
	var l: LobbyScreen = _lobby("viewer")
	var helm: Button = _cell(l, "helm")
	var ship_button: Button = l._ships.get_child(0)
	l.ctx.crew.lobby[0]["seats"] = [{"name": "Ana", "seat": "helm"}]
	l.refresh()
	assert_object(_cell(l, "helm")).is_same(helm)
	assert_object(l._ships.get_child(0)).is_same(ship_button)
	assert_str((helm.find_child("Crew", true, false) as Label).text).is_equal("Ana")
	l.ctx.crew.lobby[0]["seats"] = []
	l.refresh()
	assert_str((helm.find_child("Crew", true, false) as Label).text).is_empty()
	helm.pressed.emit()
	assert_array(_sent_picks(l)).is_not_empty()
