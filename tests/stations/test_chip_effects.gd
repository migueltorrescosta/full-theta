extends GdUnitTestSuite
## C5: a request chip states what accepting does, one nobody answers lapses visibly in its
## own place, a share lights its sender's button, and the receiving station sees a line while
## the shared data is live.
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
	chips.show_chips([_chip(4, 18.0)], [], 0)
	assert_array(_texts(chips)).is_equal(
		["Helm: Boost · 18 s", "Engines to full pips for a while. Heats up."]
	)
	assert_int(chips.buttons(0).size()).is_equal(2)


func test_an_unanswered_chip_lapses_in_view_and_an_answered_one_does_not() -> void:
	var chips: RequestChips = auto_free(RequestChips.new())
	add_child(chips)
	chips.show_chips([_chip(4, 2.0)], [], 0)
	chips.show_chips([_chip(4, 1.0)], [], 1000)
	# Gone with a second left: it ran out.
	chips.show_chips([], [], 2000)
	assert_bool(chips.visible).is_true()
	assert_array(_texts(chips)).is_equal(["Helm: Boost lapsed"])
	assert_int(chips.buttons(0).size()).is_equal(0)
	# The note goes after a few seconds.
	chips.show_chips([], [], 2000 + ChipLapse.SHOW_MS + 1)
	assert_bool(chips.visible).is_false()
	# Gone with plenty of time left: someone answered it, no note.
	chips.show_chips([_chip(5, 15.0)], [], 10000)
	chips.show_chips([], [], 11000)
	assert_bool(chips.visible).is_false()


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
