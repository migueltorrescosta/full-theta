class_name NetEventInbox
extends RefCounted
## Client side of the reliable event stream (FT-NET-011, FT-NET-037): delivers
## events in sequence order exactly once, whether they come alone or inside a
## full snapshot. Promoted from S4EventInbox (T041).

var last_seq: int = 0
var duplicates: int = 0
var _pending: Dictionary = {}


func _init(start_after: int = 0) -> void:
	last_seq = start_after


## Takes one event ({"seq": int, ...}); returns the events now deliverable, in order.
func receive(event: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seq: int = event["seq"]
	if seq <= last_seq or _pending.has(seq):
		duplicates += 1
		return out
	_pending[seq] = event
	while _pending.has(last_seq + 1):
		last_seq += 1
		out.append(_pending[last_seq])
		_pending.erase(last_seq)
	return out


## Events received ahead of a gap, waiting for it to fill.
func waiting() -> int:
	return _pending.size()
