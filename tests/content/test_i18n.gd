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
		assert_array(Array(t.get_message_list())).contains_exactly_in_any_order(keys)
		for key: String in keys:
			assert_str(String(t.get_message(key))).is_equal(data["strings"][key][lang])


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
