extends GdUnitTestSuite

func test_wrap() -> void:
	var kin := Kinematics.new()
	assert_float(kin.px[0]).is_equal(0.0)
