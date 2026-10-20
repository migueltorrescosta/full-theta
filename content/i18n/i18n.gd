class_name I18n
extends RefCounted
## Session language for UI text (FT-AUD-013, D41): the host picks one language before
## launch and every client gets it in Welcome (`lang`); clients call apply() with it, so
## tr() returns the UI strings of content/i18n/strings.json in that language. Spoken lines
## and their subtitles arrive already in the session language (net/voice/). The l0 gate
## (tools/check_dialogue.py) keeps every string complete in each launch language
## (FT-DAT-011).

## Session languages (FT-AUD-012); the first is the default.
const LANGUAGES: PackedStringArray = ["en", "pt_PT", "it"]
const STRINGS: String = "res://content/i18n/strings.json"


## One Translation for `lang` holding every key of the string table; null for a
## language that isn't a launch language or an unreadable table.
static func translation(lang: String, path: String = STRINGS) -> Translation:
	if lang not in LANGUAGES:
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not (data as Dictionary).get("strings") is Dictionary:
		return null
	var t: Translation = Translation.new()
	t.locale = lang
	var strings: Dictionary = data["strings"]
	for key: String in strings:
		t.add_message(key, str((strings[key] as Dictionary).get(lang, key)))
	return t


## Installs `lang`'s strings (replacing an earlier apply) and makes it the locale.
## Returns false, changing nothing, for a language that isn't a launch language.
static func apply(lang: String, path: String = STRINGS) -> bool:
	var t: Translation = translation(lang, path)
	if t == null:
		return false
	for other: String in LANGUAGES:
		for old: Translation in TranslationServer.get_translations():
			if old.locale == other and old.has_meta(&"ft_i18n"):
				TranslationServer.remove_translation(old)
	t.set_meta(&"ft_i18n", true)
	TranslationServer.add_translation(t)
	TranslationServer.set_locale(lang)
	return true
