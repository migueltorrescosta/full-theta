class_name KnowledgeSystem
extends RefCounted
## Per-faction detection, identification and callsigns (FT-ARC-013, T034). Runs every
## tick before power: a faction detects a contact while any live ship of that faction at
## the same site has it within sensor_range scaled by its sensors' effectiveness; it
## identifies the contact's allegiance once one is within identify_range, scaled alike
## (D112; Science scans extend it, E01), and never forgets it. Callsigns are
## per faction (FT-SPA-002), so allied ships, being one faction, share them (FT-ARC-018).
## Enemy AI must read contacts only through this class.
##
## Events, keyed to the observing faction through their ship_id:
## - &"contact_detected": ship_id = the lowest-id observing ship that detects the
##   contact, other_id = the contact, value = callsign number, tag = callsign text.
## - &"contact_lost": ship_id = the faction's lowest-id live ship (lowest-id ship if all
##   are destroyed), other_id = the contact, value and tag as above.

const SENSORS: StringName = &"sensors"


static func step(world: SimWorld) -> void:
	var table: KnowledgeTable = world.knowledge
	var observing: PackedInt32Array = _factions(world)
	for contact: int in world.ship_count():
		for faction: int in observing:
			if faction == world.faction_of(contact):
				continue
			var scan: Vector2i = _scan(world, faction, contact)
			var row: int = table.row_for(faction, contact)
			if scan.x >= 0:
				if row < 0:
					row = table.add_contact(faction, contact)
				if scan.y == 1:
					table.identified[row] = 1
				if table.detected[row] == 0:
					table.detected[row] = 1
					_emit(world, &"contact_detected", scan.x, contact, row)
			elif row >= 0 and table.detected[row] == 1:
				table.detected[row] = 0
				_emit(world, &"contact_lost", _any_ship(world, faction), contact, row)


## Whether the faction currently detects the ship (FT-ARC-013). A faction always knows
## its own ships.
static func is_detected(world: SimWorld, faction: int, ship_id: int) -> bool:
	if world.faction_of(ship_id) == faction:
		return true
	var row: int = world.knowledge.row_for(faction, ship_id)
	return row >= 0 and world.knowledge.detected[row] == 1


## Whether the faction knows the ship's allegiance (FT-SPA-001).
static func is_identified(world: SimWorld, faction: int, ship_id: int) -> bool:
	if world.faction_of(ship_id) == faction:
		return true
	var row: int = world.knowledge.row_for(faction, ship_id)
	return row >= 0 and world.knowledge.identified[row] == 1


## Ships the faction currently detects, other than its own, in id order.
static func contacts(world: SimWorld, faction: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in world.ship_count():
		if world.faction_of(id) != faction and is_detected(world, faction, id):
			out.append(id)
	return out


## The callsign the faction uses for the ship, for example "H2" (FT-SPA-001,
## FT-SPA-002): prefix H hostile, F friendly, N neutral by the faction's current relation
## to the ship's faction once identified, U before; the number is fixed at first
## detection. Own ships go by ship name (spec §6.1). "" if never detected.
static func callsign(world: SimWorld, faction: int, ship_id: int) -> String:
	if world.faction_of(ship_id) == faction:
		return world.defs[ship_id].display_name
	var row: int = world.knowledge.row_for(faction, ship_id)
	if row < 0:
		return ""
	return _prefix(world, faction, ship_id, row) + str(world.knowledge.numbers[row])


static func _prefix(world: SimWorld, faction: int, ship_id: int, row: int) -> String:
	if world.knowledge.identified[row] == 0:
		return "U"
	match world.relation(faction, world.faction_of(ship_id)):
		SimWorld.Relation.FRIENDLY:
			return "F"
		SimWorld.Relation.NEUTRAL:
			return "N"
	return "H"


## x: lowest-id live ship of the faction that detects the contact, or -1; y: 1 if any
## of them is within identify range.
static func _scan(world: SimWorld, faction: int, contact: int) -> Vector2i:
	var kin: Kinematics = world.kin
	var result: Vector2i = Vector2i(-1, 0)
	if not kin.is_alive(contact):
		return result
	for o: int in world.ship_count():
		if world.faction_of(o) != faction or not kin.is_alive(o) or not kin.same_site(o, contact):
			continue
		var scale: float = DamageSystem.effectiveness(world, o, SENSORS)
		var dist: float = kin.relative(o, contact).length()
		if scale <= 0.0 or dist > world.defs[o].sensor_range * scale:
			continue
		if result.x < 0:
			result.x = o
		if dist <= world.defs[o].identify_range * scale:
			result.y = 1
			return result
	return result


## Factions that have at least one ship, ascending.
static func _factions(world: SimWorld) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in world.ship_count():
		var f: int = world.faction_of(id)
		if not out.has(f):
			out.append(f)
	out.sort()
	return out


## The faction's lowest-id live ship, else its lowest-id ship.
static func _any_ship(world: SimWorld, faction: int) -> int:
	var first: int = -1
	for id: int in world.ship_count():
		if world.faction_of(id) == faction:
			if world.kin.is_alive(id):
				return id
			if first < 0:
				first = id
	return first


static func _emit(world: SimWorld, kind: StringName, observer: int, contact: int, row: int) -> void:
	var text: String = callsign(world, world.faction_of(observer), contact)
	world.emit(
		kind, observer, contact, world.knowledge.numbers[row], Vector3.ZERO, StringName(text)
	)
