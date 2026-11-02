extends GdUnitTestSuite
## The in-game menu (FT-STN-011, P28 menu): Game, Controls (with Change keys) and Settings
## tabs; the Pause and Abandon controls change in place, never rebuilding the menu (load
## fix 2); Leave and the host's Abandon or Give up ask to confirm in place; a phone has no
## Change keys.

const CFG: String = "user://test_settings_menu.cfg"


func before() -> void:
	I18n.apply("en")


func after() -> void:
	LayoutMode.forced = -1


func _menu(in_session: bool = true) -> SettingsScreen:
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	var m: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(m)
	m.setup(ClientSettings.new(CFG), in_session)
	return m


func _tab_names(m: SettingsScreen) -> Array[String]:
	var out: Array[String] = []
	for c: Node in m.tabs.get_children():
		out.append(String(c.name))
	return out


func _button(m: SettingsScreen, node_name: String) -> Button:
	return m.find_child(node_name, true, false) as Button


# FT: FT-STN-011
func test_a_session_menu_has_the_game_tab_first() -> void:
	var m: SettingsScreen = _menu()
	assert_array(_tab_names(m)).is_equal(
		[SettingsScreen.TAB_GAME, SettingsScreen.TAB_CONTROLS, SettingsScreen.TAB_SETTINGS]
	)
	assert_str(m.current_tab_name()).is_equal(SettingsScreen.TAB_GAME)
	var game: Node = m.tabs.get_node(SettingsScreen.TAB_GAME)
	for n: String in ["ShipName", "Sound", "Fullscreen", "HostPause", "Abandon", "Leave"]:
		assert_object(game.find_child(n, true, false)).override_failure_message(n).is_not_null()
	m.set_ship_name("Kestrel")
	var ship: Label = game.find_child("ShipName", true, false)
	assert_bool(ship.visible).is_true()
	assert_str(ship.text).contains("Kestrel")
	# Outside a session: Settings (Full screen there) and Controls, to change keys.
	var main: SettingsScreen = _menu(false)
	assert_array(_tab_names(main)).is_equal(
		[SettingsScreen.TAB_SETTINGS, SettingsScreen.TAB_CONTROLS]
	)
	(
		assert_object(
			main.tabs.get_node(SettingsScreen.TAB_SETTINGS).find_child("Fullscreen", true, false)
		)
		. is_not_null()
	)


# FT: FT-AUD-024
func test_the_music_slider_sits_in_the_game_tab_and_saves_on_close() -> void:
	var m: SettingsScreen = _menu()
	var slider: HSlider = m.tabs.get_node(SettingsScreen.TAB_GAME).find_child("Music", true, false)
	assert_float(slider.value).is_equal(50.0)
	slider.value = 25.0
	assert_float(m.settings.music_volume).is_equal(0.25)
	m.close()
	var saved: ClientSettings = ClientSettings.new(CFG)
	saved.load_file()
	assert_float(saved.music_volume).is_equal(0.25)


# FT: FT-STN-011, FT-MIS-040
# A vote, a run start or an elimination changes one button; the tabs and the Controls
# pane stay the same nodes.
func test_pause_and_abandon_change_in_place() -> void:
	var m: SettingsScreen = _menu()
	m.set_controls(Bindings.new(), ["helm"], IntentTable.KBM, "helm")
	var tabs: TabContainer = m.tabs
	var pane: ControlsPane = m.controls_pane
	var abandon: Button = _button(m, "Abandon")
	assert_bool(abandon.visible).is_false()
	for key: String in ["settings.abandon_vote", "settings.abandon_unvote", "settings.forfeit"]:
		m.set_abandon_control(key)
		assert_bool(abandon.visible).is_true()
		assert_str(abandon.text).is_equal(tr(key))
	m.set_abandon_control("")
	assert_bool(abandon.visible).is_false()
	m.set_pause_control(true)
	m.set_pause_control(false)
	assert_object(m.tabs).is_same(tabs)
	assert_object(m.controls_pane).is_same(pane)
	assert_object(_button(m, "Abandon")).is_same(abandon)


# FT: FT-STN-011
func test_leave_asks_to_confirm_in_place() -> void:
	var m: SettingsScreen = _menu()
	var left: Array[bool] = []
	m.leave_requested.connect(func() -> void: left.append(true))
	var leave: Button = _button(m, "Leave")
	leave.pressed.emit()
	assert_array(left).is_empty()
	assert_str(leave.text).is_equal(tr("settings.confirm_leave"))
	leave.pressed.emit()
	assert_array(left).has_size(1)
	assert_str(leave.text).is_equal(tr("settings.leave"))
	# A second tap after the wait arms it again instead.
	leave.pressed.emit()
	m._armed["Leave"] = Time.get_ticks_msec() - 1
	leave.pressed.emit()
	assert_array(left).has_size(1)
	# Closing the menu disarms it.
	m.close()
	assert_str(leave.text).is_equal(tr("settings.leave"))


# FT: FT-STN-011, FT-MIS-016
# The host's Abandon or Give up ends the run, so it confirms; a crew vote goes at once.
func test_host_abandon_confirms_and_a_vote_goes_at_once() -> void:
	var m: SettingsScreen = _menu()
	var asked: Array[bool] = []
	m.abandon_requested.connect(func() -> void: asked.append(true))
	var abandon: Button = _button(m, "Abandon")
	m.set_abandon_control("settings.abandon")
	abandon.pressed.emit()
	assert_array(asked).is_empty()
	assert_str(abandon.text).is_equal(tr("settings.confirm"))
	abandon.pressed.emit()
	assert_array(asked).has_size(1)
	m.visible = true
	m.set_abandon_control("settings.forfeit_vote")
	abandon.pressed.emit()
	assert_array(asked).has_size(2)
	assert_bool(m.visible).is_false()


# FT: FT-STN-011, FT-STN-014
# A phone has no keys to change: the Controls tab hides Change keys, and outside a session
# (where the tab is there for them) the menu has no Controls tab (a hidden one would still
# widen the tab bar past a phone's width); a window that turns into one hides them.
func test_a_phone_has_no_change_keys() -> void:
	var m: SettingsScreen = _menu()
	var keys: Control = m.find_child("ChangeKeys", true, false)
	assert_bool(keys.visible).is_true()
	LayoutMode.forced = LayoutMode.Kind.PHONE
	m._fit_safe_area()
	assert_bool(keys.visible).is_false()
	var main: SettingsScreen = _menu(false)
	var tab: int = main.tabs.get_node(SettingsScreen.TAB_CONTROLS).get_index()
	main.open(SettingsScreen.TAB_CONTROLS)
	LayoutMode.forced = LayoutMode.Kind.PHONE
	main._fit_safe_area()
	assert_bool(main.tabs.is_tab_hidden(tab)).is_true()
	assert_str(main.current_tab_name()).is_equal(SettingsScreen.TAB_SETTINGS)
	var phone: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(phone)
	phone.setup(ClientSettings.new(CFG), false)
	assert_array(_tab_names(phone)).not_contains([SettingsScreen.TAB_CONTROLS])
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	phone._fit_safe_area()
	assert_array(_tab_names(phone)).contains([SettingsScreen.TAB_CONTROLS])


# FT: FT-STN-012, FT-STN-014
# Owner A13/A14: the Controls tab shows content even before a seat is known (every
# station), and Change keys sits under it with the seat's stations first, then the rest.
func test_the_controls_tab_shows_controls_then_change_keys() -> void:
	var m: SettingsScreen = _menu()
	m.open(SettingsScreen.TAB_CONTROLS)
	assert_array(m.controls.rows()).is_not_empty()
	m.set_controls(m.settings.bindings, ["helm"], IntentTable.KBM, "helm")
	var sections: Array = m.controls.rows().map(func(r: Dictionary) -> String: return r["section"])
	assert_array(sections).contains(["station.helm"]).not_contains(["station.weapons"])
	var keys: Control = m.controls_pane.find_child("ChangeKeys", true, false)
	assert_object(keys).is_not_null()
	var first: Label = keys.find_child("Row_*", true, false).get_parent().get_child(1)
	assert_str(first.text).is_equal(tr("settings.group_helm"))
	for id: String in ["cycle_target", "fire", "approach"]:
		(
			assert_object(keys.find_child("Row_" + id, true, false))
			. override_failure_message(id)
			. is_not_null()
		)


# FT: FT-AUD-010
func test_the_subtitle_size_sits_in_the_game_tab_and_is_saved() -> void:
	var m: SettingsScreen = _menu()
	var pick: OptionButton = m.tabs.get_node(SettingsScreen.TAB_GAME).find_child(
		"SubtitleSize", true, false
	)
	assert_int(pick.selected).is_equal(1)
	pick.item_selected.emit(2)
	assert_str(m.settings.subtitle_size).is_equal("large")
	m.close()
	var saved: ClientSettings = ClientSettings.new(CFG)
	saved.load_file()
	assert_str(saved.subtitle_size).is_equal("large")


# FT: FT-STN-013
# T5: a touch or phone layout's scale slider starts at 100 %; the saved scale is kept.
func test_the_scale_slider_starts_at_100_percent_on_touch_layouts() -> void:
	var m: SettingsScreen = _menu()
	m.settings.set_ui_scale(0.75)
	var slider: HSlider = m.find_child("UiScale", true, false) as HSlider
	LayoutMode.forced = LayoutMode.Kind.TOUCH
	m._fit_safe_area()
	assert_float(slider.min_value).is_equal(100.0)
	assert_float(slider.value).is_equal(100.0)
	assert_float(m.settings.ui_scale).is_equal(0.75)
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	m._fit_safe_area()
	assert_float(slider.min_value).is_equal(75.0)
	assert_float(slider.value).is_equal(75.0)


# FT: FT-STN-011
# #35 A5: the Game tab has the player's name; Enter saves a changed, non-empty name and asks
# the shell to rename the session; an empty one puts the old name back.
func test_the_game_tab_renames_the_player() -> void:
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	var m: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(m)
	var settings: ClientSettings = ClientSettings.new(CFG)
	settings.player_name = "Ana"
	m.setup(settings, true)
	var field: LineEdit = m.find_child("PlayerName", true, false)
	assert_str(field.text).is_equal("Ana")
	var names: Array[String] = []
	m.name_changed.connect(func(n: String) -> void: names.append(n))
	field.text = "  "
	field.text_submitted.emit(field.text)
	assert_str(field.text).is_equal("Ana")
	field.text = " Bea "
	field.text_submitted.emit(field.text)
	assert_array(names).is_equal(["Bea"])
	assert_str(m.settings.player_name).is_equal("Bea")
	if FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
