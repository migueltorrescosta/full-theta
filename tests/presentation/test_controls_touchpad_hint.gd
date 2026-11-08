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
# D4: a browser on Linux is a Linux desktop; Android's user agent also names Linux.
func test_a_web_build_on_linux_gets_the_hint() -> void:
	var firefox: String = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
	var android: String = "Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/126.0 Mobile Safari/537.36"
	var windows: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0 Safari/537.36"
	assert_str(ControlsPane.os_of_agent(firefox, "Web")).is_equal("Linux")
	assert_str(ControlsPane.os_of_agent(android, "Web")).is_equal("Android")
	assert_str(ControlsPane.os_of_agent(windows, "Web")).is_equal("Web")
	(
		assert_bool(ControlsPane.touchpad_hint(["helm"], ControlsPane.os_of_agent(firefox, "Web")))
		. is_true()
	)
	(
		assert_bool(ControlsPane.touchpad_hint(["helm"], ControlsPane.os_of_agent(windows, "Web")))
		. is_false()
	)


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


# FT: FT-STN-012
# D2: the Controls page links the callout card.
func test_the_page_links_the_callout_card() -> void:
	I18n.apply("en")
	var pane: ControlsPane = auto_free(ControlsPane.new())
	add_child(pane)
	pane.build(Bindings.new(), ["helm"], IntentTable.KBM)
	var link: LinkButton = pane.get_node("CalloutCard")
	assert_str(link.text).is_equal("Callout card: how the crew names contacts")
	assert_str(ControlsPane.CALLOUT_CARD_URL).ends_with("docs/callout-card.md")
	assert_bool(FileAccess.file_exists("res://docs/callout-card.md")).is_true()
