class_name TouchText
extends RefCounted
## The touch widgets' few strings: the translation of `key` (content/i18n/strings.json),
## or the English `fallback` while the table lacks it.


static func of(key: String, fallback: String) -> String:
	var t: String = TranslationServer.translate(key)
	return fallback if t == key else t


## The translation of `key` (content/i18n/strings.json), with no fallback: the touch help
## pictures' data (`touch_help()`) names only keys.
static func t(key: String) -> String:
	return TranslationServer.translate(key)


## A touch help box `[box, name, what]` from "Name: what it does" (or a bare name).
static func named(box: Rect2, text: String) -> Array:
	var parts: PackedStringArray = text.split(": ", true, 1)
	return [box, parts[0], parts[1] if parts.size() > 1 else parts[0]]
