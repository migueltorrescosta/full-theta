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


# FT: FT-MIS-052, FT-MIS-036
# Each dock offers MarketDef.modules_per_dock (2) of Kappa's 3 modules, drawn per dock; Comms'
# rows and the buy read the same pair, and the third is refused.
func test_a_dock_offers_two_of_the_three_modules() -> void:
	var f: ScenarioFixture = _docked()
	var w: SimWorld = f.world
	var card: int = _market_card(f)
	var m: MarketDef = w.markets[&"kappa"]
	assert_int(m.modules_per_dock).is_equal(2)
	var offered: Array[StringName] = Trade.modules_on_offer(w, card, m)
	assert_int(offered.size()).is_equal(2)
	var shown: Dictionary[StringName, bool] = {}
	for row: Dictionary in CommsSection.block(w, 0)["modules"]:
		shown[row["module"]] = true
	assert_array(shown.keys()).contains_exactly_in_any_order(offered)
	var missing: StringName = &""
	for key: StringName in m.modules:
		if not offered.has(key):
			missing = key
	Economy.add_credits(w, 0, 5000)
	assert_bool(_buy(f, card, missing)).is_false()
	var module: ModuleDef = w.module_defs[ModuleSystem.index_of(w, offered[0])]
	var before: int = Economy.credits(w, 0)
	assert_bool(_buy(f, card, offered[0])).is_true()
	for row: Dictionary in CommsSection.block(w, 0)["modules"]:
		assert_int(row["price"]).is_equal(
			Trade.module_price(w, f.world.module_defs[ModuleSystem.index_of(w, row["module"])])
		)
	assert_int(before - Economy.credits(w, 0)).is_less_equal(Trade.module_price(w, module))


func _buy(f: ScenarioFixture, card: int, key: StringName) -> bool:
	var module: ModuleDef = f.world.module_defs[ModuleSystem.index_of(f.world, key)]
	var buy: BuyModuleCommand = BuyModuleCommand.new()
	buy.card = card
	buy.module_key = key
	for r: int in f.world.modules.rows_of(0):
		if f.world.modules.slot_type[r] == module.slot_type:
			buy.slot = r - f.world.modules.row_of(0)
	return f.send(buy)
