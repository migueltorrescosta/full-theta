class_name CrewRelay
extends RefCounted
## Relay's per-ship crew state outside the sim (E02, D171), the pure rules beside CrewMarks:
## - zones: hazard zones and scan positions, MARK items outside the 8 named marks that
##   stay at every difficulty (FT-SPA-012, FT-SPA-028, FT-SPA-029);
## - routes: Relay's waypoint lines (FT-RLY-005), MARK items that Hard keeps off other
##   stations (FT-SPA-029, FT-PAIR-008);
## - the inbox of marks other ships' Relays sent, visible only to the receiving Relay
##   until it accepts one (FT-RLY-008, FT-RLY-009, FT-SPA-021);
## - the ship's log (FT-RLY-006): short keyed entries, never NPC text (FT-RLY-007).
## - approach lanes (P5, strand F): MARK items Comms' accepted clearance creates, derived from
##   STORY (lane_items), that Hard keeps off other stations (FT-SPA-029, FT-PAIR-008).
## NetCrewState checks who may do what and sends the events.

const KIND_HAZARD: String = "hazard"
const KIND_SCAN: String = "scan"
## Most zones, routes, waypoints per route, pending marks and log entries kept per ship.
## PROVISIONAL.
const MAX_ZONES: int = 16
const MAX_ROUTES: int = 4
const MAX_WAYPOINTS: int = 12
const MAX_INBOX: int = 8
const MAX_LOG: int = 60
## Largest hazard radius (m).
const MAX_RADIUS: float = 50_000.0

## Refusals.
const ZONES_FULL: String = "zones_full"
const ROUTE_FULL: String = "route_full"
const BAD_ROUTE: String = "bad_route"
const BAD_ZONE: String = "bad_zone"
const INBOX_FULL: String = "inbox_full"
const BAD_INBOX: String = "bad_inbox"
const BAD_TARGET: String = "bad_target"
## A mark attached to a contact the faction no longer detects can't be sent (D221).
const LOST_CONTACT: String = "lost_contact"
const NOT_RELAY: String = "not_relay"

## Ship -> Array of {id, kind, x, y, z, radius, by}.
var _zones: Dictionary[int, Array] = {}
## Ship -> Array (MAX_ROUTES slots) of Arrays of {x, y, z}.
var _routes: Dictionary[int, Array] = {}
## Ship -> Array of {id, from_ship, from, name, x, y, z}.
var _inbox: Dictionary[int, Array] = {}
## Ship -> Array of {tick, key, args}.
var _log: Dictionary[int, Array] = {}
var _next_id: int = 1


func zones_of(ship: int) -> Array:
	return (_zones.get(ship, []) as Array).duplicate(true)


## Adds a zone (kind KIND_HAZARD or KIND_SCAN) at a point in the cube; returns "" or why not.
func add_zone(ship: int, kind: String, at: Vector3, radius: float, by: String) -> String:
	if kind != KIND_HAZARD and kind != KIND_SCAN:
		return BAD_ZONE
	if not (is_finite(radius) and radius > 0.0 and radius <= MAX_RADIUS):
		return BAD_ZONE
	var zones: Array = _zones.get_or_add(ship, [])
	if zones.size() >= MAX_ZONES:
		return ZONES_FULL
	(
		zones
		. append(
			{
				"id": _next_id,
				"kind": kind,
				"x": at.x,
				"y": at.y,
				"z": at.z,
				"radius": radius,
				"by": by,
			}
		)
	)
	_next_id += 1
	return ""


func delete_zone(ship: int, id: int) -> String:
	var zones: Array = _zones.get(ship, [])
	for i: int in zones.size():
		if zones[i]["id"] == id:
			zones.remove_at(i)
			return ""
	return BAD_ZONE


## The ship's routes, slot order (empty routes included).
func routes_of(ship: int) -> Array:
	return (_route_slots(ship) as Array).duplicate(true)


## Appends a waypoint to route `route`.
func route_add(ship: int, route: int, at: Vector3) -> String:
	if route < 0 or route >= MAX_ROUTES or not (is_finite(at.x) and is_finite(at.y)):
		return BAD_ROUTE
	if not is_finite(at.z):
		return BAD_ROUTE
	var points: Array = _route_slots(ship)[route]
	if points.size() >= MAX_WAYPOINTS:
		return ROUTE_FULL
	points.append({"x": at.x, "y": at.y, "z": at.z})
	return ""


func route_clear(ship: int, route: int) -> String:
	if route < 0 or route >= MAX_ROUTES:
		return BAD_ROUTE
	_route_slots(ship)[route].clear()
	return ""


func inbox_of(ship: int) -> Array:
	return (_inbox.get(ship, []) as Array).duplicate(true)


## Queues a mark for the receiving ship's Relay (`mark`: name, x, y, z); returns
## "" or why not.
func send(to_ship: int, from_ship: int, from: String, mark: Dictionary) -> String:
	var box: Array = _inbox.get_or_add(to_ship, [])
	if box.size() >= MAX_INBOX:
		return INBOX_FULL
	var item: Dictionary = {"id": _next_id, "from_ship": from_ship, "from": from}
	item.merge({"name": mark["name"]})
	item.merge({"x": mark["x"], "y": mark["y"], "z": mark["z"]})
	box.append(item)
	_next_id += 1
	return ""


## The pending mark `id` of the ship, removed from its inbox; {} when there is none.
func take(ship: int, id: int) -> Dictionary:
	var box: Array = _inbox.get(ship, [])
	for i: int in box.size():
		if box[i]["id"] == id:
			return box.pop_at(i)
	return {}


func log_of(ship: int) -> Array:
	return (_log.get(ship, []) as Array).duplicate(true)


## Appends a log entry (the newest MAX_LOG stay) and returns it.
func log_entry(ship: int, tick: int, key: String, args: Dictionary = {}) -> Dictionary:
	var entries: Array = _log.get_or_add(ship, [])
	var entry: Dictionary = {"tick": tick, "key": key, "args": args}
	entries.append(entry)
	if entries.size() > MAX_LOG:
		entries.pop_front()
	return entry


## A run reset: everything of the ship cleared.
func reset(ship: int) -> void:
	_zones.erase(ship)
	_routes.erase(ship)
	_inbox.erase(ship)
	_log.erase(ship)


func _route_slots(ship: int) -> Array:
	if not _routes.has(ship):
		var slots: Array = []
		for i: int in MAX_ROUTES:
			slots.append([])
		_routes[ship] = slots
	return _routes[ship]


# --- strand F ---
## The ship's approach lanes (P5): one MARK item per accepted clearance card of its board, at
## the card's site (WAITS ON B: SiteTable.point, A's stub until B lands), with the seconds
## until the window opens and closes (negative once past), {card, x, y, z, open_s, close_s,
## by}. A lane exists while its card is ACCEPTED: docking, expiry or a decline remove it.
static func lane_items(world: SimWorld, ship: int) -> Array:
	var out: Array = []
	for card: int in world.story.size():
		var window: Array[int] = StoryRules.lane_window(world, card)
		if (
			window.is_empty()
			or world.story.state[card] != StoryTable.State.ACCEPTED
			or not Story.visible_to(world, card, ship)
			or world.story.site[card] < 0
			or world.story.site[card] >= world.sites.size()
		):
			continue
		var at: PackedFloat64Array = world.sites.point(world.story.site[card])
		(
			out
			. append(
				{
					"card": card,
					"x": at[0],
					"y": at[1],
					"z": at[2],
					"open_s": (window[0] - world.tick) * SimWorld.DT,
					"close_s": (window[1] - world.tick) * SimWorld.DT,
					"by": "comms",
				}
			)
		)
	return out

# --- end strand F ---
