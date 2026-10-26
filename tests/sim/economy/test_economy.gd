extends GdUnitTestSuite
## The economy: what a ship holds, what it earns from cards, and docked trading
## at a market through Comms. BLUE's corvette is ship 0, docked at the Kappa site with an
## OFFER card on its board.

const SITE: int = StoryFixture.SITE


## A docked world with the corvette, 5000 credits and Kappa's offer card; returns the card.
func _docked() -> Array:
	var w: SimWorld = StoryFixture.world()
	StoryFixture.spawn(w, TestDefs.corvette(), StoryFixture.BLUE)
	w.economy.credits[0] = 5000
	StoryFixture.dock(w, 0)
	var card: int = StoryFixture.post(w, 0, StoryFixture.card(StoryTable.Kind.OFFER, &"", SITE))
	return [w, card]


func _trade(w: SimWorld, card: int, item: StringName, qty: int, buy: bool = true) -> bool:
	var c: TradeCommand = TradeCommand.new()
	c.card = card
	c.item = item
	c.qty = qty
	c.buy = buy
	return StoryFixture.run(w, 0, c)


func _why(w: SimWorld) -> String:
	var refused: Array[SimEvent] = StoryFixture.events(w, &"trade_refused")
	return String(refused[-1].tag) if not refused.is_empty() else ""


# FT: FT-MIS-018
# The one read helper lists credits, propellant, parts, probes, ammunition by weapon (the
# unlimited beam is no stock) and reputation per faction.
func test_of_ship_reads_every_resource() -> void:
	var w: SimWorld = _docked()[0]
	Reputation.apply(w, StoryFixture.BLUE, StoryFixture.RED, 12.5)
	var e: Dictionary = Economy.of_ship(w, 0)
	assert_int(e["credits"]).is_equal(5000)
	assert_float(e["propellant"]).is_equal(w.defs[0].propellant_capacity)
	assert_int(e["parts"]).is_equal(20)
	assert_int(e["probes"]).is_equal(3)
	assert_dict(e["ammo"]).is_equal({&"m1_cannon": 400, &"m2_missile": 8, &"m2_torpedo": 3})
	assert_dict(e["reputation"]).is_equal({StoryFixture.RED: 12.5})


# FT: FT-MIS-021, FT-MIS-018
# A done card pays its reward and draws its reputation change; a failed one pays nothing
# and draws the failure change.
func test_earnings_from_cards() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	StoryFixture.spawn(w, TestDefs.raider(), StoryFixture.RED, Vector3(0.0, 0.0, -5000.0))
	var pay: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION)
	pay.reward_credits = 400
	pay.target = 1
	pay.rep_interaction = &"rep.complete_mission"
	var won: int = StoryFixture.post(w, 0, pay)
	var lost: int = StoryFixture.post(w, 0, pay)
	for card: int in [won, lost]:
		var accept: AcceptCardCommand = AcceptCardCommand.new()
		accept.card = card
		assert_bool(StoryFixture.run(w, 0, accept)).is_true()
	var done: CardResultCommand = CardResultCommand.new()
	done.card = won
	assert_bool(StoryFixture.run(w, 0, done)).is_true()
	assert_int(w.economy.credits[0]).is_equal(5400)
	assert_int(w.story.state[won]).is_equal(StoryTable.State.DONE)
	assert_float(w.reputation.value_of(StoryFixture.BLUE, StoryFixture.RED)).is_between(4.0, 12.0)
	var fail: CardResultCommand = CardResultCommand.new()
	fail.card = lost
	fail.success = false
	assert_bool(StoryFixture.run(w, 0, fail)).is_true()
	assert_int(w.economy.credits[0]).is_equal(5400)
	assert_int(w.story.state[lost]).is_equal(StoryTable.State.FAILED)
	assert_float(w.reputation.value_of(StoryFixture.BLUE, StoryFixture.RED)).is_less(12.0)
	assert_bool(StoryFixture.run(w, 0, done)).override_failure_message("settled twice").is_false()


# FT: FT-COM-004, FT-MIS-018
# Docked, Comms buys propellant, parts, probes and ammunition at the market's prices, up
# to its stock and the ship's room, and the goods land where they are used.
func test_docked_buying() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	var card: int = d[1]
	w.kin.propellant[0] = 5000.0
	assert_bool(_trade(w, card, &"propellant", 1000)).is_true()
	assert_float(w.kin.propellant[0]).is_equal(6000.0)
	assert_int(w.economy.credits[0]).is_equal(3000)
	assert_bool(_trade(w, card, &"parts", 5)).is_true()
	assert_int(w.damage.spare_parts[w.damage.hull_row(0)]).is_equal(25)
	assert_bool(_trade(w, card, &"probes", 2)).is_true()
	assert_int(w.relay.stock[0]).is_equal(5)
	w.mounts.ammo[0] = 100
	assert_bool(_trade(w, card, &"ammo:m1_cannon", 300)).is_true()
	assert_int(w.mounts.ammo[0]).is_equal(400)
	assert_int(w.economy.credits[0]).is_equal(5000 - 2000 - 125 - 240 - 300)
	var done: Array[SimEvent] = StoryFixture.events(w, &"trade_done")
	assert_int(done.size()).is_equal(4)
	assert_float(done[0].value).is_equal(-2000.0)
	assert_str(done[3].tag).is_equal("ammo:m1_cannon")


# FT: FT-COM-004
# A trade is refused, changing nothing, past the market's stock, the ship's room or its
# credits, for a good the ship doesn't use or the market doesn't price.
func test_buying_refusals() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	var card: int = d[1]
	assert_bool(_trade(w, card, &"parts", 21)).is_false()
	assert_str(_why(w)).is_equal("over_stock")
	assert_bool(_trade(w, card, &"propellant", 100)).is_false()
	assert_str(_why(w)).is_equal("no_room")
	assert_bool(_trade(w, card, &"ammo:m1_cannon", 1)).is_false()
	assert_str(_why(w)).is_equal("no_room")
	assert_bool(_trade(w, card, &"ammo:m1_raider_cannon", 1)).is_false()
	assert_str(_why(w)).is_equal("bad_item")
	assert_bool(_trade(w, card, &"ammo:m2_missile", 1)).is_false()
	assert_str(_why(w)).is_equal("no_price")
	assert_bool(_trade(w, card, &"parts", 0)).is_false()
	w.economy.credits[0] = 10
	assert_bool(_trade(w, card, &"parts", 1)).is_false()
	assert_str(_why(w)).is_equal("no_credits")
	assert_int(w.economy.credits[0]).is_equal(10)
	assert_int(w.damage.spare_parts[w.damage.hull_row(0)]).is_equal(20)


# FT: FT-COM-004, FT-MIS-036
# Trading needs the ship docked at the card's site; undocked, or at another site, it is
# refused.
func test_trading_needs_docking() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	var card: int = d[1]
	StoryFixture.dock(w, 0, 9)
	assert_bool(_trade(w, card, &"parts", 1)).is_false()
	assert_str(_why(w)).is_equal("not_docked")
	w.helm.docked_site[0] = -1
	assert_bool(_trade(w, card, &"parts", 1)).is_false()
	assert_str(_why(w)).is_equal("not_docked")
	StoryFixture.dock(w, 0)
	assert_bool(_trade(w, card, &"parts", 1)).is_true()
	w.story.state[card] = StoryTable.State.DECLINED
	assert_bool(_trade(w, card, &"parts", 1)).is_false()
	assert_str(_why(w)).is_equal("closed")


# FT: FT-COM-004, FT-MIS-018
# Selling pays the market's share of the price for what the ship holds.
func test_selling() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	var card: int = d[1]
	assert_bool(_trade(w, card, &"parts", 10, false)).is_true()
	assert_int(w.damage.spare_parts[w.damage.hull_row(0)]).is_equal(10)
	assert_int(w.economy.credits[0]).is_equal(5000 + 10 * 12)
	assert_bool(_trade(w, card, &"parts", 11, false)).is_false()
	assert_str(_why(w)).is_equal("not_held")
	assert_bool(_trade(w, card, &"ammo:m1_cannon", 50, false)).is_true()
	assert_int(w.mounts.ammo[0]).is_equal(350)
	assert_bool(_trade(w, card, &"repair:engines", 1, false)).is_false()


# FT: FT-COM-004, FT-PAIR-004
# A dock repair clears the subsystem's fault and restores its health for the market's price.
func test_dock_repair() -> void:
	var d: Array = _docked()
	var w: SimWorld = d[0]
	var card: int = d[1]
	assert_bool(DamageSystem.inflict_fault(w, 0, &"sensors", &"coolant_leak", 5000000.0)).is_true()
	var row: int = w.damage.find_subsystem(0, &"sensors")
	assert_str(w.damage.fault_cause[row]).is_equal("coolant_leak")
	assert_float(w.damage.health[row]).is_less(w.defs[0].subsystems[4].health_max)
	assert_bool(_trade(w, card, &"repair:sensors", 1)).is_true()
	assert_str(w.damage.fault_cause[row]).is_equal("")
	assert_float(w.damage.health[row]).is_equal(w.defs[0].subsystems[4].health_max)
	assert_int(w.economy.credits[0]).is_equal(4750)
	assert_bool(_trade(w, card, &"repair:hull", 1)).is_false()
	assert_str(_why(w)).is_equal("bad_item")


# FT: FT-MIS-018, FT-DAT-002
# The shipped markets and distributions pass their own validation, and a market prices
# only what it caps.
func test_market_data() -> void:
	for m: MarketDef in StoryFixture.content()["markets"].values():
		assert_array(m.validate()).is_empty()
	var bad: MarketDef = MarketDef.new()
	bad.id = &"bad"
	bad.stock = {&"parts": 3}
	assert_array(bad.validate()).contains_exactly(["stock.parts: no price for it"])
