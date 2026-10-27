class_name MarketDef
extends Resource
## What a docked site trades (FT-COM-004, FT-COM-009, D34, D86): per-unit prices in
## credits for what the ship buys (items as TradeCommand names them: propellant, parts,
## probes, ammo:<weapon id>), repair prices per subsystem, and the modules on offer. The
## market never runs out; `stock` caps the units of one trade. Read-only at runtime
## (FT-ARC-020).

## Unique among markets (dimensionless id).
@export var id: StringName = &""
## Item -> credits per unit when the crew buys (and the base of what a sale pays).
@export var prices: Dictionary[StringName, int] = {}
## Item -> most units in one trade; an item missing here has no cap.
@export var stock: Dictionary[StringName, int] = {}
## Subsystem id -> credits for a dock repair of it (clears its fault, restores its health).
@export var repairs: Dictionary[StringName, int] = {}
## ModuleDef ids on offer.
@export var modules: Array[StringName] = []
## Share of a price paid when the crew sells to the market (dimensionless, 0..1).
@export var sell_ratio: float = 0.5


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.in_range(errors, "sell_ratio", sell_ratio, 0.0, 1.0)
	for item: StringName in prices:
		if prices[item] < 1:
			errors.append("prices.%s: must be >= 1, got %d" % [item, prices[item]])
	for item: StringName in stock:
		if stock[item] < 1:
			errors.append("stock.%s: must be >= 1, got %d" % [item, stock[item]])
		if not prices.has(item):
			errors.append("stock.%s: no price for it" % item)
	for sub: StringName in repairs:
		if repairs[sub] < 1:
			errors.append("repairs.%s: must be >= 1, got %d" % [sub, repairs[sub]])
	return errors
