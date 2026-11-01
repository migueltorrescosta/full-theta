extends GdUnitTestSuite
## Helm's touch help data (#28 follow-up, P28-Help): one page per phone page with its title,
## the persistent controls on the first, and every text a translation (no key or fallback).
# FT: FT-STN-012


func before() -> void:
	I18n.apply("en")


func test_help_names_every_page_and_control() -> void:
	var help: Array = HelmPanel.touch_help()
	assert_int(help.size()).is_equal(HelmTouch.PAGE_IDS.size())
	for p: int in help.size():
		assert_str(help[p]["page"]).is_equal(HelmTouch.page_titles()[p])
		assert_array(help[p]["boxes"]).is_not_empty()
		for b: Array in help[p]["boxes"]:
			for text: String in [b[1], b[2]]:
				assert_str(text).is_not_empty()
				assert_bool(text.begins_with("intent.") or text.begins_with("touch.")).is_false()
	# The Fly page numbers the persistent controls too.
	assert_int(help[0]["boxes"].size()).is_greater(help[1]["boxes"].size() + 4)
