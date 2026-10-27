extends GdUnitTestSuite
## Every reason the director logs has a string in each launch language (FT-MIS-006, D35), so
## the debrief never shows a raw key.


func _strings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(I18n.STRINGS))["strings"]


# FT: FT-MIS-006
func test_every_reason_key_the_director_can_log_resolves() -> void:
	var source: String = FileAccess.get_file_as_string("res://director/director.gd")
	var pattern: String = (
		'"reason": "([a-z_]+)"|reason: String = "([a-z_]+)"'
		+ '|"(site_pool|periodic|rejected|run_length|budget_spent)"'
	)
	var found: RegEx = RegEx.create_from_string(pattern)
	var keys: Dictionary = {}
	for m: RegExMatch in found.search_all(source):
		for g: int in [1, 2, 3]:
			if m.get_string(g) != "":
				keys["director.reason." + m.get_string(g)] = true
	assert_int(keys.size()).is_greater_equal(6)
	var strings: Dictionary = _strings()
	for key: String in keys:
		assert_bool(strings.has(key)).is_true()
		for lang: String in I18n.LANGUAGES:
			assert_str(str(strings[key][lang])).is_not_empty()


# FT: FT-MIS-006
func test_a_run_logs_only_resolvable_reasons() -> void:
	var r: Dictionary = BotRun.play(DefLibrary.new(), "average", "easy", 1, 600.0)
	var strings: Dictionary = _strings()
	assert_array(r["decisions"]).is_not_empty()
	for d: Dictionary in r["decisions"]:
		assert_bool(strings.has(d["reason_key"])).is_true()
		var text: String = str(strings[d["reason_key"]]["en"]).format(d["reason_args"])
		assert_bool(text.contains("{")).is_false()
