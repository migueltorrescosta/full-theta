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


# FT: FT-STN-012
# C3 (ux-08): Helm's and Weapons' rail labels are a verb and its object, at most 14 characters
# in every language; none is a raw key.
func test_rail_labels_are_short_in_every_language() -> void:
	var keys: Array[String] = [
		"touch.helm.face",
		"touch.helm.align",
		"touch.helm.shield_track",
		"touch.helm.dock",
		"touch.helm.undock",
		"touch.helm.jump",
		"weapons.touch_guided",
		"weapons.touch_claim",
		"weapons.touch_claim_held",
		"touch.weapons.mount",
	]
	for lang: String in I18n.LANGUAGES:
		I18n.apply(lang)
		for key: String in keys:
			var text: String = tr(key)
			if "%d" in text:
				text = text % 1
			assert_str(text).override_failure_message("%s %s" % [lang, key]).is_not_equal(key)
			(
				assert_int(text.length())
				. override_failure_message("%s %s: %s" % [lang, key, text])
				. is_less_equal(14)
			)
	I18n.apply("en")
