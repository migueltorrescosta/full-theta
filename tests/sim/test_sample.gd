extends GdUnitTestSuite
## Sample suite proving the gdUnit4 runner works headless.


# FT: FT-TST-001
func test_runner_works() -> void:
	assert_int(1 + 1).is_equal(2)
