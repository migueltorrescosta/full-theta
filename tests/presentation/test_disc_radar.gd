extends GdUnitTestSuite
## DiscRadar (spec §6.2): projection, above/below, beyond-range arrows, centring with the
## ship's axes, hit-testing and hover text.
# FT: FT-STN-002

var radar: DiscRadar


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	radar = auto_free(DiscRadar.new())
	radar.size = Vector2(600, 400)


func _it(kind: String, id: int, label: String, letter: String, local: Vector3) -> Dictionary:
	return {"kind": kind, "id": id, "label": label, "allegiance": letter, "local": local}


# FT: FT-STN-003, FT-SPA-007
func test_item_at_returns_the_contact_drawn_at_its_position() -> void:
	var items: Array[Dictionary] = [
		_it("contact", 3, "H1", "H", Vector3(-3000, 500, -4000)),
		_it("contact", 4, "U2", "U", Vector3(4000, -800, 2000)),
		_it("mark", 0, "Alpha", "", Vector3(2000, 0, -2000)),
	]
	radar.set_items(items, {})
	for it: Dictionary in items:
		var p: Vector2 = radar.project(it["local"])
		assert_dict(radar.item_at(p + Vector2(3, -2))).is_equal(
			{"kind": it["kind"], "id": it["id"]}
		)
	assert_dict(radar.item_at(Vector2(2, 2))).is_empty()


# FT: FT-STN-003, FT-SPA-025
func test_selected_item_wins_a_tie() -> void:
	var items: Array[Dictionary] = [
		_it("contact", 1, "H1", "H", Vector3(1000, 0, -1000)),
		_it("contact", 2, "H2", "H", Vector3(1010, 0, -1000)),
	]
	radar.set_items(items, {"kind": "contact", "id": 1})
	var p: Vector2 = radar.project(items[1]["local"])
	assert_dict(radar.item_at(p)).is_equal({"kind": "contact", "id": 1})
	radar.set_items(items, {})
	assert_dict(radar.item_at(p)).is_equal({"kind": "contact", "id": 2})


# FT: FT-STN-003
func test_chip_is_clickable() -> void:
	var items: Array[Dictionary] = [_it("contact", 5, "H5", "H", Vector3(0, 0, -3000))]
	radar.set_items(items, {})
	# A point on the chip text, right of the blip and outside the blip's hit radius.
	var p: Vector2 = radar.project(items[0]["local"]) + Vector2(40, 0)
	assert_dict(radar.item_at(p)).is_equal({"kind": "contact", "id": 5})
	radar.chips = false
	assert_dict(radar.item_at(p)).is_empty()


# FT: FT-SPA-007, FT-SPA-010
func test_projection_is_ship_frame() -> void:
	var c: Vector2 = radar.disc_centre()
	assert_vector(radar.project(Vector3.ZERO)).is_equal(c)
	# Bow up the screen, starboard right; height lifts the blip off its foot.
	assert_float(radar.project(Vector3(0, 0, -1000)).y).is_less(c.y)
	assert_float(radar.project(Vector3(1000, 0, 0)).x).is_greater(c.x)
	assert_float(radar.project(Vector3(0, 500, 0)).y).is_less(c.y)
	# Clock 3 sits on the rim at range.
	var rim: Vector2 = radar.project(Vector3(DiscRadar.RANGES_M[radar.range_index], 0, 0))
	assert_float(rim.x - c.x).is_equal_approx(radar.disc_radius(), 0.01)


# FT: FT-SPA-007
func test_above_is_solid_below_is_hollow() -> void:
	assert_bool(radar.is_above(Vector3(100, 300, -200))).is_true()
	assert_bool(radar.is_above(Vector3(100, -300, -200))).is_false()
	var up: Vector2 = radar.project(Vector3(1000, 600, -1000))
	var down: Vector2 = radar.project(Vector3(1000, -600, -1000))
	var foot: Vector2 = radar.project(Vector3(1000, 0, -1000))
	assert_float(up.y).is_less(foot.y)
	assert_float(down.y).is_greater(foot.y)


# FT: FT-SPA-024
func test_beyond_range_is_clamped_to_the_rim() -> void:
	var far: Vector3 = Vector3(30000, 2000, 0)
	var items: Array[Dictionary] = [_it("contact", 9, "H9", "H", far)]
	radar.set_items(items, {})
	assert_bool(radar.is_beyond(far)).is_true()
	var rim: Vector2 = radar.disc_centre() + Vector2(radar.disc_radius(), 0)
	assert_dict(radar.item_at(rim)).is_equal({"kind": "contact", "id": 9})
	radar.zoom(1)
	assert_float(DiscRadar.RANGES_M[radar.range_index]).is_equal(50000.0)
	assert_bool(radar.is_beyond(far)).is_false()
	radar.zoom(1)
	assert_int(radar.range_index).is_equal(2)


# FT: FT-SPA-010
func test_centring_on_a_mark_keeps_the_ship_axes() -> void:
	var mark: Vector3 = Vector3(3000, 400, -2000)
	var items: Array[Dictionary] = [
		_it("mark", 1, "Bravo", "", mark), _it("contact", 2, "H2", "H", mark + Vector3(1000, 0, 0))
	]
	radar.set_items(items, {})
	radar.centre = {"kind": "mark", "id": 1}
	var c: Vector2 = radar.disc_centre()
	assert_vector(radar.project(mark)).is_equal_approx(c, Vector2.ONE * 0.01)
	# H2 is 1 km to starboard of Bravo: straight right of the centre, as without centring.
	var h2: Vector2 = radar.project(items[1]["local"])
	assert_float(h2.y).is_equal_approx(c.y, 0.01)
	assert_float(h2.x).is_greater(c.x)
	assert_dict(radar.item_at(c)).is_equal({"kind": "mark", "id": 1})


# FT: FT-SPA-011
func test_tilt_flattens_and_orbit_turns() -> void:
	radar.tilt_deg = 90.0
	var c: Vector2 = radar.disc_centre()
	var bow: Vector2 = radar.project(Vector3(0, 0, -1000))
	assert_float(c.y - bow.y).is_equal_approx(radar.project(Vector3(1000, 0, 0)).x - c.x, 0.01)
	radar.yaw_deg = 90.0
	assert_float(radar.project(Vector3(0, 0, -1000)).x).is_less(c.x)


# FT: FT-SPA-011
func test_right_drag_orbits_only_when_orbitable() -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	var drag: InputEventMouseMotion = InputEventMouseMotion.new()
	drag.relative = Vector2(50, 200)
	radar._gui_input(press)
	radar._gui_input(drag)
	assert_float(radar.tilt_deg).is_equal(35.0)
	radar.orbitable = true
	radar._gui_input(press)
	radar._gui_input(drag)
	assert_float(radar.yaw_deg).is_equal_approx(20.0, 0.01)
	assert_float(radar.tilt_deg).is_equal(DiscRadar.TILT_MIN)


# FT: FT-SPA-005
func test_hover_shows_bearing_and_mark() -> void:
	var items: Array[Dictionary] = [_it("contact", 3, "H3", "H", Vector3(1000, 0, -1000))]
	radar.set_items(items, {})
	assert_str(radar.hover_text(radar.project(items[0]["local"]))).is_equal("brg 045 · mk +0")
	assert_str(radar.hover_text(Vector2(1, 1))).is_empty()


# FT: FT-SPA-008, FT-SPA-009, FT-SPA-025
func test_draws_selection_strip_and_pulses() -> void:
	var items: Array[Dictionary] = [
		_it("contact", 1, "H1", "H", Vector3(1000, 300, -1000)),
		_it("mark", 0, "Alpha", "", Vector3(-1000, -300, 500)),
		_it("point", -1, "", "", Vector3(-6000, 0, 6000)),
	]
	items[2]["pulse"] = 0.5
	radar.side_strip = true
	add_child(radar)
	radar.set_items(items, {"kind": "contact", "id": 1})
	await await_idle_frame()
	# The strip narrows the disc; the point ping is never picked.
	assert_float(radar.disc_centre().x).is_equal_approx((600.0 - DiscRadar.STRIP_W) / 2.0, 0.01)
	assert_dict(radar.item_at(radar.project(items[2]["local"]))).is_empty()
