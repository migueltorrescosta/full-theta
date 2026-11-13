extends GdUnitTestSuite
## Every reason the director logs has a string in each launch language (FT-MIS-006, D35), so
## the debrief never shows a raw key. The reasons a bot run logs are checked against the same
## strings in tests/sim/run/test_seeded_run.gd.


func _strings() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(I18n.STRINGS))["strings"]


# FT: FT-MIS-006
func test_every_reason_key_the_director_can_log_resolves() -> void:
	var source: String = (
		FileAccess.get_file_as_string("res://director/director.gd")
		+ FileAccess.get_file_as_string("res://director/fleet_director.gd")
	)
	var pattern: String = (
		'"reason": "([a-z_]+)"|reason: String = "([a-z_]+)"'
		+ '|"(site_pool|periodic|rejected|run_length|budget_spent|finale|finale_won|finale_out)"'
		+ '|"director\\.reason\\.([a-z_]+)"'
	)
	var found: RegEx = RegEx.create_from_string(pattern)
	var keys: Dictionary = {}
	for m: RegExMatch in found.search_all(source):
		for g: int in [1, 2, 3, 4]:
			if m.get_string(g) != "":
				keys["director.reason." + m.get_string(g)] = true
	assert_int(keys.size()).is_greater_equal(6)
	var strings: Dictionary = _strings()
	for key: String in keys:
		assert_bool(strings.has(key)).is_true()
		for lang: String in I18n.LANGUAGES:
			assert_str(str(strings[key][lang])).is_not_empty()
