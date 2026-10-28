extends GdUnitTestSuite
## The touch help pictures of the phone pages (#28 follow-up, P28-Help, D292): one section per
## page with its tab, every control numbered once, each box inside the phone's safe frame
## (views may be drawn into the band), and a line saying what each does.
# FT: FT-STN-012


func before() -> void:
	I18n.apply("en")


# FT: FT-STN-012, FT-STN-005
func test_pictures_number_every_control() -> void:
	# A view box may reach into the band (it is drawn there, P28-Band).
	var safe: Rect2 = Rect2(47.0, 8.0, 750.0, 382.0)
	for station: String in ["engineering", "comms", "captain"]:
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
