class_name IdleExitTimer
extends RefCounted
## "No connections for N minutes, then exit" for the server (FT-NET-003,
## TECH-8), so orphaned servers don't pile up. Runs on wall clock passed in by
## the caller (`Time.get_unix_time_from_system()`), since the sim may be
## paused. A limit of 0 or less never expires (a dedicated server may want
## that).

var limit_s: float = 0.0
## Unix time the server last became empty, or -1 while someone is connected.
var _idle_since: float = -1.0


func _init(minutes: float) -> void:
	limit_s = minutes * 60.0


## Call once per frame (or less often) with the open connection count. Returns
## true once the server has had no connections for the whole limit.
func update(connections: int, now_unix: float) -> bool:
	if connections > 0:
		_idle_since = -1.0
		return false
	if _idle_since < 0.0:
		_idle_since = now_unix
	return limit_s > 0.0 and now_unix - _idle_since >= limit_s


## Seconds without connections so far (0 while someone is connected).
func idle_seconds(now_unix: float) -> float:
	return 0.0 if _idle_since < 0.0 else now_unix - _idle_since
