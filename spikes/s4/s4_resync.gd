class_name S4Resync
extends RefCounted
## Per-client snapshot policy: deltas while the client keeps up, nothing while it
## lags, one full snapshot once its queue has drained (FT-NET-037, TECH-2).
## Candidate for promotion to T045 (#6).
##
## Lag is measured end to end: snapshots sent but not yet acknowledged. On
## loopback the kernel socket buffers absorb seconds of traffic before
## WebSocketPeer's own outbound buffer grows, so the stall triggers are the
## three in D106: ack lag, a failed send (a full outbound buffer fails the
## send) and the high-lane queue size.

enum Action { NONE, DELTA, FULL }

## Stalled at more than this many unacknowledged snapshots: more than 15
## unacknowledged (≈ 533 ms at 30 Hz).
var lag_limit: int = 15
## High-lane queued bytes that mark the client as stalled.
var queued_limit: int = 256 * 1024

var acked_seq: int = -1
var last_sent_seq: int = -1
var last_full_seq: int = -1
var need_full: bool = true
var stalled: bool = false
var stall_count: int = 0
var full_count: int = 0


func _init(lag: int = 15) -> void:
	lag_limit = lag


func on_ack(seq: int) -> void:
	acked_seq = maxi(acked_seq, seq)


## Records a failed send as a stall. The caller must also close the connection:
## the chunk that failed has left the send queue, so a message (possibly the
## `last_sent_seq` snapshot, which the drain check waits for) is lost. The
## client then resumes with its token and gets a full snapshot.
func on_send_error() -> void:
	_mark_stalled()


## Forces the next decision to be a full snapshot (join, resume, test hook).
func force_full() -> void:
	need_full = true


## Decides what to send for the next snapshot; `queued` is the high-lane bytes
## still in our queue.
func decide(queued: int) -> Action:
	if not stalled and last_sent_seq >= 0 and (lag() > lag_limit or queued > queued_limit):
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


## Base for a delta: the newest snapshot the client is sure to hold. TCP keeps
## order, so the last full snapshot counts even before it is acknowledged.
func delta_base() -> int:
	return maxi(acked_seq, last_full_seq)


func on_sent(seq: int, full: bool) -> void:
	last_sent_seq = seq
	if full:
		last_full_seq = seq
		need_full = false
		stalled = false
		full_count += 1


## Events are held while a full snapshot is due; the full snapshot carries them.
func holds_events() -> bool:
	return need_full or stalled


func _mark_stalled() -> void:
	if not stalled:
		stall_count += 1
	stalled = true
	need_full = true
