class_name TouchText
extends RefCounted
## The touch widgets' strings: the translation of a key of content/i18n/strings.json, for
## static functions (an instance calls `tr`). The touch help pictures' data
## (`touch_help()`) names only keys.


static func t(key: String) -> String:
	return TranslationServer.translate(key)
