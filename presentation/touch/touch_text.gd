class_name TouchText
extends RefCounted
## The touch widgets' few strings: the translation of `key` (content/i18n/strings.json),
## or the English `fallback` while the table lacks it.


static func of(key: String, fallback: String) -> String:
	var t: String = TranslationServer.translate(key)
	return fallback if t == key else t
