extends GdUnitTestSuite
## The dock market in a real run world (D86, FT-MIS-036, #38 D7): docking at Kestrel Yard
## puts the Kappa market's OFFER card on the ship's board, so the credits can be spent; it
## lapses when the ship undocks.


func _docked() -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.world.kin.place(0, CubePoint.plus(f.world.sites.point(0), Vector3(500.0, 0.0, 0.0)))
	f.world.kin.vel[0] = Vector3.ZERO
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	assert_bool(f.send(dock)).is_true()
	f.run(2)
	return f


func _market_card(f: ScenarioFixture, ship: int = 0) -> int:
	for c: CardInfo in f.api.cards_of(ship):
		if c.kind == CardSpec.Kind.OFFER and c.state == CardInfo.State.OPEN:
			return c.id
	return -1


# FT: FT-MIS-036, FT-COM-004
func test_docking_posts_the_market_offer_and_the_ship_can_buy() -> void:
	var f: ScenarioFixture = _docked()
	var card: int = _market_card(f)
	assert_int(card).is_greater_equal(0)
	assert_int(f.world.story.site[card]).is_equal(0)
	var credits: int = Economy.credits(f.world, 0)
	var parts: int = Economy.held(f.world, 0, &"parts")
	var buy: TradeCommand = TradeCommand.new()
	buy.card = card
	buy.item = &"parts"
	buy.qty = 1
	assert_bool(f.send(buy)).is_true()
	assert_int(Economy.credits(f.world, 0)).is_equal(credits - 25)
	assert_int(Economy.held(f.world, 0, &"parts")).is_equal(parts + 1)


# FT: FT-MIS-036
func test_the_offer_lapses_on_undocking_and_a_new_dock_posts_a_new_one() -> void:
	var f: ScenarioFixture = _docked()
	var first: int = _market_card(f)
	assert_bool(f.send(UndockCommand.new())).is_true()
	f.run(2)
	assert_int(f.card_state(first)).is_equal(CardInfo.State.EXPIRED)
	assert_int(_market_card(f)).is_equal(-1)
	var buy: TradeCommand = TradeCommand.new()
	buy.card = first
	buy.item = &"parts"
	assert_bool(f.send(buy)).is_false()
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	assert_bool(f.send(dock)).is_true()
	f.run(2)
	assert_int(_market_card(f)).is_greater(first)


# FT: FT-MIS-036
# A dock at a site with no market posts nothing.
func test_a_dock_without_a_market_posts_no_offer() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.world.site_markets.clear()
	f.world.kin.place(0, CubePoint.plus(f.world.sites.point(0), Vector3(500.0, 0.0, 0.0)))
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	assert_bool(f.send(dock)).is_true()
	f.run(2)
	assert_int(f.world.story.size()).is_equal(0)
