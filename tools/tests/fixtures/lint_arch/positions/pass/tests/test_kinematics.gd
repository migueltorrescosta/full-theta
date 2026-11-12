extends GdUnitTestSuite


func test_wrap() -> void:
	var kin := Kinematics.new()
	assert_float(kin.pos_x[0]).is_equal(0.0)
