class_name CrewMarks
extends RefCounted
## Per-ship marks and alert level: crew state the server keeps outside the sim, so
## outside the command log and the state hash. Pure rules; NetCrewState checks the
## sender's pick, validates contact and site ids, wraps free points onto the site's cube
## and sends the `marks` and `alert` events.
## - Marks (FT-SPA-012): 8 slots per ship, named Alpha to Hotel by default. A mark is
##   free (site + three 64-bit offsets wrapped into [-P/2, P/2), D104, D124) or attached
##   to a contact or to one of its scanned subsystems (FT-SPA-014, D202; the client
##   follows the contact, and shows its last known position once it is lost).
## - Who may do what (FT-SPA-013, FT-SPA-022, FT-RLY-003): any crew station places;
##   with all 8 used only Relay places, replacing the slot it names. Relay renames,
##   moves, attaches and deletes any mark; other crew only their own (`by_session`).
##   The Captain fills empty slots only. Viewers do nothing.
## - Alert level (FT-STN-008, D89): any crew pick sets it; Captain and Viewer don't.

enum Role { NONE, CREW, RELAY, CAPTAIN }

const SLOTS: int = 8
const DEFAULT_NAMES: Array[String] = [
	"Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"
]
## Longest mark name kept (UTF-8 bytes, after trimming). PROVISIONAL.
const MAX_NAME_BYTES: int = 24
## C0 and C1 controls and the bidi marks, embeddings, overrides and isolates.
const UNSAFE_CHARS: String = (
	"[\\x{0}-\\x{1F}\\x{7F}-\\x{9F}\\x{61C}\\x{200E}\\x{200F}\\x{202A}-\\x{202E}"
	+ "\\x{2066}-\\x{2069}]"
)
const ALERT_NORMAL: int = 0
const ALERT_YELLOW: int = 1
const ALERT_RED: int = 2

## Refusal reasons (request_rejected), besides ServerSession.NOT_CREW and
## CommandGate.NOT_ALLOWED (the Captain moving, renaming or deleting).
const MARKS_FULL: String = "marks_full"
const SLOT_TAKEN: String = "slot_taken"
const NOT_YOURS: String = "not_yours"
const BAD_MARK: String = "bad_mark"
const BAD_LEVEL: String = "bad_level"

static var _unsafe: RegEx

## Ship -> Array of SLOTS entries: {} for an empty slot, else {slot, name, contact, site,
## x, y, z, sub, by, by_session}.
var _marks: Dictionary[int, Array] = {}
## Ship -> alert level (missing: Normal).
var _alert: Dictionary[int, int] = {}


## The seat role of a catalogue entry for these rules.
static func role_of(entry: String) -> Role:
	if entry == StationViews.CAPTAIN:
		return Role.CAPTAIN
	if not StationViews.is_crew(entry):
		return Role.NONE
	return Role.RELAY if StationViews.stations_of(entry).has("relay") else Role.CREW


func alert(ship: int) -> int:
	return _alert.get(ship, ALERT_NORMAL)


## Sets the alert level; returns why not, or "".
func set_alert(ship: int, role: Role, level: int) -> String:
	if role != Role.CREW and role != Role.RELAY:
		return ServerSession.NOT_CREW
	if level < ALERT_NORMAL or level > ALERT_RED:
		return BAD_LEVEL
	_alert[ship] = level
	return ""


## The ship's placed marks in slot order, as sent in `marks` events.
func marks_of(ship: int) -> Array:
	var out: Array = []
	for m: Dictionary in _slots(ship):
		if not m.is_empty():
			var sent: Dictionary = m.duplicate()
			sent.erase("by_session")
			out.append(sent)
	return out


func has_mark(ship: int, slot: int) -> bool:
	return slot >= 0 and slot < SLOTS and not (_slots(ship)[slot] as Dictionary).is_empty()


## Places a mark (slot -1: the first free one; name "": the slot's default). `spot`
## holds the Mark message's contact, site, x, y and z: contact >= 0 attaches the mark
## (the caller checked the id, and the scanned subsystem `sub` with its place `off`),
## else it is free at (site, x, y, z).
func place(
	ship: int, role: Role, session: int, by: String, slot: int, name: String, spot: Dictionary
) -> String:
	if role == Role.NONE:
		return ServerSession.NOT_CREW
	var slots: Array = _slots(ship)
	if slot < -1 or slot >= SLOTS:
		return BAD_MARK
	if slot == -1:
		for k: int in SLOTS:
			if (slots[k] as Dictionary).is_empty():
				slot = k
				break
		if slot == -1:
			return MARKS_FULL
	elif not (slots[slot] as Dictionary).is_empty() and role != Role.RELAY:
		# FT-SPA-022: only Relay replaces a mark; the others get the toast.
		return MARKS_FULL if marks_of(ship).size() == SLOTS else SLOT_TAKEN
	var where: Dictionary = _location(spot)
	if where.is_empty():
		return BAD_MARK
	var mark: Dictionary = {"slot": slot, "name": _name(slot, name)}
	mark.merge(where)
	mark["by"] = by
	mark["by_session"] = session
	slots[slot] = mark
	return ""


## Moves a mark, or attaches or detaches it (`spot` as in place()).
func move(ship: int, role: Role, session: int, slot: int, spot: Dictionary) -> String:
	var why: String = _may_edit(ship, role, session, slot)
	if why != "":
		return why
	var where: Dictionary = _location(spot)
	if where.is_empty():
		return BAD_MARK
	(_slots(ship)[slot] as Dictionary).merge(where, true)
	return ""


## Renames a mark ("" restores the slot's default name).
func rename(ship: int, role: Role, session: int, slot: int, name: String) -> String:
	var why: String = _may_edit(ship, role, session, slot)
	if why == "":
		_slots(ship)[slot]["name"] = _name(slot, name)
	return why


func delete(ship: int, role: Role, session: int, slot: int) -> String:
	var why: String = _may_edit(ship, role, session, slot)
	if why == "":
		_slots(ship)[slot] = {}
	return why


## A run reset: no marks, alert Normal.
func reset(ship: int) -> void:
	_marks.erase(ship)
	_alert.erase(ship)


func _slots(ship: int) -> Array:
	if not _marks.has(ship):
		var empty: Array = []
		for k: int in SLOTS:
			empty.append({})
		_marks[ship] = empty
	return _marks[ship]


func _may_edit(ship: int, role: Role, session: int, slot: int) -> String:
	if role == Role.NONE:
		return ServerSession.NOT_CREW
	if not has_mark(ship, slot):
		return BAD_MARK
	if role == Role.CAPTAIN:
		return CommandGate.NOT_ALLOWED
	if role == Role.CREW and _slots(ship)[slot]["by_session"] != session:
		return NOT_YOURS
	return ""


## {contact, site, x, y, z} for an attached (contact >= 0, site -1, zeros) or a free mark
## (site >= 0, finite offsets, already wrapped by the caller); {} when invalid.
func _location(spot: Dictionary) -> Dictionary:
	var contact: int = spot["contact"]
	var site: int = spot["site"]
	var x: float = spot["x"]
	var y: float = spot["y"]
	var z: float = spot["z"]
	if contact >= 0:
		# Attached to a contact, or to one of its scanned subsystems (FT-SPA-014, D202):
		# `sub` is the ShipDef.subsystems index and (x, y, z) its place in the contact's
		# frame, filled in by the caller; a plain contact mark has none.
		var off: Vector3 = spot.get("off", Vector3.ZERO)
		var sub: int = spot.get("sub", -1)
		return {"contact": contact, "site": -1, "x": off.x, "y": off.y, "z": off.z, "sub": sub}
	if contact != -1 or site < 0 or not (is_finite(x) and is_finite(y) and is_finite(z)):
		return {}
	return {"contact": -1, "site": site, "x": x, "y": y, "z": z, "sub": -1}


## The name trimmed, without control or bidi characters (a name can't reorder or hide
## the text around it on another screen), cut to MAX_NAME_BYTES; the default when empty.
func _name(slot: int, name: String) -> String:
	if _unsafe == null:
		_unsafe = RegEx.create_from_string(UNSAFE_CHARS)
	var clean: String = _unsafe.sub(name, "", true).strip_edges()
	var kept: String = NetProtocol.clip_utf8(clean, MAX_NAME_BYTES).strip_edges()
	return kept if kept != "" else DEFAULT_NAMES[slot]
