extends GdUnitTestSuite
## Page tabs size to their label (#28 follow-up, P28-Tabs): on a phone's side a tab is at
## least TAB_W wide and never cuts its label ("Requests" stayed "Request" in a 64 px tab);
## upright the tabs share the bottom bar.


# FT: FT-STN-005
func test_a_tab_is_as_wide_as_its_label() -> void:
	var host: PageHost = PageHost.new()
	for t: String in ["Requests", "Contracts", "Rep"]:
		host.add_page(t, [])
	for upright: bool in [false]:
		var tabs: PageTabs = auto_free(PageTabs.new())
		tabs.upright = upright
		add_child(tabs)
		tabs.bind(host)
		await get_tree().process_frame
		for i: int in tabs.tab_count():
			var b: RailButton = tabs.tab(i)
			var font: Font = b.get_theme_font("font")
			var text_w: float = (
				font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, PageTabs.FONT).x
			)
			text_w += b.get_theme_stylebox("normal").get_minimum_size().x
			var why: String = "%s upright=%s" % [b.text, upright]
			assert_float(b.size.x).override_failure_message(why).is_greater_equal(text_w)
			if not upright:
				assert_float(b.size.x).is_greater_equal(PageTabs.TAB_W)


# FT: FT-STN-005
# Upright the tabs share the bar by their labels: in a 374 px bar Missions, Contracts, Hails,
# Rep and Crew all show whole.
func test_upright_tabs_share_the_bar_by_their_labels() -> void:
	var host: PageHost = PageHost.new()
	for t: String in ["Missions", "Contracts", "Hails •", "Rep", "Crew"]:
		host.add_page(t, [])
	var tabs: PageTabs = auto_free(PageTabs.new())
	tabs.upright = true
	add_child(tabs)
	tabs.bind(host)
	tabs.size = Vector2(374, UiTheme.TOUCH_PRIMARY)
	await get_tree().process_frame
	for i: int in tabs.tab_count():
		var b: RailButton = tabs.tab(i)
		var need: float = (
			(
				b
				. get_theme_font("font")
				. get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, PageTabs.FONT)
				. x
			)
			+ b.get_theme_stylebox("normal").get_minimum_size().x
		)
		assert_float(b.size.x).override_failure_message(b.text).is_greater_equal(need)
