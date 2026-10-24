class_name ScienceKnowledge
extends RefCounted
## What a faction has learned of a contact by Science scans, in KnowledgeTable.scan_conf
## (E01, FT-SCI-002, D28): class, identity, intent, weak points, resistances and hack
## access, each revealed once the scan confidence reaches its ScienceDef threshold. A
## faction always knows its own ships. Other strands read these functions: Weapons
## aiming at a weak point and damage with resistances (strand C) call weak_points_known
## and resistances_known; the Science card is built from card().

const CLASS: StringName = &"class"
const IDENTITY: StringName = &"identity"
const INTENT: StringName = &"intent"
const WEAK_POINTS: StringName = &"weak_points"
const RESISTANCES: StringName = &"resistances"
const HACK: StringName = &"hack"
const PARTS: Array[StringName] = [CLASS, IDENTITY, INTENT, WEAK_POINTS, RESISTANCES, HACK]


## The faction's best scan confidence of the contact, 0..1 (1 for its own ships).
static func confidence(world: SimWorld, faction: int, contact: int) -> float:
	if world.faction_of(contact) == faction:
		return 1.0
	var row: int = world.knowledge.row_for(faction, contact)
	return world.knowledge.scan_conf[row] if row >= 0 else 0.0


## The scan confidence at which a part of the card is revealed.
static func threshold(def: ScienceDef, part: StringName) -> float:
	match part:
		CLASS:
			return def.reveal_class
		IDENTITY:
			return def.reveal_identity
		INTENT:
			return def.reveal_intent
		WEAK_POINTS:
			return def.reveal_weak_points
		RESISTANCES:
			return def.reveal_resistances
		HACK:
			return def.reveal_hack
	return 2.0


## Whether a part of the contact is revealed to the faction.
static func revealed(world: SimWorld, faction: int, contact: int, part: StringName) -> bool:
	if world.faction_of(contact) == faction:
		return true
	if world.science_def == null:
		return false
	var c: float = confidence(world, faction, contact)
	return c > 0.0 and c >= threshold(world.science_def, part)


## Weak points of the contact are revealed to the faction (FT-SIM-023): the gate for
## aiming at a weak point.
static func weak_points_known(world: SimWorld, faction: int, contact: int) -> bool:
	return revealed(world, faction, contact, WEAK_POINTS)


## Damage-type resistances of the contact are revealed to the faction (FT-SIM-022).
static func resistances_known(world: SimWorld, faction: int, contact: int) -> bool:
	return revealed(world, faction, contact, RESISTANCES)


## Indices in the contact's ShipDef.subsystems of its weak points, or [] while they are
## not revealed to the faction.
static func weak_points(world: SimWorld, faction: int, contact: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if not weak_points_known(world, faction, contact):
		return out
	var subs: Array[SubsystemDef] = world.defs[contact].subsystems
	for i: int in subs.size():
		if subs[i].weak_point:
			out.append(i)
	return out


## The contact's resistances, or {} while they are not revealed to the faction.
static func resistances(
	world: SimWorld, faction: int, contact: int
) -> Dictionary[StringName, float]:
	if not resistances_known(world, faction, contact):
		return {}
	return world.defs[contact].resistances


## Number of card parts revealed (0 to 6).
static func level(world: SimWorld, faction: int, contact: int) -> int:
	var n: int = 0
	for part: StringName in PARTS:
		if revealed(world, faction, contact, part):
			n += 1
	return n


## Whether the faction has fully scanned the contact's class this run: any contact of
## that ship definition with scan confidence at or above full_scan_conf (FT-SCI-015).
static func class_fully_scanned(world: SimWorld, faction: int, contact: int) -> bool:
	if world.science_def == null:
		return false
	var id: StringName = world.defs[contact].id
	var k: KnowledgeTable = world.knowledge
	for r: int in k.size():
		if k.factions[r] == faction and k.scan_conf[r] >= world.science_def.full_scan_conf:
			if world.defs[k.ship_ids[r]].id == id:
				return true
	return false


## How sure the faction is that the contact is there, 0..1 (FT-SCI-001): the closer
## to the observing ship's sensor range, the lower; 0 while undetected. The best of the
## faction's ships that sense the contact.
static func detection_confidence(world: SimWorld, faction: int, contact: int) -> float:
	if not KnowledgeSystem.is_detected(world, faction, contact):
		return 0.0
	if world.faction_of(contact) == faction:
		return 1.0
	var best: float = 0.0
	var kin: Kinematics = world.kin
	for o: int in world.ship_count():
		if kin.factions[o] != faction or not kin.can_reach(o, contact) or not kin.is_alive(o):
			continue
		var reach: float = (
			world.defs[o].sensor_range * DamageSystem.effectiveness(world, o, &"sensors")
		)
		if reach > 0.0:
			best = maxf(best, 1.0 - kin.relative(o, contact).length() / reach)
	return clampf(best, 0.05, 1.0)


## Records a scan result: keeps the best confidence, and identifies the contact once
## the identity threshold is reached. Returns false for an unknown contact.
static func record(world: SimWorld, faction: int, contact: int, conf: float) -> bool:
	var row: int = world.knowledge.row_for(faction, contact)
	if row < 0:
		return false
	world.knowledge.scan_conf[row] = maxf(world.knowledge.scan_conf[row], clampf(conf, 0.0, 1.0))
	if (
		world.science_def != null
		and world.knowledge.scan_conf[row] >= world.science_def.reveal_identity
	):
		world.knowledge.identified[row] = 1
	return true
