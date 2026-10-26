class_name Economy
extends RefCounted
## What a ship holds and how it trades it (FT-MIS-018, FT-MIS-021, FT-COM-004, D34).
## Credits live in EconomyTable; ammunition by type, propellant, spare parts and probes in
## the tables that spend them. Items are named as TradeCommand names them: `propellant`,
## `parts`, `probes`, `ammo:<weapon id>`.

const PROPELLANT: StringName = &"propellant"
const PARTS: StringName = &"parts"
const PROBES: StringName = &"probes"
const AMMO_PREFIX: String = "ammo:"


## The one read helper for a ship's economy as a value copy: credits, propellant (kg),
## parts, probes, ammunition rounds by weapon id, and reputation by other faction.
static func of_ship(world: SimWorld, ship: int) -> Dictionary:
	var ammo: Dictionary[StringName, int] = {}
	for w: StringName in ammo_types(world, ship):
		ammo[w] = held(world, ship, StringName(AMMO_PREFIX + w))
	var rep: Dictionary[int, float] = {}
	var faction: int = world.faction_of(ship)
	for other: int in world.reputation.others_of(faction):
		rep[other] = world.reputation.value_of(faction, other)
	return {
		"credits": world.economy.credits[ship],
		"propellant": world.kin.propellant[ship],
		"parts": held(world, ship, PARTS),
		"probes": held(world, ship, PROBES),
		"ammo": ammo,
		"reputation": rep,
	}


static func credits(world: SimWorld, ship: int) -> int:
	return world.economy.credits[ship]


## Adds (or, negative, takes) credits; false, with nothing changed, if the ship can't pay.
static func add_credits(world: SimWorld, ship: int, delta: int) -> bool:
	var after: int = world.economy.credits[ship] + delta
	if after < 0:
		return false
	world.economy.credits[ship] = after
	return true


## Whether an item name is one the economy trades (the kind, and a weapon the ship carries).
static func is_item(world: SimWorld, ship: int, item: StringName) -> bool:
	if item == PROPELLANT or item == PARTS or item == PROBES:
		return true
	return String(item).begins_with(AMMO_PREFIX) and ammo_types(world, ship).has(_weapon(item))


## Units of the item the ship holds now (propellant rounded down).
static func held(world: SimWorld, ship: int, item: StringName) -> int:
	match item:
		PROPELLANT:
			return int(world.kin.propellant[ship])
		PARTS:
			return world.damage.spare_parts[world.damage.hull_row(ship)]
		PROBES:
			return world.relay.stock[ship]
	var total: int = 0
	for slot: Array in _ammo_slots(world, ship, _weapon(item)):
		total += _count(world, slot)
	return total


## Most units the ship can still take of the item (propellant, ammunition: up to capacity;
## parts and probes: unlimited, a large number here).
static func room(world: SimWorld, ship: int, item: StringName) -> int:
	match item:
		PROPELLANT:
			return int(world.defs[ship].propellant_capacity - world.kin.propellant[ship])
		PARTS, PROBES:
			return 1 << 20
	var total: int = 0
	for slot: Array in _ammo_slots(world, ship, _weapon(item)):
		var cap: int = _capacity(world, slot)
		if cap >= 0:
			total += cap - _count(world, slot)
	return total


## Adds qty units of the item to the ship (qty <= room) or, negative, removes up to
## -qty (<= held). The caller has checked both.
static func move(world: SimWorld, ship: int, item: StringName, qty: int) -> void:
	match item:
		PROPELLANT:
			world.kin.propellant[ship] += qty
		PARTS:
			world.damage.spare_parts[world.damage.hull_row(ship)] += qty
		PROBES:
			world.relay.stock[ship] += qty
		_:
			var left: int = absi(qty)
			for slot: Array in _ammo_slots(world, ship, _weapon(item)):
				if left == 0:
					break
				var have: int = _count(world, slot)
				var cap: int = _capacity(world, slot)
				if cap < 0:
					continue
				var step: int = mini(left, cap - have) if qty > 0 else mini(left, have)
				_put_count(world, slot, have + step if qty > 0 else have - step)
				left -= step


## The weapon ids of the ammunition types the ship's mounts take, in mount order.
static func ammo_types(world: SimWorld, ship: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for m: MountDef in world.defs[ship].mounts:
		for w: WeaponDef in m.ammo_types():
			if w.ammo_capacity >= 0 and not out.has(w.id):
				out.append(w.id)
	return out


static func _weapon(item: StringName) -> StringName:
	return StringName(String(item).trim_prefix(AMMO_PREFIX))


## [mount row, type index] of each ammunition store of the weapon, in mount order.
static func _ammo_slots(world: SimWorld, ship: int, weapon: StringName) -> Array:
	var out: Array = []
	var mounts: Array[MountDef] = world.defs[ship].mounts
	for i: int in mounts.size():
		var types: Array[WeaponDef] = mounts[i].ammo_types()
		for t: int in types.size():
			if types[t].id == weapon and types[t].ammo_capacity >= 0:
				out.append([world.mounts.row_for(ship, i), t, types[t].ammo_capacity])
	return out


static func _count(world: SimWorld, slot: Array) -> int:
	var m: MountTable = world.mounts
	return m.ammo[slot[0]] if m.ammo_type[slot[0]] == slot[1] else m.type_ammo[slot[0]][slot[1]]


static func _capacity(_world: SimWorld, slot: Array) -> int:
	return slot[2]


static func _put_count(world: SimWorld, slot: Array, value: int) -> void:
	var m: MountTable = world.mounts
	if m.ammo_type[slot[0]] == slot[1]:
		m.ammo[slot[0]] = value
	else:
		var stock: PackedInt32Array = m.type_ammo[slot[0]]
		stock[slot[1]] = value
		m.type_ammo[slot[0]] = stock
