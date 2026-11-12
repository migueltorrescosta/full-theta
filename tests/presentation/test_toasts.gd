extends GdUnitTestSuite
## Toasts (§5.0): newest at the top, expiry, cap.


func test_toasts_newest_first_expire_and_cap() -> void:
	var toasts: Toasts = auto_free(Toasts.new())
	for i: int in 5:
		toasts.push("t%d" % i, "info", i * 100)
	assert_array(toasts.texts()).is_equal(["t4", "t3", "t2", "t1"])
	toasts.update(Toasts.SHOW_MS + 250)
	assert_array(toasts.texts()).is_equal(["t4", "t3"])
	toasts.update(Toasts.SHOW_MS + 400)
	assert_array(toasts.texts()).is_empty()


# The newest toast shows, with the number queued behind it (D319).
func test_the_newest_shows_with_a_count() -> void:
	var toasts: Toasts = auto_free(Toasts.new())
	assert_bool(toasts.visible).is_false()
	toasts.push("first", "info", 0)
	assert_str(toasts.shown()).is_equal("first")
	toasts.push("second", "warn", 10)
	assert_str(toasts.shown()).is_equal("second +1")
	toasts.update(Toasts.SHOW_MS + 5)
	assert_str(toasts.shown()).is_equal("second")
	toasts.update(Toasts.SHOW_MS + 20)
	assert_bool(toasts.visible).is_false()


# C5, ux-14: one queue; a note (a share, a lapsed request) shows above info toasts and under
# warnings, a keyed toast updates in place, and the cap drops the oldest of the lowest rank.
func test_priorities_and_keyed_toasts() -> void:
	var toasts: Toasts = auto_free(Toasts.new())
	toasts.push("note", "note", 0, "share:routes")
	toasts.push("info", "info", 10)
	assert_str(toasts.shown()).is_equal("note +1")
	toasts.push("warn", "warn", 20)
	assert_str(toasts.shown()).is_equal("warn +2")
	toasts.push("note again", "note", 30, "share:routes")
	assert_array(toasts.texts()).is_equal(["warn", "info", "note again"])
	assert_bool(toasts.has_key("share:routes")).is_true()
	toasts.push("info 2", "info", 40)
	toasts.push("info 3", "info", 50)
	assert_array(toasts.texts()).is_equal(["info 3", "info 2", "warn", "note again"])
	toasts.update(Toasts.SHOW_MS + 5)
	assert_bool(toasts.has_key("share:routes")).is_false()
