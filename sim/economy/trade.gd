class_name Trade
extends RefCounted
## What the trade commands share (FT-COM-004, FT-COM-009, FT-MIS-036, D34, D86): the
## market of an offer card the ship is docked at, and the refusal event.

const REPAIR_PREFIX: String = "repair:"


## The market behind an OFFER card for a docked ship, or null with the reason in
## `why[0]`: no_card, not_offer, closed (the card lapsed or was declined), not_docked,
## no_market.
static func market(world: SimWorld, ship: int, card: int, why: Array[StringName]) -> MarketDef:
	var t: StoryTable = world.story
	if not Story.visible_to(world, card, ship):
		why.append(&"no_card")
	elif t.kind[card] != StoryTable.Kind.OFFER:
		why.append(&"not_offer")
	elif not Story.is_live(world, card):
		why.append(&"closed")
	elif t.site[card] < 0 or Story.docked_site(world, ship) != t.site[card]:
		why.append(&"not_docked")
	else:
		var m: MarketDef = world.markets.get(world.site_markets.get(t.site[card], &""))
		if m != null:
			return m
		why.append(&"no_market")
	return null


## What the market pays for a module or an item priced at `price`.
static func sale_price(m: MarketDef, price: int) -> int:
	return floori(price * m.sell_ratio)


static func refuse(world: SimWorld, ship: int, card: int, why: StringName) -> bool:
	world.emit(&"trade_refused", ship, card, 0.0, Vector3.ZERO, why)
	return false
