extends GdUnitTestSuite
## A finger drag scrolls the phone menu's tabs, Controls included, also when it starts on a
## full-width button (the Android Firefox check): TouchScroll follows the finger itself where
## the engine does not (a child takes the press, or no touchscreen is reported, as in a
## headless run).


func after() -> void:
	LayoutMode.forced = -1


## A phone-sized viewport holding the menu with the touch pictures of two stations.
func _menu() -> Array:
	LayoutMode.forced = LayoutMode.Kind.PHONE
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = Vector2i(844, 390)
	vp.gui_embed_subwindows = true
	add_child(vp)
	var m: SettingsScreen = SettingsScreen.new()
	vp.add_child(m)
	m.setup(ClientSettings.new("user://test_menu_touch_scroll.cfg"), true)
	m.set_controls(Bindings.new(), ["engineering", "weapons"], IntentTable.KBM, "engineering")
	return [vp, m]


func _touch(vp: SubViewport, index: int, pos: Vector2, pressed: bool) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	vp.push_input(t, true)


func _drag(vp: SubViewport, index: int, from: Vector2, to: Vector2) -> void:
	var steps: int = 8
	for i: int in range(1, steps + 1):
		var p: Vector2 = from.lerp(to, float(i) / steps)
		var d: InputEventScreenDrag = InputEventScreenDrag.new()
		d.index = index
		d.position = p
		d.relative = (to - from) / steps
		vp.push_input(d, true)


## The scroll position after a finger swipe up from `start` on the tab named `tab`.
func _swipe(tab: String, start: Vector2) -> int:
	var made: Array = _menu()
	var vp: SubViewport = made[0]
	var m: SettingsScreen = made[1]
	m.open_tab(tab)
	await await_idle_frame()
	await await_idle_frame()
	var scroll: ScrollContainer = m.tabs.get_node(tab)
	assert_bool(scroll.get_v_scroll_bar().max_value > scroll.size.y).is_true()
	_touch(vp, 0, start, true)
	_drag(vp, 0, start, start - Vector2(0, 160))
	_touch(vp, 0, start - Vector2(0, 160), false)
	await await_idle_frame()
	return scroll.scroll_vertical


# FT: FT-STN-011
func test_a_touch_drag_scrolls_the_controls_tab() -> void:
	assert_int(await _swipe(SettingsScreen.TAB_CONTROLS, Vector2(400, 300))).is_greater(0)


# FT: FT-STN-011
func test_a_drag_that_starts_on_a_button_scrolls_the_settings_tab() -> void:
	# (the Game and Tips tabs fit a landscape phone's menu; the finger starts on the full-width
	# Reset tips button)
	assert_int(await _swipe(SettingsScreen.TAB_SETTINGS, Vector2(400, 190))).is_greater(0)
