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


# FT: FT-NET-050
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


# FT: FT-NET-050
# Nothing shows for a viewer who is no guest, nor for a guest with no station free.
func test_hidden_without_a_use() -> void:
	assert_bool(_bar(StationCatalogue.VIEWER, false).visible).is_false()
	var full: Array = [
		{"seat": "systems", "name": "Bo", "session": 8}, {"seat": "ops", "name": "Cy", "session": 9}
	]
	assert_bool(_bar(StationCatalogue.VIEWER, true, full).visible).is_false()
	assert_bool(_bar("helm", false).visible).is_false()


# FT: FT-NET-050
# A guest seated at a light station gets Back to watching, which picks the Viewer again.
func test_a_seated_guest_goes_back_to_watching() -> void:
	var b: GuestBar = _bar("relay", true)
	assert_array(_buttons(b)).is_equal(["BackToWatching"])
	var back: Button = b.find_child("BackToWatching", true, false) as Button
	assert_str(back.text).is_equal("Back to watching")
	back.pressed.emit()
	var sent: Array = StationFixture.sent(b.ctx).of("pick")[-1][1]
	assert_array(sent).is_equal([StationFixture.SHIP, StationCatalogue.VIEWER])


## A station screen for `seat` after the player's ship 1 was handed over to ship 0.
func _screen(seat: String) -> StationScreen:
	var ctx: StationContext = StationFixture.context(seat)
	StationFixture.fleet(ctx, "coop", [StationFixture.SHIP_NAME, "Heron"], [], true)
	ctx.crew.handle_event({"type": "handover", "payload": FleetMessages.handover(1, 0)}, 0)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	return s


# FT: FT-NET-050, FT-MIS-030
# The top bar says "Watching Kestrel" while the handed-over player watches; seated at one of
# its stations as a guest, the bar names the ship as their own.
func test_a_seated_guest_is_not_watching() -> void:
	assert_str(_screen(StationCatalogue.VIEWER).top_bar.watching).is_equal(StationFixture.SHIP_NAME)
	assert_str(_screen("relay").top_bar.watching).is_empty()


# FT: FT-NET-050
# While the handover notice shows where the bar would go (a tablet), the bar sits under it,
# and moves back up once the notice hides.
func test_the_bar_keeps_clear_of_the_handover_notice() -> void:
	LayoutMode.forced = LayoutMode.Kind.TOUCH
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1024, 768)
	add_child(host)
	var notice: Control = Control.new()
	notice.name = "HandoverNotice"
	notice.position = Vector2(340, 64)
	notice.size = Vector2(500, 84)
	host.add_child(notice)
	var ctx: StationContext = StationFixture.context(StationCatalogue.VIEWER)
	ctx.crew.lobby[StationFixture.SHIP]["seats"] = [
		{"seat": "viewer", "name": "Ana", "session": StationFixture.SESSION, "guest": true}
	]
	var b: GuestBar = GuestBar.new()
	host.add_child(b)
	b.setup(ctx)
	await get_tree().process_frame
	assert_float(b.position.y).is_greater_equal(notice.get_rect().end.y)
	notice.visible = false
	await get_tree().process_frame
	assert_float(b.position.y).is_equal(GuestBar.DESK_TOP)
	LayoutMode.forced = -1
