class_name SellModuleCommand
extends SimCommand
## Comms sells the module fitted in a slot to the docked market (FT-COM-009, FT-MIS-036),
## which pays MarketDef.sell_ratio of its price; the slot is left empty.

var card: int = -1
var slot: int = 0


func kind() -> StringName:
	return &"comms_sell_module"


func apply(world: SimWorld) -> bool:
	var why: Array[StringName] = []
	var m: MarketDef = Trade.market(world, ship_id, card, why)
	if m == null:
		return Trade.refuse(world, ship_id, card, why[0])
	var old: ModuleDef = ModuleSystem.fitted(world, ship_id, slot)
	if old == null:
		return Trade.refuse(world, ship_id, card, &"bad_item")
	var pay: int = Trade.sale_price(m, old.price)
	ModuleSystem.fit(world, ship_id, slot, null)
	Economy.add_credits(world, ship_id, pay)
	world.emit(&"module_sold", ship_id, card, pay, Vector3.ZERO, old.id)
	return true
