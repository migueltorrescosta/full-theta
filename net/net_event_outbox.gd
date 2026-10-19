class_name NetEventOutbox
extends RefCounted
## Server side of one session's reliable ordered event stream (FT-NET-011, FT-NET-037),
## on the net thread. Events get the session's next sequence number and stay here until
## the client acknowledges them, across stalls and reconnects: an event is never
## dropped. `pushed` is the newest seq handed to the current connection's send queue;
## a new connection restarts it at the acknowledged seq, so the client gets every event
## it hasn't acknowledged and drops duplicates (NetEventInbox).

var next_seq: int = 1
var acked: int = 0
var pushed: int = 0
## [seq, message bytes], ascending.
var _items: Array = []


## Adds an event; returns its seq.
func add(tick: int, type: String, payload: Dictionary) -> int:
	var seq: int = next_seq
	next_seq += 1
	_items.append([seq, NetProtocol.event(seq, tick, type, payload)])
	return seq


func ack(seq: int) -> void:
	if seq <= acked:
		return
	acked = mini(seq, next_seq - 1)
	while not _items.is_empty() and int(_items[0][0]) <= acked:
		_items.pop_front()


## The messages of the events after `pushed`, oldest first; marks them pushed.
func take_unpushed() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for item: Array in _items:
		if int(item[0]) > pushed:
			out.append(item[1])
			pushed = item[0]
	return out


## A new connection: everything not acknowledged goes again.
func restart() -> void:
	pushed = acked


## Events not yet acknowledged.
func pending() -> int:
	return _items.size()
