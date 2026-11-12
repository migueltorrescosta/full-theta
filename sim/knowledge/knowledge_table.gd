class_name KnowledgeTable
extends SimTable
## Per-faction contact knowledge (FT-ARC-013, T034). One row per (observing faction,
## contact ship) pair, added the first time any ship of that faction detects the contact
## and never removed, so a callsign number survives loss and re-detection (FT-SPA-001).
## The rows are the observing faction's: `owner_faction` is that faction and `owner_ship`
## is -1 (no one ship owns them); `subject_ship` is the contact (D404). Allied ships share
## one faction and so share these rows and callsigns (FT-ARC-018, FT-SPA-023); a faction
## never has rows for its own ships. Rows are appended in detection order (tick, then
## contact id, then faction), so they are deterministic but not one per ship: reset_ship
## is overridden.

## A contract's target flag on the contact (FT-MIS-042, D82): DISABLE (do not destroy) or
## PROTECT, held in the faction's knowledge so its allied Weapons stations can show it
## under the contract_flags toggle (P9).
enum Flag { NONE, DISABLE, PROTECT }
## What the faction has learned of the contact's intent through conversation (P9); the
## Science card's intent (from scans) is separate. A new contact is UNKNOWN until a reply
## or a surrender roll sets it (Q22, owner 2026-10-26).
enum Intent { UNKNOWN, HOSTILE, NEUTRAL, SURRENDERING, BLUFFING }

## The contact ship the row is about.
var subject_ship: PackedInt32Array = PackedInt32Array()
## 1 while the observing faction currently detects the contact.
var detected: PackedByteArray = PackedByteArray()
## 1 once the faction knows the contact's allegiance; it stays known (FT-SPA-001).
var identified: PackedByteArray = PackedByteArray()
## Callsign number, unique within the observing faction, from 1 in order of first
## detection; never changes (FT-SPA-001, FT-SPA-002).
var numbers: PackedInt32Array = PackedInt32Array()
## Best confidence of the faction's Science scans of the contact, 0..1 (0: never scanned,
## FT-SCI-016). What it reveals is ScienceKnowledge's: class, identity, intent, weak
## points, resistances and hack access, each from its own threshold (E01).
var scan_conf: PackedFloat64Array = PackedFloat64Array()

## A contract's target flag on the contact and what the faction learned of its intent
## (Flag, Intent above).
var flag: PackedByteArray = PackedByteArray()
var intent: PackedByteArray = PackedByteArray()
## Story state about the contact (#10): 1 once a probe's discovery of it opened a hail
## card (P15, StoryRules.on_discovery); the faction's refused surrender asks of it and the
## tick it may ask again (P9, StoryRules.ask_surrender; 0: any time); the scan facts the
## faction learned of it (P14, Story.learn_fact); and the RepDistDef ids its hails already
## drew (Story._first_draw). The string lists are replaced whole, never changed in place.
var hail_opened: PackedByteArray = PackedByteArray()
var surrender_refusals: PackedInt32Array = PackedInt32Array()
var surrender_reopen: PackedInt32Array = PackedInt32Array()
var facts: Array[PackedStringArray] = []
var rep_drawn: Array[PackedStringArray] = []

## Derived index, not state: row by SimTable.row_key(faction, contact id), filled in add_contact
## (rows never move or go away).
var _rows: Dictionary[int, int] = {}


## Knowledge rows are added on detection, not on spawn.
func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Row of the faction's knowledge of the contact, or -1 if it never detected it.
func row_for(faction: int, contact_id: int) -> int:
	return _rows.get(SimTable.row_key(faction, contact_id), -1)


## Ships of other factions that the faction currently detects, in id order;
## ship_factions is every ship's faction by id (Kinematics.owner_faction). One loop here
## instead of a KnowledgeSystem.is_detected call per ship (hot path).
func detected_ships(faction: int, ship_factions: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: int in detected_rows(faction, ship_factions):
		out.append(subject_ship[r])
	return out


## The faction's rows of the ships detected_ships() lists, in the same order.
func detected_rows(faction: int, ship_factions: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var base: int = SimTable.row_key(faction, 0)
	var rows: Dictionary[int, int] = _rows
	var det: PackedByteArray = detected
	for id: int in ship_factions.size():
		if ship_factions[id] != faction:
			var r: int = rows.get(base + id, -1)
			if r >= 0 and det[r] == 1:
				out.append(r)
	return out


## Adds the faction's row for a newly detected contact with the next callsign number.
func add_contact(faction: int, contact_id: int) -> int:
	var number: int = 1
	for r: int in owner_faction.size():
		if owner_faction[r] == faction:
			number += 1
	var row: int = add_key(-1, faction)
	subject_ship.append(contact_id)
	detected.append(0)
	identified.append(0)
	numbers.append(number)
	scan_conf.append(0.0)
	flag.append(Flag.NONE)
	intent.append(Intent.UNKNOWN)
	hail_opened.append(0)
	surrender_refusals.append(0)
	surrender_reopen.append(0)
	facts.append(PackedStringArray())
	rep_drawn.append(PackedStringArray())
	_rows[SimTable.row_key(faction, contact_id)] = row
	return row


## Row of the faction's knowledge of the contact, added undetected if it has none (a
## contract flag or an intent can precede the first detection).
func ensure_contact(faction: int, contact_id: int) -> int:
	var r: int = row_for(faction, contact_id)
	return r if r >= 0 else add_contact(faction, contact_id)


## Per-ship run reset (FT-MIS-017): the ship's rows as a contact drop to undetected, so
## detection starts afresh next tick, but they keep their callsign number and known
## allegiance (FT-SPA-001). Its faction's knowledge of others is faction state, kept.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	for r: int in subject_ship.size():
		if subject_ship[r] == ship_id:
			detected[r] = 0
