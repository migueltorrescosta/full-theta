extends GdUnitTestSuite
## Helm's touch help picture (#28 follow-up, P28-Help): one picture per phone page, numbered
## once each, naming every control the page holds (HelmTouch.PAGE_IDS) and the persistent
## ones on the first.
# FT: FT-STN-012


func before() -> void:
	I18n.apply("en")


func test_help_names_every_page_and_control() -> void:
	var help: HelmHelp = auto_free(HelmHelp.new())
	assert_int(help.pictures.size()).is_equal(HelmTouch.PAGE_IDS.size())
	var numbers: Array[int] = []
	for p: int in help.pictures.size():
		assert_str(help.pictures[p][0]).is_equal(HelmTouch.page_titles()[p])
		var keys: Array = []
		for c: Array in help.pictures[p][1]:
			numbers.append(int(c[0]))
			keys.append(c[1])
			assert_str(HelmHelp.text(c[1])).is_not_empty()
			assert_str(HelmHelp.text(c[1])).is_not_equal("intent." + str(c[1]))
		for id: String in HelmTouch.PAGE_IDS[p]:
			var key: String = "range" if id.begins_with("range_") else id
			assert_array(keys).override_failure_message("%s p%d" % [id, p]).contains([key])
	for id: String in ["all_stop", "approach", "throttle", "turn", "slide"]:
		assert_bool(help.pictures[0][1].any(func(c: Array) -> bool: return c[1] == id)).is_true()
	var expected: Array[int] = []
	for i: int in numbers.size():
		expected.append(i + 1)
	assert_array(numbers).is_equal(expected)
	assert_float(help.custom_minimum_size.x).is_equal(HelmHelp.WIDTH)
