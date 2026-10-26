class_name BuyModuleCommand
extends SimCommand
## Comms buys a module for one of the ship's slots while docked (FT-COM-009, FT-MIS-035,
## FT-MIS-036, D86). The module is fitted at once; buying for a full slot sells the old
## module to the market in the same command, and its sale price is taken off the cost
## (the offer card shows it). Refused with trade_refused (tag the reason) unless the
## market offers the module, the slot takes its type, and the credits cover the difference.

var card: int = -1
var module_key: StringName = &""
var slot: int = 0


func kind() -> StringName:
	return &"comms_buy_module"


func apply(world: SimWorld) -> bool:
	var why: Array[StringName] = []
	var m: MarketDef = Trade.market(world, ship_id, card, why)
	if m == null:
		return Trade.refuse(world, ship_id, card, why[0])
	var ix: int = ModuleSystem.index_of(world, module_key)
	var row: int = world.modules.slot_row(ship_id, slot)
	if ix < 0 or row < 0 or not m.modules.has(module_key):
		return Trade.refuse(world, ship_id, card, &"bad_item")
	var module: ModuleDef = world.module_defs[ix]
	if module.slot_type != world.modules.slot_type[row]:
		return Trade.refuse(world, ship_id, card, &"wrong_slot")
	var old: ModuleDef = ModuleSystem.fitted(world, ship_id, slot)
	var trade_in: int = Trade.sale_price(m, old.price) if old != null else 0
	if not Economy.add_credits(world, ship_id, trade_in - module.price):
		return Trade.refuse(world, ship_id, card, &"no_credits")
	ModuleSystem.fit(world, ship_id, slot, module)
	if old != null:
		world.emit(&"module_sold", ship_id, card, trade_in, Vector3.ZERO, old.id)
	world.emit(&"module_fitted", ship_id, card, slot, Vector3.ZERO, module.id)
	return true
