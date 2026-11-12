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
## Picked ship and seat (StationCatalogue), or -1 / "" on the pick screen.
var ship: int = -1
var seat: String = ""
## Difficulty-toggle set of the stream key (D14, D69); one set for M1.
var toggles: String = StationCatalogue.DEFAULT_TOGGLES
## The shortcuts shared to the session's ship that haven't expired (NetShares, D210).
var shares: Array[StringName] = []
## The grace period ended: pick and claims were released; last_* remember them for a
## rejoin (FT-NET-026).
var lapsed: bool = false
var last_ship: int = -1
var last_seat: String = ""
## The last ship the session held a pick on, -1 before its first: its side in a run going on,
## also after Back to ships (#35 A10, NetGame.pick_rule).
var home_ship: int = -1
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
	return ship >= 0 and seat != ""


## Holds a crew pick: a station, not the Captain seat or a viewer (R06-11).
func is_crew() -> bool:
	return has_pick() and StationCatalogue.is_crew(seat)


## Holds the Relay seat (alone or with other stations).
func is_relay() -> bool:
	return has_pick() and CrewMarks.role_of(seat) == CrewMarks.Role.RELAY


## Has a pick on `on_ship`: the audience of a ship's events (R06-9).
func on_ship(on_ship_id: int) -> bool:
	return ship == on_ship_id and has_pick()


## A connected crew player: a voter of D128 and D178.
func is_live_crew() -> bool:
	return connected() and is_crew()


## The stream key the snapshot builder encodes for this session, or "" without a pick.
func stream_key() -> String:
	return StationCatalogue.key(ship, seat, stream_code()) if has_pick() else ""


## The toggle code the view filters by: the toggles and the shortcuts shared so far
## (ShortcutFilter.of).
func stream_code() -> String:
	return ShortcutFilter.code_with(toggles, shares)
