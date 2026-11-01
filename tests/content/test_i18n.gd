extends GdUnitTestSuite
## UI strings per session language (content/i18n/i18n.gd).

var _locale: String


func before_test() -> void:
	_locale = TranslationServer.get_locale()


func after_test() -> void:
	I18n.apply("en")
	TranslationServer.set_locale(_locale)


# FT: FT-AUD-012, FT-DAT-011
func test_every_launch_language_has_every_string() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(I18n.STRINGS))
	var keys: Array = (data["strings"] as Dictionary).keys()
	for lang: String in I18n.LANGUAGES:
		var t: Translation = I18n.translation(lang)
		assert_object(t).is_not_null()
		assert_str(t.locale).is_equal(lang)
		# Sorted equality is contains_exactly_in_any_order, and one assert over the mismatches
		# checks every message: thousands of gdUnit4 asserts took 15 s (#27).
		var got: Array = Array(t.get_message_list())
		got.sort()
		var want: Array = keys.duplicate()
		want.sort()
		assert_array(got).is_equal(want)
		var wrong: Array[String] = []
		for key: String in keys:
			if String(t.get_message(key)) != data["strings"][key][lang]:
				wrong.append("%s: %s" % [lang, key])
		assert_array(wrong).is_empty()


# FT: FT-AUD-013
func test_apply_switches_all_ui_text_to_the_session_language() -> void:
	assert_bool(I18n.apply("pt_PT")).is_true()
	assert_str(tr("subtitle.computer")).is_equal("Computador de bordo")
	assert_bool(I18n.apply("it")).is_true()
	assert_str(tr("subtitle.computer")).is_equal("Computer di bordo")
	assert_str(TranslationServer.get_locale()).is_equal("it")


# FT: FT-AUD-012
func test_unknown_language_is_refused() -> void:
	assert_bool(I18n.apply("fr")).is_false()
	assert_object(I18n.translation("pt_BR")).is_null()


# FT: FT-STN-012, FT-AUD-012
func test_every_seat_has_a_role_summary_in_every_language() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(I18n.STRINGS))
	var ids: Array = StationViews.STATIONS.keys() + StationViews.ENTRIES.keys()
	ids.append(StationViews.ALL)
	for id: String in ids:
		var entry: Dictionary = data["strings"].get("role." + id, {})
		for lang: String in I18n.LANGUAGES:
			assert_str(str(entry.get(lang, ""))).is_not_empty()
