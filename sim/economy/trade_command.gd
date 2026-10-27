class_name TradeCommand
extends SimCommand
## Comms buys or sells goods at the market of a docked site's offer card (FT-COM-004,
## FT-MIS-018, D34, D68): propellant, parts, probes, ammo:<weapon id>, or repair:<subsystem>
## (buy only; clears the subsystem's fault and restores its health, P12). Parts land in
## Engineering's spares at once. Refused with event trade_refused (tag the reason) unless
## docked, priced, within the market's cap, in room and affordable.

var card: int = -1
var item: StringName = &""
var qty: int = 1
var buy: bool = true


func kind() -> StringName:
	return &"comms_trade"


func apply(world: SimWorld) -> bool:
	var why: Array[StringName] = []
	var m: MarketDef = Trade.market(world, ship_id, card, why)
	if m == null:
		return Trade.refuse(world, ship_id, card, why[0])
	if String(item).begins_with(Trade.REPAIR_PREFIX):
		return _repair(world, m)
	var reason: StringName = _check(world, m)
	if reason != &"":
		return Trade.refuse(world, ship_id, card, reason)
	var price: int = m.prices[item]
	if buy:
		Economy.add_credits(world, ship_id, -price * qty)
		Economy.move(world, ship_id, item, qty)
		world.emit(&"trade_done", ship_id, card, -price * qty, Vector3.ZERO, item)
	else:
		var pay: int = Trade.sale_price(m, price) * qty
		Economy.move(world, ship_id, item, -qty)
		Economy.add_credits(world, ship_id, pay)
		world.emit(&"trade_done", ship_id, card, pay, Vector3.ZERO, item)
	return true


## Why the trade can't happen, or &"".
func _check(world: SimWorld, m: MarketDef) -> StringName:
	if qty < 1 or not Economy.is_item(world, ship_id, item):
		return &"bad_item"
	var price: int = m.prices.get(item, 0)
	if price < 1:
		return &"no_price"
	if qty > m.stock.get(item, 1 << 20):
		return &"over_stock"
	if not buy:
		return &"" if qty <= Economy.held(world, ship_id, item) else &"not_held"
	if qty > Economy.room(world, ship_id, item):
		return &"no_room"
	return &"" if price * qty <= Economy.credits(world, ship_id) else &"no_credits"


## A dock repair: the subsystem's fault clears and its health is restored.
func _repair(world: SimWorld, m: MarketDef) -> bool:
	var sub: StringName = StringName(String(item).trim_prefix(Trade.REPAIR_PREFIX))
	var row: int = world.damage.find_subsystem(ship_id, sub)
	var price: int = m.repairs.get(sub, 0)
	if not buy or row < 0 or price < 1:
		return Trade.refuse(world, ship_id, card, &"bad_item")
	if not Economy.add_credits(world, ship_id, -price):
		return Trade.refuse(world, ship_id, card, &"no_credits")
	var d: DamageTable = world.damage
	for def: SubsystemDef in world.defs[ship_id].subsystems:
		if def.id == sub:
			d.health[row] = def.health_max
	d.fault_cause[row] = &""
	d.fault_known[row] = 0
	d.fault_pick[row] = &""
	world.emit(&"trade_done", ship_id, card, -price, Vector3.ZERO, item)
	return true
