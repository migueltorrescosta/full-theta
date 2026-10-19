class_name NetClaims
extends RefCounted
## Claims on shared stations (FT-NET-022 to FT-NET-024, FT-NET-044, D18, STN-3): per
## ship, item -> the session holding it ("flight", "shield_facing", "mount:1",
## "crew:0"; StationViews). A claimed item takes commands only from its claimer; an
## unclaimed one from anyone at its station. A player alone on a station holds all its
## claims (settle()): when a second player joins, the first keeps them, and they free
## up on release, station change or grace expiry (PROVISIONAL: STN-3 leaves the join
## case open; keeping control with the player already flying is the conservative
## choice). Pure: ServerSession supplies who covers which station.

## Ship -> {item: session id}.
var _held: Dictionary = {}


## The session holding an item, or -1.
func holder(ship: int, item: String) -> int:
	return (_held.get(ship, {}) as Dictionary).get(item, -1)


## Claims an item for a session; false if another session holds it.
func claim(ship: int, item: String, session: int) -> bool:
	var h: int = holder(ship, item)
	if h >= 0 and h != session:
		return false
	(_held.get_or_add(ship, {}) as Dictionary)[item] = session
	return true


## Releases an item the session holds; false if it doesn't hold it.
func release(ship: int, item: String, session: int) -> bool:
	if holder(ship, item) != session:
		return false
	(_held[ship] as Dictionary).erase(item)
	return true


## The items a session holds on a ship, sorted.
func items_of(ship: int, session: int) -> Array[String]:
	var out: Array[String] = []
	var held: Dictionary = _held.get(ship, {})
	for item: String in held:
		if held[item] == session:
			out.append(item)
	out.sort()
	return out


## Releases every item of the session except those of the stations in keep (a station
## change keeps the claims of the stations the new pick still covers); returns
## [ship, item] for each released item.
func release_session(session: int, keep: Array[String] = []) -> Array:
	var out: Array = []
	for ship: int in _held:
		var held: Dictionary = _held[ship]
		for item: String in held.keys():
			if held[item] == session and not keep.has(StationViews.station_of_item(item)):
				held.erase(item)
				out.append([ship, item])
	return out


## A session alone on a station holds every free item of it. covering: station ->
## session ids holding it on this ship; items: station -> the ship's items
## (StationViews.claim_items). Returns [item, session] for each new claim.
func settle(ship: int, covering: Dictionary, items: Dictionary) -> Array:
	var out: Array = []
	for station: String in items:
		var who: Array = covering.get(station, [])
		if who.size() != 1:
			continue
		for item: String in items[station]:
			if holder(ship, item) < 0:
				claim(ship, item, who[0])
				out.append([item, who[0]])
	return out


## item -> session id for a ship.
func table(ship: int) -> Dictionary:
	return (_held.get(ship, {}) as Dictionary).duplicate()
