class_name SalvageSystem
extends RefCounted
## Salvage (gp-11, #38 D7). An armed AI ship destroyed (OutcomeSystem, drop_wreck) leaves a
## wreck worth RunDef.salvage times the run modifier (none at 0), collectable for
## RunDef.salvage_lifetime. Each tick after OutcomeSystem, in a director run (RunDef set),
## the first crewed ship in play (by id) within RunDef.salvage_range of a wreck still there
## collects it: the credits go to that ship, and &"salvage" is emitted (ship_id the ship,
## other_id the wrecked ship, value the credits).


static func step(world: SimWorld) -> void:
	var def: RunDef = world.run_def
	if def == null:
		return
	var t: WreckTable = world.wrecks
	for w: int in t.size():
		if t.taken_by[w] >= 0 or world.tick > t.until_tick[w]:
			continue
		var at: PackedFloat64Array = CubePoint.make(t.x[w], t.y[w], t.z[w])
		for ship: int in world.ship_count():
			if not world.is_crew_in_play(ship) or not world.kin.is_alive(ship):
				continue
			if world.kin.relative_to_point(ship, at).length() <= def.salvage_range:
				t.taken_by[w] = ship
				Economy.add_credits(world, ship, t.value[w])
				world.emit(&"salvage", ship, t.owner_ship[w], t.value[w])
				break


## The wreck of an armed AI ship OutcomeSystem has just marked DESTROYED (a retreat leaves none).
static func drop_wreck(world: SimWorld, id: int) -> void:
	var def: RunDef = world.run_def
	if def == null or world.ships.status[id] != ShipStateTable.Status.DESTROYED:
		return
	var credits: int = scaled(def.salvage, world.modifier.salvage)
	# (an armed ship: a destroyed debris rock is no wreck)
	if credits <= 0 or world.defs[id].mounts.is_empty():
		return
	var until: int = world.tick + SimRate.ticks(def.salvage_lifetime)
	world.wrecks.add_wreck(id, world.faction_of(id), world.kin.point(id), credits, until)


## A run number times a run modifier's multiplier, rounded down (with a hair of slack, as
## Trade.sale_price).
static func scaled(base: int, factor: float) -> int:
	return floori(base * factor + 1e-6)
