class_name NetSession
extends RefCounted
## One player's session on the server (main thread): identity, token, connection,
## catalogue pick and rate limit. It outlives its connection: a client that presents
## the token gets it back (FT-NET-025, FT-NET-026), with its pick and claims while its
## grace period runs (FT-NET-033), and after that with whatever is still free.

var id: int = 0
var token: String = ""
var name: String = ""
## "desktop", "web" or "bot" (Hello.kind).
var client_kind: String = ""
## Transport connection id, or -1 while disconnected.
var conn: int = -1
## Wall-clock time of the last disconnect (us), outside sim/ (FT-NET-033).
var dropped_us: int = 0
## Picked ship and catalogue entry (StationViews), or -1 / "" on the pick screen.
var ship: int = -1
var entry: String = ""
## Difficulty-toggle set of the view key (D14, D69); one set for M1.
var toggles: String = StationViews.DEFAULT_TOGGLES
## The shortcuts shared to the session's ship that haven't expired (NetShares, D210).
var shares: Array[StringName] = []
## The grace period ended: pick and claims were released; last_* remember them for a
## rejoin (FT-NET-026).
var lapsed: bool = false
var last_ship: int = -1
var last_entry: String = ""
var last_claims: Array[String] = []
## Presented the server's host secret in Hello (D127): the host client.
var is_host: bool = false
## Command rate limit (FT-NET-006).
var bucket: NetTokenBucket


func _init(session_id: int, rate: float, burst: float) -> void:
	id = session_id
	bucket = NetTokenBucket.new(rate, burst)


func connected() -> bool:
	return conn >= 0


func has_pick() -> bool:
	return ship >= 0 and entry != ""


## The view key the snapshot builder encodes for this session, or "" without a pick.
func view_key() -> String:
	return StationViews.key(ship, entry, view_code()) if has_pick() else ""


## The toggle code the view filters by: the toggles and the shortcuts shared so far
## (ViewFilter.of).
func view_code() -> String:
	return ViewFilter.code_with(toggles, shares)
