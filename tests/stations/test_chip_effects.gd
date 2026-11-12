extends GdUnitTestSuite
## C5: a request chip states what accepting does, one nobody answers says it lapsed in the
## toast queue, a share lights its sender's button, and the receiving station gets a note in
## its toast queue while the shared data is live (ux-14).
# FT: FT-PAIR-013, FT-PAIR-007


func before() -> void:
	I18n.apply("en")


func _chip(id: int, left: float) -> Dictionary:
	return {"id": id, "text": "Helm: Boost", "left": left, "effect": ChipLapse.effect("boost")}


func _texts(chips: RequestChips) -> Array:
	var out: Array = []
	for row: Node in chips.get_children():
		for l: Node in row.find_children("*", "Label", true, false):
			out.append((l as Label).text)
	return out


func test_the_boost_chip_states_its_effect() -> void:
	assert_str(ChipLapse.effect("boost")).is_equal("Engines to full pips for a while. Heats up.")
	assert_str(ChipLapse.effect("hold_fire")).is_empty()
	var chips: RequestChips = auto_free(RequestChips.new())
	add_child(chips)
	chips.show_chips([_chip(4, 18.0)])
	assert_array(_texts(chips)).is_equal(
		["Helm: Boost · 18 s", "Engines to full pips for a while. Heats up."]
	)
	assert_int(chips.buttons(0).size()).is_equal(2)


func test_an_unanswered_chip_lapses_and_an_answered_one_does_not() -> void:
	var lapse: ChipLapse = ChipLapse.new()
	assert_array(lapse.update([_chip(4, 2.0)])).is_empty()
	assert_array(lapse.update([_chip(4, 1.0)])).is_empty()
	# Gone with a second left: it ran out, said once.
	assert_array(lapse.update([])).is_equal(["Helm: Boost lapsed"])
	assert_array(lapse.update([])).is_empty()
	# Gone with plenty of time left: someone answered it, no note.
	lapse.update([_chip(5, 15.0)])
	assert_array(lapse.update([])).is_empty()


# ux-14: the lapse note and a partner's share are notes in the one toast queue, above info
# toasts; the share's seconds count down in place.
func test_lapse_and_share_notes_go_to_the_toast_queue() -> void:
	var ctx: StationContext = StationFixture.context("helm")
	var s: StationScreen = auto_free(StationScreen.new())
	s.panel_factory = func(_st: String) -> StationPanel: return StationPanel.new()
	s.setup(ctx)
	add_child(s)
	s.toasts.push("Info", "info", ctx.now_ms())
	ctx.crew.shares[&"routes"] = ctx.now_ms() + 12000
	s._process(0.0)
	assert_str(s.toasts.shown()).is_equal("Routes on Helm from Relay · 12 s +1")
	StationFixture.clock(ctx).ms += 2000
	s._process(0.0)
	assert_array(s.toasts.texts()).contains(["Routes on Helm from Relay · 10 s"])
	assert_int(s.toasts.texts().size()).is_equal(2)
	# Nothing else shows the share: no chip strip line, no request row.
	assert_bool(s.chip_strip.visible).is_false()


func test_the_receiver_sees_a_line_while_shared_data_is_live() -> void:
	# Relay shares routes to Helm: Helm's screen gets the line, Relay's own does not.
	var left: Dictionary = {&"routes": 12.0}
	var helm: Array[String] = ["helm"]
	var relay: Array[String] = ["relay"]
	assert_array(ShareBar.incoming_lines(helm, left)).is_equal(["Routes on Helm from Relay · 12 s"])
	assert_array(ShareBar.incoming_lines(relay, left)).is_empty()
	assert_array(ShareBar.incoming_lines(helm, {&"routes": 0.0})).is_empty()


func test_a_live_share_lights_the_senders_button() -> void:
	var bar: ShareBar = auto_free(ShareBar.new())
	add_child(bar)
	var shown: Array[StringName] = [&"routes"]
	bar.show_features(shown, {})
	var b: Button = bar.get_child(0)
	assert_str(b.text).is_equal("Share: Routes on Helm")
	assert_str(b.theme_type_variation).is_empty()
	bar.show_features(shown, {&"routes": 20.0})
	assert_str(b.text).is_equal("Shared: Routes on Helm · 20 s")
	assert_str(b.theme_type_variation).is_equal("RailAccentButton")
