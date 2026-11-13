extends GdUnitTestSuite
## The paid co-op relaunch on the relaunch prompt (gp-10, #38 D4 amending D259): the prompt
## says the price; a purse short of it shows the button disabled with price and purse (w-7v6);
## a side with no relaunch left by policy gets no prompt.


func before() -> void:
	I18n.apply("en")


func _ctx() -> StationContext:
	var ctx: StationContext = StationFixture.context("helm")
	StationFixture.fleet(ctx, "coop", [StationFixture.SHIP_NAME, "Heron"], [0, 0], true)
	return ctx


func _event(ctx: StationContext, type: String, p: Dictionary) -> void:
	assert_str(FleetMessages.check(type, p)).is_empty()
	ctx.crew.handle_event({"type": type, "payload": p}, StationFixture.NOW_MS)


func _prompt(ctx: StationContext) -> VotePrompt:
	var p: VotePrompt = auto_free(VotePrompt.new())
	p.setup(ctx, VotePrompt.Kind.RELAUNCH)
	add_child(p)
	return p


# FT: FT-MIS-051
func test_the_relaunch_prompt_shows_its_price() -> void:
	var ctx: StationContext = _ctx()
	var p: VotePrompt = _prompt(ctx)
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", 1, 800))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(0, 1))
	assert_bool(p.visible).is_true()
	var title: Label = p.find_child("Title", true, false)
	assert_str(title.text).is_equal("Kestrel is out. 1 life left. Costs 800 credits.")


# FT: FT-MIS-051
func test_a_side_with_no_relaunch_left_shows_no_prompt() -> void:
	var ctx: StationContext = _ctx()
	var p: VotePrompt = _prompt(ctx)
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", 0, 800, 900))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(0, 1))
	assert_bool(p.visible).is_false()


# FT: FT-MIS-051
func test_a_short_purse_shows_the_relaunch_disabled_with_price_and_purse() -> void:
	var ctx: StationContext = _ctx()
	var p: VotePrompt = _prompt(ctx)
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", 1, 800, 500))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(0, 1))
	assert_bool(p.visible).is_true()
	var b: Button = p.find_child("Relaunch", true, false)
	assert_bool(b.disabled).is_true()
	assert_str(b.text).is_equal("Relaunch (800, you have 500)")


# FT: FT-MIS-051
func test_an_affordable_purse_keeps_the_button_enabled() -> void:
	var ctx: StationContext = _ctx()
	var p: VotePrompt = _prompt(ctx)
	_event(ctx, NetProtocol.EVENT_ELIMINATED, FleetMessages.eliminated(0, "destroyed", 1, 800, 800))
	_event(ctx, NetProtocol.EVENT_HANDOVER, FleetMessages.handover(0, 1))
	var b: Button = p.find_child("Relaunch", true, false)
	assert_bool(b.disabled).is_false()
	assert_str(b.text).is_equal("Relaunch")
