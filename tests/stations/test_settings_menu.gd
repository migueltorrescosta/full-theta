extends GdUnitTestSuite
## The in-game menu (FT-STN-011, P28 menu): Game, Controls, Tips, Settings and Rebind keys
## tabs; the Pause and Abandon controls change in place, never rebuilding the menu (load
## fix 2); Leave and the host's Abandon or Give up ask to confirm in place; a phone has no
## Rebind keys tab.

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
		[
			SettingsScreen.TAB_GAME,
			SettingsScreen.TAB_CONTROLS,
			SettingsScreen.TAB_TIPS,
			SettingsScreen.TAB_SETTINGS,
			SettingsScreen.TAB_KEYS
		]
	)
	assert_str(m.current_tab_name()).is_equal(SettingsScreen.TAB_GAME)
	var game: Node = m.tabs.get_node(SettingsScreen.TAB_GAME)
	for n: String in ["ShipName", "Sound", "Fullscreen", "HostPause", "Abandon", "Leave"]:
		assert_object(game.find_child(n, true, false)).override_failure_message(n).is_not_null()
	m.set_ship_name("Kestrel")
	var ship: Label = game.find_child("ShipName", true, false)
	assert_bool(ship.visible).is_true()
	assert_str(ship.text).contains("Kestrel")
	# Outside a session: Settings (Full screen there) and Rebind keys only.
	var main: SettingsScreen = _menu(false)
	assert_array(_tab_names(main)).is_equal([SettingsScreen.TAB_SETTINGS, SettingsScreen.TAB_KEYS])
	(
		assert_object(
			main.tabs.get_node(SettingsScreen.TAB_SETTINGS).find_child("Fullscreen", true, false)
		)
		. is_not_null()
	)


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
# A phone has no keys to rebind: its menu hides the Rebind keys tab.
func test_a_phone_hides_the_rebind_keys_tab() -> void:
	var m: SettingsScreen = _menu()
	var keys: int = m.tabs.get_node(SettingsScreen.TAB_KEYS).get_index()
	assert_bool(m.tabs.is_tab_hidden(keys)).is_false()
	m.open(SettingsScreen.TAB_KEYS)
	LayoutMode.forced = LayoutMode.Kind.PHONE
	m._fit_safe_area()
	assert_bool(m.tabs.is_tab_hidden(keys)).is_true()
	assert_str(m.current_tab_name()).is_equal(SettingsScreen.TAB_SETTINGS)
