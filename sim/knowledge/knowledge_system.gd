class_name KnowledgeSystem
extends RefCounted
## Per-faction detection, identification and callsigns (FT-ARC-013, T034). Runs every
## tick before power: a faction detects a contact while any live ship of that faction
## has it within sensor_range scaled by its sensors' effectiveness; it
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

## The subsystem id of a ship's sensors (the one name the sim uses for it).
const SENSORS: StringName = &"sensors"


## The share of its sensors a ship still has, 0..1: 0 for a destroyed ship or blinded sensors.
static func sensor_scale(world: SimWorld, ship: int) -> float:
	if not world.kin.is_alive(ship):
		return 0.0
	return DamageSystem.effectiveness(world, ship, SENSORS)


## How far a ship detects (m): its sensor range scaled by its sensors' effectiveness; 0 for a
## destroyed ship or blinded sensors. The one place the reach is computed (R04-1).
static func sensor_reach(world: SimWorld, ship: int) -> float:
	return world.defs[ship].sensor_range * sensor_scale(world, ship)


static func step(world: SimWorld) -> void:
	var table: KnowledgeTable = world.knowledge
	var kin: Kinematics = world.kin
	var n: int = world.ship_count()
	var observing: PackedInt32Array = _factions(world)
	# Each live ship's sensor and identify ranges scaled by its sensors' effectiveness
	# (m), once per tick; -1 when the ship can't sense.
	var sense: PackedFloat64Array = PackedFloat64Array()
	var identify: PackedFloat64Array = PackedFloat64Array()
	sense.resize(n)
	identify.resize(n)
	# The ships that can sense, per observing faction (same order), in id order.
	var sensing: Array[PackedInt32Array] = []
	for f: int in observing.size():
		sensing.append(PackedInt32Array())
	var factions: PackedInt32Array = kin.factions
	var alive: PackedByteArray = kin.alive
	var detected: PackedByteArray = table.detected
	var defs: Array[ShipDef] = world.defs
	for o: int in n:
		var scale: float = sensor_scale(world, o)
		var can_sense: bool = scale > 0.0
		sense[o] = defs[o].sensor_range * scale if can_sense else -1.0
		identify[o] = defs[o].identify_range * scale if can_sense else -1.0
		if not sense[o] < 0.0:
			sensing[observing.bsearch(factions[o])].append(o)
	for contact: int in n:
		var own: int = factions[contact]
		var live: bool = alive[contact] == 1
		for fi: int in observing.size():
			var faction: int = observing[fi]
			if faction == own:
				continue
			# The lowest-id ship of the faction that detects the contact (or -1), and
			# whether any of them is within identify range (_scan, inlined).
			var by: int = -1
			var ident: bool = false
			if live:
				for o: int in sensing[fi]:
					var dist: float = kin.relative(o, contact).length()
					if dist > sense[o]:
						continue
					if by < 0:
						by = o
					if dist <= identify[o]:
						ident = true
						break
			# A deployed probe's bubble detects too (P13, FT-RLY-004): the contact gets a
			# row, so Science can scan and hack inside it.
			if by < 0 and live and world.probes.size() > 0:
				var p: PackedFloat64Array = kin.point_at(contact, Vector3.ZERO)
				if ProbeSystem.coverage_at(world, faction, Vector3(p[0], p[1], p[2])):
					by = _any_ship(world, faction)
			var row: int = table.row_for(faction, contact)
			if by >= 0:
				if row < 0:
					row = table.add_contact(faction, contact)
					# add_contact grows the columns in place; detected still refers to it.
				if ident:
					table.identified[row] = 1
				if detected[row] == 0:
					detected[row] = 1
					_emit(world, &"contact_detected", by, contact, row)
			elif row >= 0 and detected[row] == 1:
				detected[row] = 0
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
	return world.knowledge.detected_ships(faction, world.kin.factions)


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


## Whether the faction knows the subsystem is a weak point (FT-SIM-023): a faction knows
## its own ships', and otherwise Science's scans reveal it (ScienceKnowledge, the one
## store of what scans revealed).
static func knows_weak_point(
	world: SimWorld, faction: int, contact: int, subsystem_id: StringName
) -> bool:
	var i: int = _subsystem_index(world, contact, subsystem_id)
	if i < 0 or not world.defs[contact].subsystems[i].weak_point:
		return false
	return (
		world.faction_of(contact) == faction
		or i in ScienceKnowledge.weak_points(world, faction, contact)
	)


static func _subsystem_index(world: SimWorld, ship_id: int, subsystem_id: StringName) -> int:
	if not world.has_ship(ship_id):
		return -1
	var row: int = world.damage.find_subsystem(ship_id, subsystem_id)
	var i: int = world.damage.index_of_row(ship_id, row) if row >= 0 else -1
	return i if i < 31 else -1


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
