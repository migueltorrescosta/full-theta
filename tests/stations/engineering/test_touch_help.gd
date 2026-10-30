extends GdUnitTestSuite
## The touch help pictures of the phone pages (#28 follow-up, P28-Help, D292): one section per
## page with its tab, every control numbered once, each box inside the phone's safe frame
## (views may be drawn into the band), and a line saying what each does.
# FT: FT-STN-012


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	LayoutMode.forced = -1


# FT: FT-STN-012, FT-STN-005
func test_pictures_number_every_control() -> void:
	# A view box may reach into the band (it is drawn there, P28-Band).
	var safe: Rect2 = Rect2(47.0, 8.0, 750.0, 382.0)
	for station: String in [
		"engineering", "comms", "captain", "science", "relay", "weapons", "helm"
	]:
		var data: Array = TouchHelpPicture.help_of(station)
		if data.is_empty() and station == "comms":
			continue
		assert_array(data).override_failure_message(station).is_not_empty()
		var pic: TouchHelpPicture = auto_free(TouchHelpPicture.make(station))
		add_child(pic)
		var n: int = 0
		for p: Dictionary in data:
			assert_str(str(p["page"])).is_not_empty()
			for b: Array in p["boxes"]:
				var r: Rect2 = b[0]
				(
					assert_bool(safe.encloses(r))
					. override_failure_message("%s %s" % [station, b])
					. is_true()
				)
				assert_str(str(b[1])).is_not_empty()
				assert_str(str(b[2])).is_not_empty()
				n += 1
		assert_int(pic.count()).is_equal(n)
		var drawings: Array[Node] = pic.find_children("*", "Control", false, false).filter(
			func(c: Node) -> bool: return c is TouchHelpPicture.PageDrawing
		)
		assert_int(drawings.size()).is_equal(data.size())
	assert_object(TouchHelpPicture.make("viewer")).is_null()


# FT: FT-STN-012
# Engineering's first page shows its whole rail, each box where the rail button is.
func test_engineering_rail_boxes_match_the_rail() -> void:
	var power: Array = EngineeringPanel.touch_help()[0]["boxes"]
	for i: int in EngineeringPanel.TOUCH_ACTIONS.size():
		var a: Array = EngineeringPanel.TOUCH_ACTIONS[i]
		assert_str(str(power[i][1])).is_equal(TouchText.of(a[1], a[2]))
	var pages: Array = EngineeringPanel.touch_help()
	assert_int(pages.size()).is_equal(4)
	for p: int in range(1, pages.size()):
		assert_int((pages[p]["boxes"] as Array).size()).is_less(5)


# FT: FT-STN-012
# A station registers its picture at run time (TouchHelpPicture.register), over its panel's.
func test_a_registered_station_shows_its_picture() -> void:
	assert_object(TouchHelpPicture.make("viewer")).is_null()
	var help: Array = [{"page": "Fly", "boxes": [[Rect2(60, 80, 100, 48), "Go", "Go there"]]}]
	TouchHelpPicture.register("viewer", func() -> Array: return help)
	var pic: TouchHelpPicture = auto_free(TouchHelpPicture.make("viewer"))
	TouchHelpPicture.unregister("viewer")
	assert_int(pic.count()).is_equal(1)
	assert_object(TouchHelpPicture.make("viewer")).is_null()


# FT: FT-STN-011, FT-STN-012
# On a phone the Controls tab shows the touch picture of each shown station that has one,
# over the list; the filter adds every station's.
func test_a_phone_controls_tab_shows_the_touch_pictures() -> void:
	LayoutMode.forced = LayoutMode.Kind.PHONE
	var pane: ControlsPane = auto_free(ControlsPane.new())
	add_child(pane)
	pane.build(Bindings.new(), ["engineering", "viewer"], IntentTable.KBM, "")
	var pictures: Callable = func() -> Array:
		return pane.touch.get_children().filter(
			func(c: Node) -> bool: return c is TouchHelpPicture and not c.is_queued_for_deletion()
		)
	assert_bool(pane.touch.is_visible_in_tree()).is_true()
	assert_int(pictures.call().size()).is_equal(1)
	pane.set_all_stations(true)
	assert_int(pictures.call().size()).is_greater_equal(3)
	LayoutMode.forced = -1
	var desk: ControlsPane = auto_free(ControlsPane.new())
	desk.build(Bindings.new(), ["engineering"], IntentTable.KBM, "")
	assert_bool(desk.touch.visible).is_false()
	assert_int(desk.touch.get_child_count()).is_equal(0)
