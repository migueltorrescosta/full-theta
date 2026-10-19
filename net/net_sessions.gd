class_name NetSessions
extends RefCounted
## Session tokens (FT-NET-025, FT-NET-026, FT-NET-033; promoted from S4Sessions). The
## server issues a token at first join; presenting it while the session is connected
## (a takeover: the old socket may not have closed yet) or within the grace period
## after a drop returns the same NetSession. T045 adds the pause and claim rules on top.
##
## Times are wall-clock microseconds supplied by the caller, outside sim/.

const DEFAULT_GRACE_US: int = 10_000_000

var grace_us: int = DEFAULT_GRACE_US
var _by_token: Dictionary[String, NetSession] = {}
var _crypto: Crypto = Crypto.new()


func _init(grace: int = DEFAULT_GRACE_US) -> void:
	grace_us = grace


## Gives the session a fresh random token (128 bits, hex) and registers it.
func issue(session: NetSession) -> String:
	var token: String = _crypto.generate_random_bytes(16).hex_encode()
	session.token = token
	_by_token[token] = session
	return token


## The session for a valid token, or null. A connected session never expires, so a
## restarted client can take it over before its old socket closes.
func resume(token: String, now_us: int) -> NetSession:
	var session: NetSession = _by_token.get(token)
	if session == null:
		return null
	if _expired(session, now_us):
		_by_token.erase(token)
		return null
	return session


## Marks the session disconnected at now_us; its grace period starts.
func drop(session: NetSession, now_us: int) -> void:
	session.conn = -1
	session.dropped_us = now_us


func get_session(token: String) -> NetSession:
	return _by_token.get(token)


func all() -> Array[NetSession]:
	var out: Array[NetSession] = []
	out.assign(_by_token.values())
	return out


func size() -> int:
	return _by_token.size()


## Removes the sessions whose grace ran out and returns them.
func expire(now_us: int) -> Array[NetSession]:
	var gone: Array[NetSession] = []
	for session: NetSession in _by_token.values():
		if _expired(session, now_us):
			gone.append(session)
	for session: NetSession in gone:
		_by_token.erase(session.token)
	return gone


func _expired(session: NetSession, now_us: int) -> bool:
	return not session.connected() and now_us - session.dropped_us > grace_us
