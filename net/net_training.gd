class_name NetTraining
extends RefCounted
## Solo station lessons on the server (D303, FT-MIS-039): the Training message, and the bots
## that crew the other stations of a lesson. A client asks for a lesson at a station, or the
## crew drill ("" = the Shakedown with a crew); a server with no other crew switches to a
## fresh Shakedown and seats and starts the sender, otherwise it answers `busy` and nothing
## changes for the players already on it. The bots take no session: they are seats that
## count for coverage (NetLobby.seats_of) and press Next for their half of a pair
## step (TrainingPartners). docs/protocol.md, "Solo training".

const BUSY: String = "busy"
const BAD_STATION: String = "bad_station"

var game: NetGame
## The station played alone, or "" outside a solo lesson.
var solo: String = ""
## Switches the server over for (session, station); set by NetServer.
var hook: Callable
## A lesson to start for the host as soon as it joins (the --solo flag), or "".
var solo_on_join: String = ""


func _init(net_game: NetGame) -> void:
	game = net_game
	game.add_handler(NetProtocol.Type.TRAINING, _on_training)


## The crew stations the bots hold in a solo lesson: all but the player's.
func bot_seats() -> Array:
	var out: Array = []
	if solo != "":
		for station: String in StationCatalogue.CREW:
			if station != solo:
				out.append(station)
	return out


## How many other sessions hold a pick: the crew a lesson must not disturb.
func crew_besides(s: NetSession) -> int:
	var n: int = 0
	for o: NetSession in game.by_id.values():
		if o != s and o.has_pick():
			n += 1
	return n


## The host's first join starts its --solo lesson.
func on_join(s: NetSession) -> void:
	if solo_on_join != "" and s.is_host and hook.is_valid():
		var station: String = solo_on_join
		solo_on_join = ""
		hook.call(s, station)


## Seats the session at `seat` of the ship and starts the lesson for it, Ready (the coverage
## check passes through the bots; NetLobby.start without the host rule).
func seat_and_start(s: NetSession, ship: int, seat: String) -> void:
	game.lobby.move(s, ship, seat)
	game.lobby.start(s, true)


func _on_training(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var station: String = msg["station"]
	var reason: String = ""
	var extra: Dictionary = {}
	if (
		station != ""
		and not StationCatalogue.CREW.has(station)
		and station != StationCatalogue.CAPTAIN
	):
		reason = BAD_STATION
		extra = {"station": station}
	elif not hook.is_valid():
		reason = NetGame.NOT_IMPLEMENTED
	elif crew_besides(s) > 0:
		reason = BUSY
		extra = {"players": crew_besides(s)}
	if game.refuse(s, NetProtocol.Type.TRAINING, reason, extra):
		return
	hook.call(s, station)
