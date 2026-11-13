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


func _offers(n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append({"site": i, "name_key": "site.vesper_beacon", "risk": i % 3, "reward": 1})
	return out


func _picker_banner(pickers: Array, offers: Array, pick: int) -> GapBanner:
	var b: GapBanner = _banner([StationFixture.SESSION, 9], [])
	var gap: Dictionary = b.ctx.crew.gap.duplicate()
	gap.merge({"offers": offers, "pick": pick, "pickers": pickers}, true)
	b.ctx.crew.handle_event({"type": NetProtocol.EVENT_GAP, "payload": gap}, 0)
	b.refresh()
	return b


# FT: FT-MIS-025
# w-bzx: a picker with 3 offers sees one toggle per offer (name, then the tags), the current
# pick pressed; tapping another sends SitePick and closes them on a phone, "Next" naming it.
func test_a_picker_sees_the_offers_and_taps_one() -> void:
	I18n.apply("en")
	var b: GapBanner = _picker_banner([StationFixture.SESSION], _offers(3), 1)
	# Opened, as a tap on "Next" does on a phone (desktop and tablet always show the offers).
	b.expanded = true
	b.refresh()
	var offer: Button = b.find_child("Offer2", true, false)
	assert_bool(offer.is_visible_in_tree()).is_true()
	assert_str(offer.text).contains("\n").contains("High risk · Fair pay")
	assert_bool((b.find_child("Offer1", true, false) as Button).button_pressed).is_true()
	offer.button_pressed = true
	assert_array(StationFixture.sent(b.ctx).of("site_pick")).is_equal([["site_pick", [2]]])
	b.refresh()
	assert_bool(b.expanded).is_false()
	assert_str((b.find_child("Next", true, false) as Button).text).is_equal("Next: Vesper Beacon")
	assert_bool((b.find_child("Offer1", true, false) as Button).button_pressed).is_false()


# FT: FT-MIS-025
# AVOID BAD PATHS: a voter who isn't a picker, or a picker with one offer, sees no choice.
func test_no_choice_for_a_non_picker_or_a_single_offer() -> void:
	for b: GapBanner in [
		_picker_banner([9], _offers(3), 0), _picker_banner([StationFixture.SESSION], _offers(1), 0)
	]:
		assert_bool(b.visible).is_true()
		var offer: Button = b.find_child("Offer0", true, false)
		assert_bool(offer == null or not offer.is_visible_in_tree()).is_true()
		assert_bool((b.find_child("Next", true, false) as Button).is_visible_in_tree()).is_false()


# FT: FT-MIS-025
# New offers (a new gap) rebuild the toggles in a fresh group and close them again: the pick
# pressed is the new one, and "Next" names its site, never a stale toggle's.
func test_new_offers_rebuild_the_choice() -> void:
	I18n.apply("en")
	var b: GapBanner = _picker_banner([StationFixture.SESSION], _offers(3), 1)
	b.expanded = true
	b.refresh()
	(b.find_child("Offer2", true, false) as Button).button_pressed = true
	b.expanded = true
	var fresh: Array = [
		{"site": 5, "name_key": "site.pale_drift", "risk": 0, "reward": 1},
		{"site": 6, "name_key": "site.cinder_field", "risk": 2, "reward": 2},
	]
	var gap: Dictionary = b.ctx.crew.gap.duplicate()
	gap.merge({"offers": fresh, "pick": 0}, true)
	b.ctx.crew.handle_event({"type": NetProtocol.EVENT_GAP, "payload": gap}, 0)
	b.refresh()
	assert_bool(b.expanded).is_false()
	assert_bool((b.find_child("Offer0", true, false) as Button).button_pressed).is_true()
	assert_bool((b.find_child("Offer1", true, false) as Button).button_pressed).is_false()
	assert_str((b.find_child("Next", true, false) as Button).text).is_equal("Next: Pale Drift")
