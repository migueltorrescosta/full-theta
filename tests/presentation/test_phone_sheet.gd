extends GdUnitTestSuite
## PhoneSheet (R05-9): the phone placement the pause, outcome, vote and handover overlays
## share. A sheet fits the safe tap area cut to the given bounds, in its parent's
## coordinates; `unfit` puts it back as a centred card; `follow_viewport` connects once.
# FT: FT-STN-005


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1


func _host(size: Vector2i) -> Control:
	var vp: SubViewport = auto_free(SubViewport.new())
	vp.size = size
	add_child(vp)
	var parent: Control = Control.new()
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(parent)
	var sheet: PanelContainer = PanelContainer.new()
	parent.add_child(sheet)
	return sheet


func test_is_phone_follows_the_layout_kind() -> void:
	var sheet: Control = _host(Vector2i(844, 390))
	LayoutMode.forced = LayoutMode.Kind.PHONE
	assert_bool(PhoneSheet.is_phone(sheet)).is_true()
	LayoutMode.forced = LayoutMode.Kind.DESKTOP
	assert_bool(PhoneSheet.is_phone(sheet)).is_false()


func test_fit_fills_the_tap_rect_between_the_bounds() -> void:
	var sheet: Control = _host(Vector2i(844, 390))
	PhoneSheet.fit(sheet)
	var r: Rect2 = SafeArea.tap_rect(sheet)
	assert_vector(sheet.position).is_equal(r.position)
	assert_vector(sheet.size).is_equal(r.size)
	assert_vector(sheet.custom_minimum_size).is_equal(r.size)
	PhoneSheet.fit(sheet, 60.0, 300.0)
	assert_float(sheet.position.y).is_equal(maxf(r.position.y, 60.0))
	assert_float(sheet.size.y).is_equal(minf(r.end.y, 300.0) - maxf(r.position.y, 60.0))
	PhoneSheet.unfit(sheet)
	assert_vector(sheet.custom_minimum_size).is_equal(Vector2.ZERO)
	assert_int(sheet.grow_vertical).is_equal(Control.GROW_DIRECTION_BOTH)
	assert_float(sheet.anchor_left).is_equal(0.5)


func test_follow_viewport_connects_once() -> void:
	var sheet: Control = _host(Vector2i(844, 390))
	var place: Callable = sheet.reset_size
	assert_bool(PhoneSheet.follow_viewport(sheet, place, true)).is_true()
	assert_bool(PhoneSheet.follow_viewport(sheet, place, true)).is_false()
	assert_bool(sheet.get_viewport().size_changed.is_connected(place)).is_true()
	assert_bool(sheet.minimum_size_changed.is_connected(place)).is_true()
