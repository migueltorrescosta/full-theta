# gdlint: disable=max-public-methods
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


## An item of a hand-built picture (identity rotation, no wrap: world = local).
func _it(kind: String, id: int, label: String, letter: String, local: Vector3) -> Dictionary:
	return {
		"kind": kind, "id": id, "label": label, "allegiance": letter, "local": local, "world": local
	}


func _pic(items: Array[Dictionary]) -> ContactPicture:
	var pic: ContactPicture = ContactPicture.new()
	pic.items = items
	return pic


# FT: FT-STN-003, FT-SPA-007
func test_item_at_returns_the_contact_drawn_at_its_position() -> void:
	var items: Array[Dictionary] = [
		_it("contact", 3, "H1", "H", Vector3(-3000, 500, -4000)),
		_it("contact", 4, "U2", "U", Vector3(4000, -800, 2000)),
		_it("mark", 0, "Alpha", "", Vector3(2000, 0, -2000)),
	]
	radar.set_picture(_pic(items), {})
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
	radar.set_picture(_pic(items), {"kind": "contact", "id": 1})
	var p: Vector2 = radar.project(items[1]["local"])
	assert_dict(radar.item_at(p)).is_equal({"kind": "contact", "id": 1})
	radar.set_picture(_pic(items), {})
	assert_dict(radar.item_at(p)).is_equal({"kind": "contact", "id": 2})


# FT: FT-STN-003
func test_chip_is_clickable() -> void:
	var items: Array[Dictionary] = [_it("contact", 5, "H5", "H", Vector3(0, 0, -3000))]
	radar.set_picture(_pic(items), {})
	# A point on the chip text, right of the blip and outside the blip's hit radius.
	var p: Vector2 = radar.project(items[0]["local"]) + Vector2(40, 0)
	assert_dict(radar.item_at(p)).is_equal({"kind": "contact", "id": 5})
	radar.chips = false
	assert_dict(radar.item_at(p)).is_empty()


# FT: FT-STN-003
# Callsigns of close blips don't print over each other (checkpoint render: Bravo, F4, H2).
func test_chips_of_close_blips_do_not_overlap() -> void:
	var items: Array[Dictionary] = [
		_it("contact", 2, "H2", "H", Vector3(0, 0, -3000)),
		_it("contact", 4, "F4", "F", Vector3(60, 0, -3010)),
		_it("mark", 1, "Bravo", "", Vector3(-60, 0, -2990)),
	]
	radar.set_picture(_pic(items), {})
	var rects: Array[Rect2] = []
	for e: Dictionary in radar._layout():
		rects.append(e["chip_rect"])
	assert_int(rects.size()).is_equal(3)
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			assert_bool(rects[i].intersects(rects[j])).is_false()


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
	radar.set_picture(_pic(items), {})
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
	radar.set_picture(_pic(items), {})
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
	radar.set_picture(_pic(items), {})
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
	radar.set_picture(_pic(items), {"kind": "contact", "id": 1})
	await await_idle_frame()
	# The strip narrows the disc; the point ping is never picked.
	assert_float(radar.disc_centre().x).is_equal_approx((600.0 - DiscRadar.STRIP_W) / 2.0, 0.01)
	assert_dict(radar.item_at(radar.project(items[2]["local"]))).is_empty()


# FT: FT-SPA-010
func test_centring_takes_the_minimum_image_on_a_rolled_ship() -> void:
	# A 20 km cube; the ship yawed, pitched and rolled. Bravo sits 9.7 km to world -X, H2
	# 9.6 km to world +X: through the seam H2 is 700 m to world -X of Bravo (D124).
	var v: NetViewState = NetViewState.new(NetCodec.period_units(20000.0))
	v.tick = 10
	var rot: Quaternion = Quaternion.from_euler(Vector3(0.2, 0.5, 0.4))
	v.kin = {"pos": Vector3i.ZERO, "rot": rot}
	var pic: ContactPicture = ContactPicture.new()
	pic.interp.push(v, 0)
	var bravo: Vector3 = Vector3(-9700, 0, 0)
	var h2: Vector3 = Vector3(9600, 0, 0)
	pic.items = [
		{"kind": "mark", "id": 1, "label": "Bravo", "world": bravo, "local": rot.inverse() * bravo},
		{"kind": "contact", "id": 2, "label": "H2", "world": h2, "local": rot.inverse() * h2},
	]
	radar.set_picture(pic, {})
	var plain: Vector2 = radar.project(rot.inverse() * Vector3(-700, 0, 0))
	radar.centre = {"kind": "mark", "id": 1}
	assert_bool(radar.is_beyond(pic.items[1]["local"])).is_false()
	assert_vector(radar.project(pic.items[1]["local"])).is_equal_approx(plain, Vector2.ONE * 0.01)
	assert_vector(radar.project(pic.items[0]["local"])).is_equal_approx(
		radar.disc_centre(), Vector2.ONE * 0.01
	)


# FT: FT-SPA-024, FT-SPA-025
# Fixed range steps of 2, 10 and 50 km, in and out and stopping at the ends; a contact past
# the scale is an arrow on the rim at its bearing, whichever step; the selected stem is
# drawn last, on top.
func test_range_steps_rim_arrows_and_the_selected_stem_on_top() -> void:
	assert_array(DiscRadar.RANGES_M).is_equal([2000.0, 10000.0, 50000.0])
	var items: Array[Dictionary] = [
		_it("contact", 1, "H1", "H", Vector3(3000, 0, 0)),
		_it("contact", 2, "H2", "H", Vector3(0, 0, -30000)),
		_it("contact", 3, "H3", "H", Vector3(500, 100, -500)),
	]
	radar.set_picture(_pic(items), {"kind": "contact", "id": 1})
	var expect: Array = [
		# [range index, H1 past the scale, H2 past the scale]
		[0, true, true],
		[1, false, true],
		[2, false, false],
	]
	for row: Array in expect:
		radar.range_index = row[0]
		assert_bool(radar.is_beyond(items[0]["local"])).is_equal(row[1])
		assert_bool(radar.is_beyond(items[1]["local"])).is_equal(row[2])
	# Zoom out stops at 50 km, in at 2 km.
	radar.range_index = 1
	radar.zoom(1)
	radar.zoom(1)
	assert_int(radar.range_index).is_equal(2)
	radar.zoom(-1)
	radar.zoom(-1)
	radar.zoom(-1)
	assert_int(radar.range_index).is_equal(0)
	# At 2 km H2 (dead ahead) is an arrow on the rim straight above the centre; H1 (3 o'clock)
	# on the rim to its right.
	var c: Vector2 = radar.disc_centre()
	var layout: Array[Dictionary] = radar._layout()
	var h2: Dictionary = layout[1]
	assert_bool(h2["beyond"]).is_true()
	assert_float((h2["pos"] as Vector2).distance_to(radar.project(Vector3(0, 0, -2000)))).is_less(
		0.5
	)
	assert_float((h2["pos"] as Vector2).x).is_equal_approx(c.x, 0.5)
	assert_float((layout[0]["pos"] as Vector2).y).is_equal_approx(c.y, 0.5)
	assert_float((layout[0]["pos"] as Vector2).x).is_greater(c.x)


# FT: FT-STN-003
# A phone's rail radar (160 px, #28): callsign-only chips clear of the clock numbers, the
# range label, the own ship and each other; the selected item keeps its chip.
func test_small_radar_chips_are_callsigns_clear_of_everything() -> void:
	radar.size = Vector2(160, 110)
	var items: Array[Dictionary] = [
		_it("contact", 3, "U3", "U", Vector3(-400, 2500, -8000)),
		_it("contact", 2, "H2", "H", Vector3(1500, 300, -1500)),
		_it("contact", 4, "F4", "F", Vector3(2000, 0, 400)),
		_it("mark", 1, "Bravo", "", Vector3(-1200, -200, 500)),
	]
	radar.set_picture(_pic(items), {"kind": "contact", "id": 2})
	assert_bool(radar.small()).is_true()
	var font: Font = radar.get_theme_default_font()
	var blocked: Array = radar._numerals(font, radar.disc_centre(), 10000.0).values()
	blocked.append(radar._range_rect())
	var placed: Array[Rect2] = []
	var selected_chip: String = ""
	for e: Dictionary in radar._layout():
		if e["chip"] == "":
			continue
		assert_str(e["chip"]).is_equal(e["item"]["label"])
		var r: Rect2 = e["chip_rect"]
		assert_bool(Rect2(Vector2.ZERO, radar.size).encloses(r)).is_true()
		for o: Rect2 in blocked + placed:
			assert_bool(o.intersects(r)).is_false()
		placed.append(r)
		if e["item"]["id"] == 2 and e["item"]["kind"] == "contact":
			selected_chip = e["chip"]
	assert_str(selected_chip).is_equal("H2")


# FT: FT-STN-003
# A tablet or desktop radar keeps its full chips (clock and range band).
func test_large_radar_keeps_full_chips() -> void:
	radar.set_picture(_pic([_it("contact", 2, "H2", "H", Vector3(1500, 300, -1500))]), {})
	assert_bool(radar.small()).is_false()
	assert_str(radar._layout()[0]["chip"]).contains(ChipText.SEP)


# FT: FT-STN-002
# A chip never sits over a clock number: it takes the nearest free spot beside its blip.
func test_a_chip_moves_off_a_clock_number() -> void:
	var number: Rect2 = Rect2(Vector2(100, 20), Vector2(14, 14))
	var entries: Array[Dictionary] = [
		{
			"chip": "U3",
			"chip_rect": Rect2(Vector2(104, 18), Vector2(60, 16)),
			"pos": Vector2(94, 26),
		}
	]
	DiscRadar._declutter(entries, [number], Rect2(0, 0, 300, 200))
	var moved: Rect2 = entries[0]["chip_rect"]
	assert_bool(moved.intersects(number)).is_false()
	# Still beside the blip, not a line away.
	assert_float(moved.get_center().distance_to(Vector2(94, 26))).is_less(80.0)
	# Without a blip or a free spot it drops below the number.
	entries = [{"chip": "U3", "chip_rect": Rect2(Vector2(104, 18), Vector2(60, 16))}]
	DiscRadar._declutter(entries, [number])
	assert_float((entries[0]["chip_rect"] as Rect2).position.y).is_equal(number.end.y)


# FT: FT-STN-003
# Each chip stays beside its own blip (never farther than a line or two), clear of every
# blip, the own ship and the other chips, and inside the disc when a spot there is free
# (the 150 % checkpoint: H2 and F4 crossed the rim, Bravo floated 60 px away).
func test_chips_sit_next_to_their_blip_inside_the_disc() -> void:
	radar.size = Vector2(900, 560)
	var items: Array[Dictionary] = [
		_it("contact", 2, "H2", "H", Vector3(0, 0, -3000)),
		_it("contact", 4, "F4", "F", Vector3(60, 0, -3010)),
		_it("mark", 1, "Bravo", "", Vector3(-60, 0, -2990)),
		_it("contact", 3, "U3", "U", Vector3(-400, 2500, -8000)),
	]
	radar.set_picture(_pic(items), {})
	var c: Vector2 = radar.disc_centre()
	var rim: float = radar.disc_radius()
	var ry: float = rim * sin(deg_to_rad(radar.tilt_deg))
	var layout: Array[Dictionary] = radar._layout()
	for e: Dictionary in layout:
		var r: Rect2 = e["chip_rect"]
		assert_float(r.get_center().distance_to(e["pos"])).is_less(90.0)
		assert_bool(r.intersects(radar._own_box())).is_false()
		for o: Dictionary in layout:
			var box: Rect2 = Rect2((o["pos"] as Vector2) - Vector2(6, 6), Vector2(12, 12))
			assert_bool(box.intersects(r)).is_false()
		# (U3 floats above the disc, so its chip does too.)
		if e["item"]["label"] != "U3":
			var inside: bool = DiscRadar._in_ellipse(
				Rect2(c - Vector2(rim, ry), Vector2(rim, ry) * 2.0), r
			)
			assert_bool(inside).is_true()


# FT: FT-STN-013
func test_blips_keep_six_physical_pixels_below_full_scale() -> void:
	add_child(radar)
	var win: Window = radar.get_window()
	var was: float = win.content_scale_factor
	win.content_scale_factor = 0.75
	assert_float(radar.blip_r() * 0.75).is_equal_approx(DiscRadar.BLIP_R, 0.001)
	win.content_scale_factor = 1.5
	assert_float(radar.blip_r()).is_equal(DiscRadar.BLIP_R)
	win.content_scale_factor = was
	remove_child(radar)
