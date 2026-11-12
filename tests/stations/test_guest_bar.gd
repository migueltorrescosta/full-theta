extends GdUnitTestSuite
## A guest's Help out and Back to watching (GuestBar, #40 D10, gp-04): shown only to the
## session the server marks a guest, listing the free light stations of the watched ship; a
## tap picks through the normal Pick.


func before() -> void:
	I18n.apply("en")


func _bar(seat: String, guest: bool, others: Array = [], bots: Array = []) -> GuestBar:
	var ctx: StationContext = StationFixture.context(seat)
	var seats: Array = [
		{"seat": seat, "name": "Ana", "session": StationFixture.SESSION, "guest": guest}
	]
	seats.append_array(others)
	ctx.crew.lobby[StationFixture.SHIP]["seats"] = seats
	ctx.crew.lobby[StationFixture.SHIP]["bots"] = bots
	var b: GuestBar = auto_free(GuestBar.new())
	add_child(b)
	b.setup(ctx)
	return b


func _buttons(b: GuestBar) -> Array:
	return b.find_children("*", "Button", true, false).map(func(n: Node) -> String: return n.name)


# FT: FT-NET-049
# A watching guest sees the light stations nobody holds (a fill bot gives way, a stand-in
# doesn't); a tap picks one through Pick.
func test_a_watching_guest_sees_the_free_light_stations() -> void:
	var others: Array = [{"seat": "ops", "name": "Bo", "session": 8}]
	var bots: Array = [{"seat": "science", "for": "Cy"}, {"seat": "engineering", "for": ""}]
	var b: GuestBar = _bar(StationCatalogue.VIEWER, true, others, bots)
	assert_bool(b.visible).is_true()
	assert_str((b.find_child("HelpOut", true, false) as Label).text).is_equal("Help out:")
	assert_array(_buttons(b)).is_equal(["Take_engineering"])
	(b.find_child("Take_engineering", true, false) as Button).pressed.emit()
	var sent: Array = StationFixture.sent(b.ctx).of("pick")[-1][1]
	assert_array(sent).is_equal([StationFixture.SHIP, "engineering"])


# FT: FT-NET-049
# Nothing shows for a viewer who is no guest, nor for a guest with no station free.
func test_hidden_without_a_use() -> void:
	assert_bool(_bar(StationCatalogue.VIEWER, false).visible).is_false()
	var full: Array = [
		{"seat": "systems", "name": "Bo", "session": 8}, {"seat": "ops", "name": "Cy", "session": 9}
	]
	assert_bool(_bar(StationCatalogue.VIEWER, true, full).visible).is_false()
	assert_bool(_bar("helm", false).visible).is_false()


# FT: FT-NET-049
# A guest seated at a light station gets Back to watching, which picks the Viewer again.
func test_a_seated_guest_goes_back_to_watching() -> void:
	var b: GuestBar = _bar("relay", true)
	assert_array(_buttons(b)).is_equal(["BackToWatching"])
	var back: Button = b.find_child("BackToWatching", true, false) as Button
	assert_str(back.text).is_equal("Back to watching")
	back.pressed.emit()
	var sent: Array = StationFixture.sent(b.ctx).of("pick")[-1][1]
	assert_array(sent).is_equal([StationFixture.SHIP, StationCatalogue.VIEWER])
