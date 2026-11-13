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


# FT: FT-STN-011
# R25-13: the controller picture says which button each letter is, by place. R25-9: with
# Weapons shown, the keyboard picture says a left click selects over an item and fires
# elsewhere (D176).
func test_the_pad_and_left_click_notes() -> void:
	I18n.apply("en")
	# The headless window is phone-sized, and a phone has no diagrams.
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	var pane: ControlsPane = auto_free(ControlsPane.new())
	add_child(pane)
	pane.build(Bindings.new(), ["weapons"], IntentTable.PAD)
	pane.show_view(ControlsPane.VIEW_PAD)
	var pad_note: Label = pane.get_node(ControlsPane.VIEW_PAD + "View").get_child(1)
	assert_str(pad_note.text).contains("A bottom, B right, X left, Y top")
	pane.show_view(ControlsPane.VIEW_KBM)
	var kbm_note: Label = pane.get_node(ControlsPane.VIEW_KBM + "View").get_child(1)
	assert_str(kbm_note.text).contains("Left click selects")
	assert_bool(ControlsPane.lmb_split(Bindings.new(), ["helm"])).is_false()
	var b: Bindings = Bindings.new()
	b.rebind("fire", IntentTable.KBM, PackedStringArray(["Space"]))
	assert_bool(ControlsPane.lmb_split(b, ["weapons"])).is_false()


# FT: FT-STN-011
# R25-14: "?" is whichever key types it, so it has no place on the drawing; the note under
# the keyboard names it. The US slash key is the physical Slash.
func test_the_question_mark_is_named_not_drawn() -> void:
	I18n.apply("en")
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	assert_dict(ControlsFigure.part(IntentTable.KBM, "?")).is_empty()
	assert_str(ControlsFigure.part(IntentTable.KBM, "Slash")["caption"]).is_equal("/")
	var known: Dictionary = ControlsFigure.ids(IntentTable.KBM)
	assert_array(ControlsModel.parts_of("Slash", known)).is_equal(["Slash"])
	var pane: ControlsPane = auto_free(ControlsPane.new())
	add_child(pane)
	pane.build(Bindings.new(), ["comms"], IntentTable.KBM)
	pane.show_view(ControlsPane.VIEW_KBM)
	var note: Label = pane.get_node(ControlsPane.VIEW_KBM + "View").get_child(1)
	assert_str(note.text).contains("Show controls: type ?")
	assert_str(note.text).not_contains("Not on the picture")
