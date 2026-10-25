extends GdUnitTestSuite
## LobbyScreen, PauseOverlay and PlaceholderPanel.


func before() -> void:
	I18n.apply("en")


func _lobby(entry: String) -> LobbyScreen:
	var ctx: StationContext = StationFixture.context(entry)
	ctx.crew.lobby[0]["started"] = false
	var l: LobbyScreen = auto_free(LobbyScreen.new())
	l.setup(ctx)
	add_child(l)
	return l


func _cell(l: LobbyScreen, id: String) -> Button:
	return l.find_child("Entry_" + id, true, false)


func _picked(l: LobbyScreen, entry: String) -> void:
	l.ctx.crew.handle_event({"type": "picked", "payload": {"ship": 0, "entry": entry}}, 0)


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
		ids.append(c.name.trim_prefix("Entry_"))
	assert_array(ids).is_equal(LobbyScreen.GRID_STATIONS)
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
		assert_str((cell.find_child("Role", true, false) as Label).text).is_equal(tr("role." + id))
		assert_int((cell.find_child("Name", true, false) as Label).horizontal_alignment).is_equal(
			HORIZONTAL_ALIGNMENT_CENTER
		)
	assert_bool(_cell(l, "captain") is Button).is_true()
	assert_bool(_cell(l, "viewer").button_pressed).is_true()


# FT: FT-STN-015
func test_legend_names_each_load_in_its_colour_and_follows_the_language() -> void:
	var l: LobbyScreen = _lobby("helm")
	var legend: Control = l.find_child("Legend", true, false)
	for tag: String in ["intense", "busy", "light"]:
		var item: Label = legend.get_node("Legend_" + tag)
		assert_str(item.text).is_equal(tr("lobby.legend_" + tag))
		assert_object(item.get_theme_color("font_color")).is_equal(Palette.color("load_" + tag))
	assert_str((legend.get_node("Legend_intense") as Label).text).is_equal("Red: intense")
	I18n.apply("pt_PT")
	assert_str((legend.get_node("Legend_light") as Label).text).is_equal("Verde: leve")
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


# FT: FT-NET-032
# Every pair of stations maps to its joint view entry.
func test_every_pair_maps_to_its_joint_view() -> void:
	var l: LobbyScreen = _lobby("viewer")
	var seen: Dictionary = {}
	for a: String in LobbyScreen.GRID_STATIONS:
		for b: String in LobbyScreen.GRID_STATIONS:
			if a < b:
				var entry: String = l.entry_for([a, b] as Array[String])
				assert_str(entry).is_not_empty()
				assert_bool(seen.has(entry)).is_false()
				seen[entry] = true
				assert_array(StationViews.stations_of(entry)).contains_exactly_in_any_order([a, b])
	assert_int(seen.size()).is_equal(15)


# FT: FT-NET-015
# A cell lists the crewmates who picked it, a joint view's crew under both stations.
func test_cells_name_the_crewmates_from_the_seats() -> void:
	var l: LobbyScreen = _lobby("viewer")
	l.ctx.crew.lobby[0]["seats"] = [
		{"name": "Ana", "entry": "tactical"},
		{"name": "Bo", "entry": "helm"},
		{"name": "Cy", "entry": "captain"},
	]
	l.refresh()
	assert_str((_cell(l, "helm").find_child("Crew", true, false) as Label).text).is_equal("Ana, Bo")
	assert_str((_cell(l, "weapons").find_child("Crew", true, false) as Label).text).is_equal("Ana")
	assert_object(_cell(l, "science").find_child("Crew", true, false)).is_null()


# FT: FT-NET-017
# The dev seat exists only when the server offers it (--dev-all-stations): picking it
# shows all six cells selected; a tap on a cell, Captain or Viewer leaves it.
func test_dev_all_stations_seat_only_with_the_flag() -> void:
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
	for id: String in LobbyScreen.GRID_STATIONS:
		assert_bool(_cell(l, id).button_pressed).is_true()
		assert_bool(_cell(l, id).disabled).is_false()
	_cell(l, "science").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "science"])
	_picked(l, "science")
	assert_bool(_cell(l, "helm").button_pressed).is_false()
	_picked(l, "all")
	_cell(l, "viewer").pressed.emit()
	assert_array(_sent_picks(l)[-1][1]).is_equal([0, "viewer"])


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
		ctx.crew.lobby[0]["seats"] = [{"name": "Ana", "entry": "helm"}]
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
func test_start_is_for_crew_of_a_covered_ship() -> void:
	var l: LobbyScreen = _lobby("ops")
	var start: Button = l.find_child("Start", true, false)
	assert_bool(start.disabled).is_false()
	start.pressed.emit()
	assert_array(StationFixture.sent(l.ctx).of("set_ready")[0][1]).is_equal([true])
	l.ctx.crew.lobby[0]["ready"] = false
	l.ctx.crew.lobby[0]["uncovered"] = ["comms"]
	l.refresh()
	assert_bool(start.disabled).is_true()
	assert_str((l.find_child("Coverage", true, false) as Label).text).contains("Comms")
	assert_bool((_lobby("viewer").find_child("Start", true, false) as Button).disabled).is_true()


# FT: FT-NET-041
func test_pause_overlay_vote_and_host_abandon() -> void:
	var ctx: StationContext = StationFixture.context("tactical")
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	assert_bool(o.visible).is_false()
	ctx.crew.host = true
	var pause: Dictionary = {"ship": 0, "uncovered": ["relay"], "crew": 2, "min_crew": 3}
	ctx.crew.handle_event({"type": "pause", "payload": pause}, 0)
	assert_bool(o.visible).is_true()
	# Crew changes it doesn't show leave its buttons alone.
	var vote: Button = o.find_child("Vote", true, false)
	ctx.crew.changed.emit(&"alert")
	ctx.crew.changed.emit(&"marks")
	assert_object(o.find_child("Vote", true, false)).is_same(vote)
	vote.pressed.emit()
	(o.find_child("Abandon", true, false) as Button).pressed.emit()
	var rec: StationFixture.RecordingClient = StationFixture.sent(ctx)
	assert_array(rec.of("vote_abandon")[0][1]).is_equal([0, true])
	assert_array(rec.of("abandon")[0][1]).is_equal([0])
	var votes: Dictionary = {
		"ship": 0, "voters": ["Ana"], "sessions": [StationFixture.SESSION], "needed": 2
	}
	ctx.crew.handle_event({"type": "abandon_votes", "payload": votes}, 0)
	(o.find_child("Vote", true, false) as Button).pressed.emit()
	assert_array(rec.of("vote_abandon")[1][1]).is_equal([0, false])
	assert_str((o.find_child("Votes", true, false) as Label).text).contains("1/2")


# FT: FT-NET-042
func test_viewers_of_a_paused_ship_may_take_over() -> void:
	var ctx: StationContext = StationFixture.context("viewer")
	var o: PauseOverlay = auto_free(PauseOverlay.new())
	o.setup(ctx)
	add_child(o)
	var pause: Dictionary = {"ship": 0, "uncovered": ["relay"], "crew": 2, "min_crew": 3}
	ctx.crew.handle_event({"type": "pause", "payload": pause}, 0)
	assert_object(o.find_child("Vote", true, false)).is_null()
	(o.find_child("Takeover_relay", true, false) as Button).pressed.emit()
	assert_array(StationFixture.sent(ctx).of("takeover")[0][1]).is_equal([0, "relay"])


# FT: FT-M1-005
func test_placeholder_reads_out_its_station_def() -> void:
	var ctx: StationContext = StationFixture.context("comms")
	var p: PlaceholderPanel = auto_free(StationRegistry.make("comms") as PlaceholderPanel)
	assert_object(p).is_not_null()
	p.setup(ctx, "comms")
	add_child(p)
	var text: String = (p.get_child(0).get_child(1) as Label).text
	assert_str(text).contains("kin").contains("status").contains("contacts")
	assert_str((p.get_child(0).get_child(0) as Label).text).is_equal("Comms")
