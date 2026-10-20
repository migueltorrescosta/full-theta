extends GdUnitTestSuite
## The shield ring's focus dot sits in the cell of its clock and height band (D184).
# FT: FT-HLM-011

var ring: ShieldRing


func before_test() -> void:
	ring = auto_free(ShieldRing.new())
	ring.size = Vector2(200, 230)


## The cell the focus dot sits in, through the ring's own click mapping.
func _cell_of_focus(focus: Vector3) -> Vector3:
	ring.focus = focus
	return ring.direction_at(ring.focus_point())


# FT: FT-HLM-009, FT-HLM-011
func test_focus_dot_sits_in_its_height_band() -> void:
	for hour: int in [0, 4, 8]:
		for band: int in 3:
			var dir: Vector3 = ShieldRing.cell_direction(hour, band)
			assert_vector(_cell_of_focus(dir)).is_equal_approx(dir, Vector3.ONE * 0.001)
	# By the height words: 16° up is high (outer), 14° level (middle), 16° down low (inner).
	for e: Array in [[16.0, 2], [14.0, 1], [-16.0, 0]]:
		var dir: Vector3 = Vector3(0.0, sin(deg_to_rad(e[0])), -cos(deg_to_rad(e[0])))
		assert_vector(_cell_of_focus(dir)).is_equal_approx(
			ShieldRing.cell_direction(0, e[1]), Vector3.ONE * 0.001
		)
	# Beyond 60°: the overhead or under half of the centre.
	assert_vector(_cell_of_focus(Vector3(0.1, 1.0, 0.0))).is_equal(Vector3.UP)
	assert_vector(_cell_of_focus(Vector3(0.1, -1.0, 0.0))).is_equal(Vector3.DOWN)
