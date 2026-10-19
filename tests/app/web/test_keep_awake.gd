extends GdUnitTestSuite
## KeepAwake off the web: every call is a harmless no-op, so desktop clients
## can call it unconditionally. The browser behaviour itself is checked in the
## S3 harness and on tablets in #4, not here.


func test_is_a_no_op_off_the_web() -> void:
	assert_str(KeepAwake.start()).is_equal("")
	KeepAwake.stop()
	assert_bool(KeepAwake.status().is_empty()).is_true()
