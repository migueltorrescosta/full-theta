extends GdUnitTestSuite
## The quiet gap's Ready card (gp-07, GapBanner): shown only to a voter while the gap is on,
## with the time left and the Ready count; its toggle sends SkipGap.


func after_test() -> void:
	I18n.apply("en")


func _banner(voters: Array, ready: Array) -> GapBanner:
	var ctx: StationContext = StationFixture.context("helm")
	var b: GapBanner = auto_free(GapBanner.new())
	add_child(b)
	b.setup(ctx)
	var gap: Dictionary = {
		"faction": 1,
		"ends_at": StationFixture.TICK + 90 * 60,
		"ready": ready,
		"voters": voters,
	}
	ctx.crew.handle_event({"type": NetProtocol.EVENT_GAP, "payload": gap}, StationFixture.NOW_MS)
	b.refresh()
	return b


# FT: FT-MIS-025
func test_a_voter_sees_the_time_left_and_the_ready_count() -> void:
	I18n.apply("en")
	var b: GapBanner = _banner([StationFixture.SESSION, 9], [9])
	assert_bool(b.visible).is_true()
	var text: Label = b.find_children("*", "Label", true, false)[0]
	assert_str(text.text).contains("1:30").contains("1 of 2")
	var button: Button = b.find_child("Ready", true, false)
	assert_bool(button.button_pressed).is_false()
	button.button_pressed = true
	assert_array(StationFixture.sent(b.ctx).of("skip_gap")).is_equal([["skip_gap", [true]]])


# FT: FT-MIS-025
# AVOID BAD PATHS: a viewer (not a voter) never sees it; it goes when the gap ends.
func test_a_non_voter_never_sees_it_and_it_goes_with_the_gap() -> void:
	assert_bool(_banner([9], []).visible).is_false()
	var b: GapBanner = _banner([StationFixture.SESSION], [StationFixture.SESSION])
	assert_bool((b.find_child("Ready", true, false) as Button).button_pressed).is_true()
	var over: Dictionary = {"faction": 1, "ends_at": 0, "ready": [], "voters": []}
	b.ctx.crew.handle_event({"type": NetProtocol.EVENT_GAP, "payload": over}, 0)
	b.refresh()
	assert_bool(b.visible).is_false()
