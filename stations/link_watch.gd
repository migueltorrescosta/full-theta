class_name LinkWatch
extends RefCounted
## What the shell does about its connection (R24-3, R11-2): retry a dropped one every
## RESUME_MS, give up after GIVE_UP_MS, never retry a rejected one, and never retry after the
## server closed it because another connection took the session over (close 4001), where
## retrying only makes two windows swap the session for ever. Pure: the shell feeds it the
## client's state and the time and acts on `status`.

enum Status { OK, RETRYING, GAVE_UP, REJECTED, TAKEN_OVER }

## Retry a dropped connection this often (ms).
const RESUME_MS: int = 2000
## Stop retrying after this long without a connection (ms).
const GIVE_UP_MS: int = 20_000

var status: Status = Status.OK

var _down_since: int = -1
var _resume_at: int = 0


## Reads the client's state at `now` ms; returns true when the shell should call
## `client.resume()` now.
func update(client: NetClient, now: int) -> bool:
	var retry: bool = false
	match client.state:
		NetClient.State.WELCOMED:
			status = Status.OK
			_down_since = -1
		NetClient.State.REJECTED:
			status = Status.REJECTED
		NetClient.State.CLOSED:
			retry = _closed(client, now)
		_:
			# CONNECTING (a retry in flight) and IDLE: still down.
			_note_down(now)
	return retry


## The closed connection's turn: gives up, notes a takeover, or asks for a retry.
func _closed(client: NetClient, now: int) -> bool:
	if status == Status.TAKEN_OVER or status == Status.GAVE_UP:
		return false
	if client.close_code == NetProtocol.CLOSE_TAKEN_OVER:
		status = Status.TAKEN_OVER
		return false
	_note_down(now)
	if now - _down_since >= GIVE_UP_MS:
		status = Status.GAVE_UP
		return false
	if now < _resume_at:
		return false
	_resume_at = now + RESUME_MS
	return true


## Tries again from scratch (the "Take back" and "Try again" buttons): the client resumes at
## once and the clock starts over.
func restart(now: int) -> void:
	status = Status.RETRYING
	_down_since = now
	_resume_at = now + RESUME_MS


func _note_down(now: int) -> void:
	if _down_since < 0:
		_down_since = now
	if status == Status.OK:
		status = Status.RETRYING
