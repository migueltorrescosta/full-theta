# gdlint: disable=max-public-methods
class_name NetLobby
extends RefCounted
## The lobby and the coverage pause on the server (T043, T045; F2, R13-3): NetGame owns
## one and keeps the handshake, the session maps, claims and event routing. It holds:
## - picks (pick_rule: one Captain per ship, FT-NET-016; no mid-run change that breaks
##   coverage, FT-NET-043), the coverage check (NetCoverage), each player's Ready, Start
##   (FT-NET-019, #37 C1) and the session's data toggles (FT-PAIR-017), sent to clients as
##   `lobby` events;
## - the ships that started, the ships abandoned during a pause (D96) and the coverage pause
##   (FT-NET-034, FT-NET-035): NetServer steps the sim only while NetGame.sim_running();
## - the abandon vote (D128, D241) and the takeover of an uncovered station (FT-NET-041,
##   FT-NET-042).
## - the bots (#40 D1, D2): a dropped crew player's stations go to a stand-in bot when the
##   grace ends, unless the host ticked "Pause when someone drops" (drop_pause, gp-02); with
##   "Fill light stations with bots" (fill_bots, gp-03) the light stations no player holds get
##   bots at Start, so two players may start a ship. Bots count for coverage; a player who
##   takes a bot's station sends it away (StandInCrew acts for the rest, NetServer);
## - guests (#40 D10, gp-04): an eliminated crew handed over to a friendly ship in co-op or
##   TEAMS may take its free light stations; guests never count for coverage.
## Messages: Pick, Release, Ready, Start, Toggles, Abandon, AbandonVote, Takeover.

## Ships that started (FT-NET-019). Read it through is_launched, launched_ships
## and any_launched; launch() adds one.
var launched: Dictionary[int, bool] = {}
## Ships abandoned during a pause: out of play from then on, until the sim's
## AbandonShipCommand applies on resume (D96). A pending-command projection: read it through
## in_play.
var abandoned: Dictionary[int, bool] = {}
## Paused ships still in play: ship -> uncovered stations. The universe is paused while this
## is not empty (FT-NET-034).
var paused: Dictionary[int, Array] = {}
## Ship -> its abandon vote, during a pause or a run (D128, D241).
var votes: Dictionary[int, NetVote] = {}
## The data-shortcut toggle set of the session, one for every ship (FT-PAIR-017): the host
## changes it in the lobby until a ship starts; sessions' stream keys follow.
var toggles: DataToggles = DataToggles.of_preset(StationCatalogue.DEFAULT_TOGGLES)
## The host's options (GameMode, the Game setup sheet): a dropped player's grace ends in the
## coverage pause (FT-NET-034) rather than a stand-in (gp-02); fill light stations with bots
## at Start (gp-03). Both off by default.
var drop_pause: bool = false
var fill_bots: bool = false
## Ship -> station -> [session id, name]: the bots holding the ship's stations, a stand-in for
## a dropped player (its session and name) or a fill bot (-1, "").
var bots: Dictionary[int, Dictionary] = {}
## The stand-in numbers (StandInDef.fill_min_players); NetServer sets the loaded one.
var stand_in: StandInDef = StandInDef.new()

var game: NetGame:
	get:
		return _game.get_ref() as NetGame

var _game: WeakRef
## Ship -> the lobby payload last sent.
var _lobby_sent: Dictionary[int, Dictionary] = {}
## Something a lobby state depends on may have changed since the last publish().
var _dirty: bool = true


func _init(net_game: NetGame) -> void:
	_game = weakref(net_game)
	net_game.add_handler(NetProtocol.Type.PICK, _on_pick)
	net_game.add_handler(NetProtocol.Type.RELEASE, _on_release)
	net_game.add_handler(NetProtocol.Type.READY, _on_ready)
	net_game.add_handler(NetProtocol.Type.START, _on_start)
	net_game.add_handler(NetProtocol.Type.TOGGLES, _on_toggles)
	net_game.add_handler(NetProtocol.Type.ABANDON, _on_abandon)
	net_game.add_handler(NetProtocol.Type.ABANDON_VOTE, _on_abandon_vote)
	net_game.add_handler(NetProtocol.Type.TAKEOVER, _on_takeover)


# --- Queries. ---


func is_launched(ship: int) -> bool:
	return launched.has(ship)


## Whether any ship started: the universe runs (outside a pause) and the lobby is closed.
func any_launched() -> bool:
	return not launched.is_empty()


func launched_ships() -> Array[int]:
	var out: Array[int] = []
	out.assign(launched.keys())
	return out


## Whether a coverage pause holds anywhere (the universe is stopped).
func any_paused() -> bool:
	return not paused.is_empty()


## A ship that started and is still in the encounter: not destroyed, retreated or
## abandoned (D96). Only these count for the pause.
func in_play(ship: int) -> bool:
	return launched.has(ship) and _in_run(ship)


## The ship's run status is IN_PLAY and no abandon is pending: the lobby payload's `in_play`
## (R12-14: one reader of the pending projection).
func _in_run(ship: int) -> bool:
	return (
		not abandoned.has(ship) and game.world.ships.status[ship] == ShipStateTable.Status.IN_PLAY
	)


## Crew players a ship needs: 3, 2 when the host fills light stations with bots (gp-03), or
## 1 with --dev-all-stations (FT-NET-029).
func min_crew() -> int:
	if game.dev_all:
		return 1
	return stand_in.fill_min_players if fill_bots else NetCoverage.MIN_CREW


## The seats held on a ship by its live sessions (connected or within grace), guests aside,
## and its bots: a solo lesson's, the stand-ins and the fill bots.
func seats_of(ship: int) -> Array:
	var out: Array = game.training.bot_seats() if game.crewable(ship) else []
	out.append_array(bots.get(ship, {}).keys())
	for s: NetSession in game.by_id.values():
		if s.ship == ship and s.seat != "" and s.guest_from < 0:
			out.append(s.seat)
	return out


## The light stations bots will fill at Start (gp-03): before the ship starts, with the
## option on, those no seat covers.
func fill_stations(ship: int) -> Array[String]:
	var out: Array[String] = []
	if not fill_bots or launched.has(ship):
		return out
	var open: Array[String] = NetCoverage.uncovered(seats_of(ship))
	for station: String in StationCatalogue.LIGHT_STATIONS:
		if open.has(station):
			out.append(station)
	return out


## The functional stations neither a seat nor a bot to come covers.
func open_stations(ship: int) -> Array[String]:
	var seats: Array = seats_of(ship)
	seats.append_array(fill_stations(ship))
	return NetCoverage.uncovered(seats)


## Whether the ship passes the coverage check (FT-NET-019): min_crew crew seats, the fill
## bots to come aside, and every station covered.
func covered(ship: int) -> bool:
	return NetCoverage.crew_count(seats_of(ship)) >= min_crew() and open_stations(ship).is_empty()


## The ship's bot stations no session on it covers now (a guest's makes a fill bot give way):
## the ones its StandInCrew acts for.
func active_bots(ship: int) -> Array:
	var out: Array = bots.get(ship, {}).keys()
	for s: NetSession in game.by_id.values():
		if s.ship == ship:
			for station: String in StationCatalogue.stations_of(s.seat):
				out.erase(station)
	return out


## The bot rows of a ship's `lobby` state, in station order: {seat, for}: `for` names the
## dropped player a stand-in holds the station for, "" for a fill bot (also the ones to come
## before Start).
func bot_rows(ship: int) -> Array:
	var held: Dictionary = bots.get(ship, {})
	var to_fill: Array[String] = fill_stations(ship)
	var out: Array = []
	for station: String in StationCatalogue.CREW:
		if held.has(station):
			out.append({"seat": station, "for": held[station][1]})
		elif to_fill.has(station):
			out.append({"seat": station, "for": ""})
	return out


## The grace of a crew player of a ship in play ended (gp-01): each station of its seat goes
## to a stand-in bot that holds it for them.
func stand_in_for(s: NetSession) -> void:
	var held: Dictionary = bots.get_or_add(s.ship, {})
	for station: String in StationCatalogue.stations_of(s.seat):
		held[station] = [s.id, s.name]
	_dirty = true


## Whether a host client is connected (D127). Without one (a dedicated server, or the host
## dropped) any Ready crew player may Start (#37 C1).
func host_here() -> bool:
	for s: NetSession in game.by_id.values():
		if s.is_host and s.connected():
			return true
	return false


## Whether a session counts as Ready: a crew player whose Ready toggle is on, or the host,
## whose Start is its Ready (#37 C1). Captain and viewers are never asked.
static func is_ready(s: NetSession) -> bool:
	return s.is_crew() and (s.ready or s.is_host)


## The names of the ship's crew players who are not Ready yet.
func unready(ship: int) -> Array[String]:
	var out: Array[String] = []
	for s: NetSession in game.by_id.values():
		if s.ship == ship and s.is_crew() and not is_ready(s):
			out.append(s.name)
	return out


## The lobby state of a ship, as sent in `lobby` events (FT-NET-021): `covered` when its
## seats pass the coverage check; each seat holder's session id and Ready (#37 C1).
func lobby_state(ship: int) -> Dictionary:
	var held: Array = seats_of(ship)
	var captain: String = ""
	var holders: Array = []
	for s: NetSession in game.by_id.values():
		if s.ship == ship and s.seat != "":
			(
				holders
				. append(
					{
						"name": s.name,
						"seat": s.seat,
						"session": s.id,
						"ready": is_ready(s),
						"guest": s.guest_from >= 0,
					}
				)
			)
		if s.ship == ship and s.seat == StationCatalogue.CAPTAIN:
			captain = s.name
	return {
		"ship": ship,
		"crew": NetCoverage.crew_count(held),
		"min_crew": min_crew(),
		"uncovered": open_stations(ship),
		"covered": covered(ship),
		"started": launched.has(ship),
		"in_play": _in_run(ship),
		"captain": captain,
		"seats": holders,
		"bots": bot_rows(ship),
		"toggles": toggles.encode(),
	}


## Why a session may not move to (ship, seat), or "" ("" seat: back to the pick
## screen). One Captain per ship (FT-NET-016, CLASH-10, counting one within grace);
## on a ship in play that passes coverage and isn't paused, no change that would make
## it fail (FT-NET-043). During a pause the paused ship's crew may rearrange freely
## (FT-NET-035). Once a run is going, a session that has held a ship picks only ships of
## that ship's faction (ENEMY_SHIP, #35 A10): in PvP nobody, eliminated crews included,
## takes a rival's station; a co-op fleet is one faction.
func pick_rule(s: NetSession, ship: int, seat: String) -> String:
	var world: SimWorld = game.world
	var home: int = s.ship if s.ship >= 0 else s.home_ship
	if (
		ship >= 0
		and home >= 0
		and any_launched()
		and world.faction_of(home) != world.faction_of(ship)
	):
		return FleetMessages.ENEMY_SHIP
	if s.guest_from >= 0 and ship >= 0 and ship != s.guest_from:
		var why: String = _guest_rule(s, ship, seat)
		if why != "":
			return why
	if seat == StationCatalogue.CAPTAIN:
		for o: NetSession in game.by_id.values():
			if o != s and o.ship == ship and o.seat == StationCatalogue.CAPTAIN:
				return NetGame.CAPTAIN_TAKEN
	if (
		s.has_pick()
		and in_play(s.ship)
		and not paused.has(s.ship)
		and NetCoverage.breaks(seats_of(s.ship), min_crew(), s.seat, seat if ship == s.ship else "")
	):
		return CommandGate.BREAKS_COVERAGE
	return ""


# --- Changes. ---


## A lobby state may have changed (a name, a run status): checked at the next publish().
func mark_dirty() -> void:
	_dirty = true


## Starts a ship's run (Start, or a test fixture): the sim steps from now on; with the host's
## option the light stations nobody holds get fill bots (gp-03).
func launch(ship: int) -> void:
	for station: String in fill_stations(ship):
		(bots.get_or_add(ship, {}) as Dictionary)[station] = [-1, ""]
	launched[ship] = true
	_dirty = true


## A relaunched ship is back in play (NetFleet): its pending abandon is over.
func clear_abandoned(ship: int) -> void:
	abandoned.erase(ship)
	_dirty = true


## The run reset (NetGame.restart): every ship back in the lobby, picks kept, nobody Ready.
func reset() -> void:
	for s: NetSession in game.by_id.values():
		s.ready = false
		s.guest_from = -1
	launched.clear()
	abandoned.clear()
	bots.clear()
	refresh_pause()
	for ship: Dictionary in game.crew_ships():
		_sync_captain_seat(ship["id"])


## Moves a session to (ship, seat) without the pick rules, as the server decides it (NetFleet:
## a ship's new id at Start, a handover, a relaunch), with its `picked` event.
func move(s: NetSession, ship: int, seat: String) -> void:
	_answer_pick(s, ship, seat, "")


## Why `s` may not start the game, or "" (FT-NET-019, #37 C1), with the refusal's extra
## fields. The host starts it; with no host connected, any Ready crew player does. Every
## crewed ship must pass coverage (`coverage`, with the ship and its uncovered stations) and
## every crew player be Ready (`not_ready`, with the names). On a fixed world whose universe
## already runs, a crew player starts their own late ship alone, under the same checks.
## `by_server` skips who may press it.
func start_refusal(s: NetSession, by_server: bool = false) -> Array:
	var ships: Array[int] = game.fleet.crewed()
	var who: String = ""
	if any_launched():
		who = NetGame.NOT_CREW if not s.is_crew() else ""
		if who == "" and launched.has(s.ship):
			who = NetGame.STARTED
		ships = [s.ship]
	elif not by_server and not s.is_host:
		who = _presser_refusal(s)
	if who != "":
		return [who, {}]
	if ships.is_empty():
		return [NetGame.NOT_COVERED, {"ship": -1, "uncovered": StationCatalogue.CREW.duplicate()}]
	var names: Array[String] = []
	for ship: int in ships:
		if not covered(ship):
			return [NetGame.NOT_COVERED, {"ship": ship, "uncovered": open_stations(ship)}]
		names.append_array(unready(ship))
	if not names.is_empty():
		return [NetGame.NOT_READY, {"waiting": Array(names)}]
	return ["", {}]


## Why a session other than the host may not press Start before the game: a host is
## connected (`not_host`), or it is not a Ready crew player (`not_crew`, `not_ready`).
func _presser_refusal(s: NetSession) -> String:
	if host_here():
		return NetGame.NOT_HOST
	if not s.is_crew():
		return NetGame.NOT_CREW
	return "" if is_ready(s) else NetGame.NOT_READY


## Start from `s` (FT-NET-019, #37 C1): refused (request_rejected) as start_refusal says;
## otherwise every crewed ship starts together (NetFleet.start_ships, M4-Q4), or the late
## ship alone. `by_server` skips the checks of who may press it (a solo lesson's start,
## NetTraining.seat_and_start).
func start(s: NetSession, by_server: bool = false) -> void:
	if by_server:
		s.ready = true
	var why: Array = start_refusal(s, by_server)
	if game.refuse(s, NetProtocol.Type.START, why[0], why[1]):
		return
	var ships: Array[int] = game.fleet.start_ships(s)
	for ship: int in ships:
		launch(ship)
		game.broadcast(NetProtocol.EVENT_STARTED, {"ship": ship, "tick": game.world.tick})
	if not ships.is_empty():
		game.voice.toggles = toggles.encode()
		var factions: Array = game.crew_ships().map(func(c: Dictionary) -> int: return c["faction"])
		game.voice.start(game.language, factions)
	game.publish()


## Moves a session to (ship, seat): claims of stations it no longer covers are
## released (FT-NET-024: station change), the snapshot view follows, and the claims
## and pause are settled again.
func set_pick(s: NetSession, ship: int, seat: String) -> void:
	var old_ship: int = s.ship
	var was_captain: bool = s.seat == StationCatalogue.CAPTAIN
	if ship != s.ship or seat != s.seat:
		s.ready = false  # a new seat asks again (#37 C1)
	var keep: Array[String] = []
	if ship == old_ship:
		keep = StationCatalogue.stations_of(seat)
	game.release_claims(s, keep)
	s.ship = ship
	s.seat = seat
	# A player (not a guest) who takes a bot's station sends the bot away (gp-01, gp-03).
	if ship >= 0 and s.guest_from < 0 and bots.has(ship):
		for station: String in StationCatalogue.stations_of(seat):
			bots[ship].erase(station)
	if ship >= 0:
		s.home_ship = ship
	s.shares = game.shares.active_of(ship)
	game.transport.set_stream_key(s.id, s.stream_key())
	if votes.has(old_ship):
		votes[old_ship].keep_only(game.connected_crew(old_ship))
		_send_votes(old_ship)
	for each: int in [old_ship, ship]:
		if game.crewable(each):
			game.settle(each)
			if was_captain or seat == StationCatalogue.CAPTAIN:
				_sync_captain_seat(each)
	refresh_pause()


## Tells a training run whether a Captain sits on the ship, through a logged flag the
## TrainingDriver reads: the Captain's track counts only when someone holds the seat
## (Q20, owner 2026-10-26; review 2, M1). Other runs have no use for it.
func _sync_captain_seat(ship: int) -> void:
	var world: SimWorld = game.world
	if world.run_def == null or not world.run_def.training:
		return
	var c: SetFlagCommand = SetFlagCommand.new()
	c.ship_id = ship
	c.flag_name = TrainingDriver.CAPTAIN_SEATED
	c.value = 1 if game.crew.captain_seated(ship) else 0
	world.submit(c)


## Recomputes the paused ships, and marks the lobby states for a check. A grace ending
## (may_pause) pauses every ship in play that fails coverage (FT-NET-034); other changes
## only update or end a pause: a ship that passes again or leaves play is no longer
## paused (FT-NET-035). New or changed paused ships get a `pause` event to every
## client; when none is left the universe resumes and the votes clear (D128).
func refresh_pause(may_pause: bool = false) -> void:
	_dirty = true
	var now: Dictionary[int, Array] = {}
	for ship: int in launched:
		if in_play(ship) and (may_pause or paused.has(ship)):
			var seats: Array = seats_of(ship)
			if not NetCoverage.passes(seats, min_crew()):
				now[ship] = NetCoverage.uncovered(seats)
	var was_paused: bool = not paused.is_empty()
	var changed: Array[int] = []
	for ship: int in now:
		if not paused.has(ship) or paused[ship] != now[ship]:
			changed.append(ship)
	for ship: int in paused:
		if not now.has(ship):
			votes.erase(ship)
	paused = now
	for ship: int in changed:
		game.broadcast(NetProtocol.EVENT_PAUSE, _pause_of(ship))
	# The coverage pause's own resume, `host` false; a host pause has its own (NetHostPause).
	if was_paused and paused.is_empty():
		game.broadcast(NetProtocol.EVENT_RESUME, FleetMessages.resume(game.world.tick, false))


## A session's connection dropped: a vote it cast no longer counts (D128: connected crew only).
func on_disconnect(s: NetSession) -> void:
	for ship: int in votes:
		if votes[ship].voters.has(s.id):
			votes[ship].cast(s.id, "", false)
			_send_votes(ship)


## A (re)joining client starts in sync: the lobby states it may see, the pauses and votes.
func send_to(s: NetSession) -> void:
	for ship: Dictionary in game.crew_ships():
		if _visible(s, ship["id"]):
			game.notify(s, NetProtocol.EVENT_LOBBY, lobby_state(ship["id"]))
	for ship: int in paused:
		game.notify(s, NetProtocol.EVENT_PAUSE, _pause_of(ship))
		_send_votes(ship, s)


## Sends changed lobby states (checked only when something they depend on changed). Returns
## whether it checked (NetFleet.publish follows the same flag).
func publish() -> bool:
	if not _dirty:
		return false
	_dirty = false
	for ship: Dictionary in game.crew_ships():
		var id: int = ship["id"]
		var state: Dictionary = lobby_state(id)
		if _lobby_sent.get(id, {}) != state:
			_lobby_sent[id] = state
			for s: NetSession in game.by_id.values():
				if _visible(s, id):
					game.notify(s, NetProtocol.EVENT_LOBBY, state)
	return true


# --- Handlers. ---


func _on_pick(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var seat: String = msg["seat"]
	var reason: String = ""
	if not game.crewable(ship) or not StationCatalogue.is_seat(seat, game.dev_all):
		reason = NetGame.BAD_PICK
	else:
		reason = pick_rule(s, ship, seat)
	_answer_pick(s, ship, seat, reason)


func _on_release(s: NetSession, _msg: Dictionary, _now_us: int) -> void:
	_answer_pick(s, -1, "", pick_rule(s, -1, ""))


## Ready{ready} (#37 C1): a crew player says they are ready, or no longer; refused from a
## session that is not crew and once its ship has started. The `lobby` and `fleet` events
## show it.
func _on_ready(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var reason: String = ""
	if not s.is_crew():
		reason = NetGame.NOT_CREW
	elif launched.has(s.ship):
		reason = NetGame.STARTED
	if game.refuse(s, NetProtocol.Type.READY, reason, {}):
		return
	if s.ready != bool(msg["ready"]):
		s.ready = msg["ready"]
		_dirty = true
	game.publish()


## Start{} (#37 C1): start().
func _on_start(s: NetSession, _msg: Dictionary, _now_us: int) -> void:
	start(s)


## Toggles{set} (FT-PAIR-017): the host sets the session's data-shortcut toggles from the
## lobby, a preset or an edited set (DataToggles code); locked once any ship has started.
## Every session's view follows, and the lobby events carry the code.
func _on_toggles(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var picked: DataToggles = DataToggles.parse(msg["set"])
	var reason: String = ""
	if not s.is_host:
		reason = NetGame.NOT_HOST
	elif any_launched():
		reason = NetGame.TOGGLES_LOCKED
	elif picked == null:
		reason = NetGame.BAD_TOGGLES
	if game.refuse(s, NetProtocol.Type.TOGGLES, reason, {}):
		return
	if picked.encode() == toggles.encode():
		return
	toggles = picked
	var code: String = picked.encode()
	for each: NetSession in game.by_id.values():
		each.toggles = code
		if each.has_pick():
			game.transport.set_stream_key(each.id, each.stream_key())
	_dirty = true
	game.publish()


## The host abandons a paused ship alone (FT-NET-041, D96, D127); in PvP only its own ship.
func _on_abandon(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var extra: Dictionary = {"ship": ship}
	if s.is_host and game.fleet.rules.is_pvp() and ship != s.ship:
		# M4-F1: in PvP the host forfeits only its own ship; another crew forfeits by its vote.
		game.refuse(s, NetProtocol.Type.ABANDON, NetGame.NOT_YOUR_SHIP, extra)
		return
	if not paused.has(ship):
		var why: String = _run_abandon_refusal(ship)
		if why == "" and not s.is_host:
			why = NetGame.NOT_HOST
		if not game.refuse(s, NetProtocol.Type.ABANDON, why, extra):
			_abandon_run(ship, "host")
	elif not game.refuse(s, NetProtocol.Type.ABANDON, "" if s.is_host else NetGame.NOT_HOST, extra):
		_abandon(ship, "host")
	game.publish()


## A remaining connected crew player of a paused ship casts or withdraws an abandon
## vote; more than half of them abandon it (D128).
func _on_abandon_vote(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var members: Array[int] = game.connected_crew(ship)
	var in_pause: bool = paused.has(ship)
	var why: String = "" if in_pause else _run_abandon_refusal(ship)
	if why == "" and not members.has(s.id):
		why = NetGame.NOT_CREW
	if game.refuse(s, NetProtocol.Type.ABANDON_VOTE, why, {"ship": ship}):
		return
	var passes: bool = votes.get_or_add(ship, NetVote.new()).cast_from(s, msg["vote"], members)
	_send_votes(ship)
	if passes:
		if in_pause:
			_abandon(ship, "vote")
		else:
			_abandon_run(ship, "vote")
	game.publish()


## During a pause, the paused ship's Captain or a viewer, or a player of an allied ship,
## takes an uncovered station (FT-NET-042, M4-Q8, NetFleet.takeover_rule); a crew player of
## the ship changes its pick with Pick.
func _on_takeover(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var ship: int = msg["ship"]
	var seat: String = msg["seat"]
	var reason: String = (
		game.fleet.takeover_rule(s, ship, seat, paused[ship])
		if paused.has(ship)
		else NetGame.NOT_PAUSED
	)
	if game.refuse(s, NetProtocol.Type.TAKEOVER, reason, {"ship": ship, "seat": seat}):
		return
	var from_ship: int = s.ship
	s.guest_from = -1  # a takeover is a crew seat that counts, a guest's too (D96)
	_answer_pick(s, ship, seat, "")
	game.fleet.took_over(s, ship, seat, from_ship)


# --- Internals. ---


## Why a guest may not take `seat` on a friendly `ship` (#40 D10, gp-04), or "": only the
## Viewer or one light station that no other player and no stand-in holds (a fill bot gives
## way).
func _guest_rule(s: NetSession, ship: int, seat: String) -> String:
	if seat == StationCatalogue.VIEWER:
		return ""
	if not StationCatalogue.LIGHT_STATIONS.has(seat):
		return CommandGate.NOT_ALLOWED
	var held: Array = bots.get(ship, {}).get(seat, [-1, ""])
	if int(held[0]) >= 0:
		return FleetMessages.TAKEN
	for o: NetSession in game.by_id.values():
		if o != s and o.ship == ship and StationCatalogue.stations_of(o.seat).has(seat):
			return FleetMessages.TAKEN
	return ""


## Applies an accepted pick, or reports why not: a `picked` event, plus CommandRejected
## (seq -1) for a change refused because it breaks coverage (FT-NET-043).
func _answer_pick(s: NetSession, ship: int, seat: String, reason: String) -> void:
	if reason == "":
		set_pick(s, ship, seat)
	elif reason == CommandGate.BREAKS_COVERAGE:
		game.reject_command(s.id, -1, reason)
	game.notify(s, NetProtocol.EVENT_PICKED, {"ship": ship, "seat": seat, "reason": reason})
	if reason == "" and s.has_pick():
		game.crew.send_to(s)
	game.publish()


## Why the run cannot be abandoned outside a pause (D241, FT-MIS-016), or "": the ship must
## be in a started run.
func _run_abandon_refusal(ship: int) -> String:
	return "" if in_play(ship) else NetGame.NOT_IN_RUN


## The crew's vote passed or the host decided: the sim ends the co-op run with a logged
## server command (every crewed ship ABANDONED, a LOSS each), so the debrief and the
## "Run again" vote follow (NetRunReset). In PvP it is that ship's forfeit (M4-Q10).
func _abandon_run(ship: int, by: String) -> void:
	if game.fleet.rules.is_pvp():
		_abandon(ship, by)
		return
	votes.clear()
	game.world.submit(AbandonRunCommand.new())
	game.broadcast(NetProtocol.EVENT_ABANDONED, {"ship": ship, "by": by})
	_send_votes(ship)


## Abandons a paused ship (FT-NET-041): out of play at once, so the pause can end, and
## through a logged server command the sim marks it ABANDONED and gives it a loss.
func _abandon(ship: int, by: String) -> void:
	abandoned[ship] = true
	votes.erase(ship)
	var c: AbandonShipCommand = AbandonShipCommand.new()
	c.ship_id = ship
	game.world.submit(c)
	game.broadcast(NetProtocol.EVENT_ABANDONED, {"ship": ship, "by": by})
	refresh_pause()


func _pause_of(ship: int) -> Dictionary:
	var crew: int = NetCoverage.crew_count(seats_of(ship))
	return FleetMessages.pause(ship, paused.get(ship, []), crew, min_crew(), false)


## abandon_votes to every client, or to one (D128), through the shared vote path.
func _send_votes(ship: int, to: NetSession = null) -> void:
	var ids: PackedInt32Array = (
		PackedInt32Array([to.id]) if to != null else PackedInt32Array(game.by_id.keys())
	)
	var vote: NetVote = votes.get(ship, NetVote.new())
	var n: int = game.connected_crew(ship).size()
	game.send_votes(NetProtocol.EVENT_ABANDON_VOTES, ship, vote, n, ids)


## Lobby state of a ship goes to the clients on the pick screen and to those on ships
## of its faction (FT-NET-010).
func _visible(s: NetSession, ship: int) -> bool:
	var world: SimWorld = game.world
	return s.ship < 0 or world.faction_of(s.ship) == world.faction_of(ship)
