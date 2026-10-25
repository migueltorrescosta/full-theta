class_name KnowledgeTable
extends SimTable
## Per-faction contact knowledge (FT-ARC-013, T034). One row per (observing faction,
## contact ship) pair, added the first time any ship of that faction detects the contact
## and never removed, so a callsign number survives loss and re-detection (FT-SPA-001).
## Key columns: `ship_ids` holds the CONTACT ship id and `factions` the OBSERVING faction
## (not the contact's own faction). Allied ships share one faction and so share these
## rows and callsigns (FT-ARC-018, FT-SPA-023); a faction never has rows for its own
## ships. Rows are appended in detection order (tick, then contact id, then faction), so
## they are deterministic but not one per ship: reset_ship is overridden.

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

## Derived index, not state: row by faction * 65536 + contact id, filled in add_contact
## (rows never move or go away).
var _rows: Dictionary[int, int] = {}


## Knowledge rows are added on detection, not on spawn.
func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Row of the faction's knowledge of the contact, or -1 if it never detected it.
func row_for(faction: int, contact_id: int) -> int:
	return _rows.get(faction * 65536 + contact_id, -1)


## Ships of other factions that the faction currently detects, in id order;
## ship_factions is every ship's faction by id (Kinematics.factions). One loop here
## instead of a KnowledgeSystem.is_detected call per ship (hot path).
func detected_ships(faction: int, ship_factions: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: int in detected_rows(faction, ship_factions):
		out.append(ship_ids[r])
	return out


## The faction's rows of the ships detected_ships() lists, in the same order.
func detected_rows(faction: int, ship_factions: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var base: int = faction * 65536
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
	for r: int in factions.size():
		if factions[r] == faction:
			number += 1
	var row: int = add_key(contact_id, faction)
	detected.append(0)
	identified.append(0)
	numbers.append(number)
	scan_conf.append(0.0)
	_rows[faction * 65536 + contact_id] = row
	return row


func columns() -> Array:
	return (
		super()
		+ [
			["detected", detected],
			["identified", identified],
			["numbers", numbers],
			["scan_conf", scan_conf]
		]
	)


## Per-ship run reset (FT-MIS-017): the ship's rows as a contact drop to undetected, so
## detection starts afresh next tick, but they keep their callsign number and known
## allegiance (FT-SPA-001). Its faction's knowledge of others is faction state, kept.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	for r: int in ship_ids.size():
		if ship_ids[r] == ship_id:
			detected[r] = 0
