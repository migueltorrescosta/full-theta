class_name NetSessions
extends RefCounted
## Session tokens and the reconnect grace (FT-NET-025, FT-NET-026, FT-NET-033;
## promoted from S4Sessions). The server issues a token at first join; presenting it
## returns the same NetSession: connected (a takeover: the old socket may not have
## closed yet), within the grace period after a drop (pick and claims kept), or after
## it (the session lapsed: ServerSession released its pick and claims and restores
## what is still free). Tokens live as long as the server (provisional: see
## docs/protocol.md, Rates and limits).
##
## Times are wall-clock microseconds supplied by the caller, outside sim/, so the grace
## runs while the sim is paused.

const DEFAULT_GRACE_US: int = 15_000_000

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


## The session for a token, or null. A connected session never lapses, so a restarted
## client can take it over before its old socket closes. A session whose grace ran out
## and that expire() hasn't reported yet lapses here first.
func resume(token: String, now_us: int) -> NetSession:
	var session: NetSession = _by_token.get(token)
	if session != null and _expired(session, now_us):
		session.lapsed = true
	return session


## Marks the session disconnected at now_us; its grace period starts.
func drop(session: NetSession, now_us: int) -> void:
	session.conn = -1
	session.dropped_us = now_us


func get_session(token: String) -> NetSession:
	return _by_token.get(token)


## Every session the server issued a token to, lapsed ones included.
func all() -> Array[NetSession]:
	var out: Array[NetSession] = []
	out.assign(_by_token.values())
	return out


## Marks the sessions whose grace ran out as lapsed and returns them (each once).
func expire(now_us: int) -> Array[NetSession]:
	var gone: Array[NetSession] = []
	for session: NetSession in _by_token.values():
		if _expired(session, now_us):
			session.lapsed = true
			gone.append(session)
	return gone


func _expired(session: NetSession, now_us: int) -> bool:
	return not session.lapsed and not session.connected() and now_us - session.dropped_us > grace_us
