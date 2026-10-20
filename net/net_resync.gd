class_name NetResync
extends RefCounted
## Per-client snapshot policy: deltas while the client keeps up, nothing while it
## lags, one full snapshot once its queue has drained (FT-NET-037, TECH-2).
## Promoted from S4Resync (T041).
##
## Lag is measured end to end: snapshots sent but not yet acknowledged. On
## loopback the kernel socket buffers absorb seconds of traffic before
## WebSocketPeer's own outbound buffer grows, so the stall triggers are the
## three in D106: ack lag, a failed send (the socket write failed; NetTransport
## also closes the connection) and the high-lane queue size. A client that can't apply
## a snapshot asks for a full one (Ack snap -1).

enum Action { NONE, DELTA, FULL }

## Stalled at more than this many unacknowledged snapshots (≈ 533 ms at 30 Hz).
const LAG_LIMIT: int = 15
## High-lane queued bytes that mark the client as stalled (NetTransport closes a
## connection without a view key past it).
const QUEUED_LIMIT: int = 256 * 1024

var lag_limit: int = LAG_LIMIT

var acked_seq: int = -1
var last_sent_seq: int = -1
var last_full_seq: int = -1
var need_full: bool = true
var stalled: bool = false
var stall_count: int = 0


func _init(lag: int = LAG_LIMIT) -> void:
	lag_limit = lag


## An Ack's snap: the newest snapshot the client applied, or -1 when it couldn't apply
## one and needs a full snapshot (the next decision sends one).
func on_ack(seq: int) -> void:
	if seq < 0:
		need_full = true
		return
	acked_seq = maxi(acked_seq, seq)


## Records a failed send as a stall. The caller must also close the connection:
## the chunk that failed has left the send queue, so a message (possibly the
## `last_sent_seq` snapshot, which the drain check waits for) is lost. The
## client then resumes with its token and gets a full snapshot.
func on_send_error() -> void:
	_mark_stalled()


## Forces the next decision to be a full snapshot (a new view key).
func force_full() -> void:
	need_full = true


## Decides what to send for the next snapshot; `queued` is the high-lane bytes
## still in our queue.
func decide(queued: int) -> Action:
	if not stalled and last_sent_seq >= 0 and (lag() > lag_limit or queued > QUEUED_LIMIT):
		_mark_stalled()
	if stalled:
		# Drained: the client has acknowledged everything we sent and nothing
		# of the high lane is left in our queue.
		if acked_seq >= last_sent_seq and queued == 0:
			return Action.FULL
		return Action.NONE
	if need_full:
		return Action.FULL
	return Action.DELTA


## Snapshots sent and not yet acknowledged. Sequence numbers skipped while
## stalled don't count: a resync full snapshot restarts the count at one.
func lag() -> int:
	return last_sent_seq - maxi(acked_seq, last_full_seq - 1)


func on_sent(seq: int, full: bool) -> void:
	last_sent_seq = seq
	if full:
		last_full_seq = seq
		need_full = false
		stalled = false


## Events are held while a full snapshot is due; the full snapshot carries them.
func holds_events() -> bool:
	return need_full or stalled


func _mark_stalled() -> void:
	if not stalled:
		stall_count += 1
	stalled = true
	need_full = true
