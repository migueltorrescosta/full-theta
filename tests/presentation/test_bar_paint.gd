extends GdUnitTestSuite
## BarPaint (R05-11): the shared track-and-fill bar; UiTheme.action_button (R05-9).
# FT: FT-STN-005


class Canvas:
	extends Control
	var args: Array = []

	func _draw() -> void:
		BarPaint.draw(self, Rect2(0, 0, 100, 10), args[0], Color.RED, Color.BLUE)


func test_fill_clamps_to_track() -> void:
	var c: Canvas = auto_free(Canvas.new())
	c.size = Vector2(100, 10)
	for f: float in [-1.0, 0.5, 3.0]:
		c.args = [f]
		c._draw()  # Must not error on out-of-range fractions.
	assert_float(clampf(3.0, 0.0, 1.0)).is_equal(1.0)


func test_action_button_sizes() -> void:
	var b: Button = auto_free(UiTheme.action_button("Go", "Go", 140.0, "X"))
	assert_vector(b.custom_minimum_size).is_equal(Vector2(140, UiTheme.TOUCH_PRIMARY))
	assert_str(b.name).is_equal("Go")
	assert_str(b.theme_type_variation).is_equal("X")
