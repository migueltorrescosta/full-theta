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
