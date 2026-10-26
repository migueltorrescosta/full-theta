class_name CrewPings
extends RefCounted
## Ping rules, outside the sim like marks (CrewMarks): a per-session rate limit
## (FT-SPA-017) and the silent "copy" (FT-SPA-031): a ping on an item someone else
## pinged on the same ship within COPY_US names that first pinger. Points never copy
## (no two are the same item). Wall-clock microseconds come from the caller.

## PROVISIONAL (FT-SPA-017): one ping per 0.5 s, burst 3.
const RATE: float = 2.0
const BURST: float = 3.0
## A ping pulses for 3 s (FT-SPA-016); another ping on its item meanwhile is a copy.
const COPY_US: int = 3_000_000
const BAD_PING: String = "bad_ping"
## A `zone` ping names a marked zone of the ship's `zones` event by its id (>= 0), a launched
## probe's bubble as -1 - the probe's serial, or a sim hazard the faction knows as
## HAZARD_ZONE_BASE - its index (D222). The probe ids stay above HAZARD_ZONE_BASE.
const HAZARD_ZONE_BASE: int = -1000

## Session id -> NetTokenBucket.
var _buckets: Dictionary[int, NetTokenBucket] = {}
## Ship -> item key -> [time us, session id, name] of its original ping.
var _recent: Dictionary[int, Dictionary] = {}


## Takes a token from the session's ping limit; false when it is empty.
func take(session: int, now_us: int) -> bool:
	return _buckets.get_or_add(session, NetTokenBucket.new(RATE, BURST)).take(now_us)


## Records a ping on the item and returns the original pinger's name when it is a copy,
## else "" (and this ping becomes the item's original).
func copy_of(ship: int, kind: String, id: int, session: int, name: String, now_us: int) -> String:
	if kind == "point":
		return ""
	var key: String = "%s:%d" % [kind, id]
	var recent: Dictionary = _recent.get_or_add(ship, {})
	var first: Array = recent.get(key, [])
	if not first.is_empty() and now_us - int(first[0]) < COPY_US and first[1] != session:
		return first[2]
	recent[key] = [now_us, session, name]
	return ""


func reset(ship: int) -> void:
	_recent.erase(ship)
