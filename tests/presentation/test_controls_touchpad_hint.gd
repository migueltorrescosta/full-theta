extends GdUnitTestSuite
## The Controls page warns Linux players on Helm that the touchpad may pause while a key is
## held (#35 A12, owner playtest 2026-11-02).


# FT: FT-STN-012
func test_the_touchpad_hint_shows_for_helm_on_linux_only() -> void:
	assert_bool(ControlsPane.touchpad_hint(["helm"], "Linux")).is_true()
	assert_bool(ControlsPane.touchpad_hint(["helm", "weapons"], "Linux")).is_true()
	assert_bool(ControlsPane.touchpad_hint(["engineering"], "Linux")).is_false()
	assert_bool(ControlsPane.touchpad_hint(["helm"], "Windows")).is_false()
	assert_bool(ControlsPane.touchpad_hint(["helm"], "macOS")).is_false()


# FT: FT-STN-012
# D4: a desktop build names the engine's OS (the web build's Linux comes from Godot's
# web_linuxbsd feature tag, which a desktop run never has).
func test_a_desktop_build_names_the_engines_os() -> void:
	assert_bool(OS.has_feature("web_linuxbsd")).is_false()
	assert_str(ControlsPane.host_os()).is_equal(OS.get_name())


# FT: FT-STN-012
# D4: the List view carries the note too, not only the keyboard diagram.
func test_the_list_view_shows_the_note() -> void:
	I18n.apply("en")
	var pane: ControlsPane = auto_free(ControlsPane.new())
	add_child(pane)
	pane.build(Bindings.new(), ["helm"], IntentTable.KBM)
	pane.show_view(ControlsPane.VIEW_LIST)
	var note: Label = pane.get_node("ListNote")
	assert_bool(note.visible).is_equal(ControlsPane.touchpad_hint(["helm"]))
	assert_str(note.text).is_equal(tr("controls.touchpad_hint"))
	pane.build(Bindings.new(), ["engineering"], IntentTable.KBM)
	pane.show_view(ControlsPane.VIEW_LIST)
	assert_bool(note.visible).is_false()
