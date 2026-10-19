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


## Knowledge rows are added on detection, not on spawn.
func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Row of the faction's knowledge of the contact, or -1 if it never detected it.
func row_for(faction: int, contact_id: int) -> int:
	for r: int in ship_ids.size():
		if ship_ids[r] == contact_id and factions[r] == faction:
			return r
	return -1


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
	return row


func columns() -> Array:
	return super() + [["detected", detected], ["identified", identified], ["numbers", numbers]]


## Per-ship run reset (FT-MIS-017): the ship's rows as a contact drop to undetected, so
## detection starts afresh next tick, but they keep their callsign number and known
## allegiance (FT-SPA-001). Its faction's knowledge of others is faction state, kept.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	for r: int in ship_ids.size():
		if ship_ids[r] == ship_id:
			detected[r] = 0
