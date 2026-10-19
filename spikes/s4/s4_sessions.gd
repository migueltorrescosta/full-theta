class_name S4Sessions
extends RefCounted
## Session tokens and seats (FT-NET-025, FT-NET-026, FT-NET-033). The server
## issues a token at first join; presenting it within the grace period returns the
## same seat and event cursor. Candidate for promotion to T045 (#6).
##
## Times are wall-clock microseconds supplied by the caller, outside sim/.

const DEFAULT_GRACE_US: int = 10_000_000

var grace_us: int = DEFAULT_GRACE_US
## token -> {"seat": Dictionary, "acked_ev": int, "connected": bool, "dropped_us": int}
var _by_token: Dictionary = {}
var _crypto: Crypto = Crypto.new()


func _init(grace: int = DEFAULT_GRACE_US) -> void:
	grace_us = grace


func issue(seat: Dictionary, acked_ev: int) -> String:
	var token: String = _crypto.generate_random_bytes(16).hex_encode()
	_by_token[token] = {"seat": seat, "acked_ev": acked_ev, "connected": true, "dropped_us": 0}
	return token


## Returns the session for a valid token (and marks it connected), or {}.
## A token still marked connected is taken over: the old socket may not have
## closed yet when a killed client restarts.
func resume(token: String, now_us: int) -> Dictionary:
	if not _by_token.has(token):
		return {}
	var session: Dictionary = _by_token[token]
	if not session["connected"] and now_us - int(session["dropped_us"]) > grace_us:
		_by_token.erase(token)
		return {}
	session["connected"] = true
	return session


func drop(token: String, now_us: int) -> void:
	if _by_token.has(token):
		var session: Dictionary = _by_token[token]
		session["connected"] = false
		session["dropped_us"] = now_us


func set_acked_event(token: String, seq: int) -> void:
	if _by_token.has(token):
		var session: Dictionary = _by_token[token]
		session["acked_ev"] = maxi(int(session["acked_ev"]), seq)


func get_session(token: String) -> Dictionary:
	return _by_token.get(token, {})


## Removes sessions whose grace ran out; returns their tokens.
func expire(now_us: int) -> Array[String]:
	var gone: Array[String] = []
	for token: String in _by_token.keys():
		var session: Dictionary = _by_token[token]
		if not session["connected"] and now_us - int(session["dropped_us"]) > grace_us:
			gone.append(token)
	for token: String in gone:
		_by_token.erase(token)
	return gone


## Lowest event seq any live session still needs (for trimming the event log).
func min_acked_event(default_value: int) -> int:
	var low: int = default_value
	for session: Dictionary in _by_token.values():
		low = mini(low, int(session["acked_ev"]))
	return low
