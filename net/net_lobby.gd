class_name NetLobby
extends RefCounted
## The lobby and the coverage pause on the server (T043, T045; F2, R13-3): NetGame owns
## one and keeps the handshake, the session maps, claims and event routing. It holds:
## - picks (pick_rule: one Captain per ship, FT-NET-016; no mid-run change that breaks
##   coverage, FT-NET-043), the coverage check (NetCoverage), Start (FT-NET-019) and the
##   session's data toggles (FT-PAIR-017), sent to clients as `lobby` events;
## - the ships that started, the ships abandoned during a pause (D96) and the coverage pause
##   (FT-NET-034, FT-NET-035): NetServer steps the sim only while NetGame.sim_running();
## - the abandon vote (D128, D241) and the takeover of an uncovered station (FT-NET-041,
##   FT-NET-042).
## Messages: Pick, Release, Ready, Toggles, Abandon, AbandonVote, Takeover.

## Ships whose crew pressed Start (FT-NET-019). Read it through is_launched, launched_ships
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
## changes it in the lobby until a ship starts; sessions' view keys follow.
var toggles: DataToggles = DataToggles.of_preset(StationViews.DEFAULT_TOGGLES)

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


## Crew players a ship needs: 3, or 1 with --dev-all-stations (FT-NET-029).
func min_crew() -> int:
	return 1 if game.dev_all else NetCoverage.MIN_CREW


## The seats held on a ship by its live sessions (connected or within grace), and a solo
## lesson's bots.
func seats_of(ship: int) -> Array:
	var out: Array = game.training.bot_seats() if game.crewable(ship) else []
	for s: NetSession in game.by_id.values():
		if s.ship == ship and s.seat != "":
			out.append(s.seat)
	return out


## The lobby state of a ship, as sent in `lobby` events (FT-NET-021).
func lobby_state(ship: int) -> Dictionary:
	var held: Array = seats_of(ship)
	var captain: String = ""
	var holders: Array = []
	for s: NetSession in game.by_id.values():
		if s.ship == ship and s.seat != "":
			holders.append({"name": s.name, "seat": s.seat})
		if s.ship == ship and s.seat == StationViews.CAPTAIN:
			captain = s.name
	return {
		"ship": ship,
		"crew": NetCoverage.crew_count(held),
		"min_crew": min_crew(),
		"uncovered": NetCoverage.uncovered(held),
		"ready": NetCoverage.passes(held, min_crew()),
		"started": launched.has(ship),
		"in_play": _in_run(ship),
		"captain": captain,
		"seats": holders,
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
	if seat == StationViews.CAPTAIN:
		for o: NetSession in game.by_id.values():
			if o != s and o.ship == ship and o.seat == StationViews.CAPTAIN:
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


## Starts a ship's run (Start, or a test fixture): the sim steps from now on.
func launch(ship: int) -> void:
	launched[ship] = true
	_dirty = true


## A relaunched ship is back in play (NetFleet): its pending abandon is over.
func clear_abandoned(ship: int) -> void:
	abandoned.erase(ship)
	_dirty = true


## The run reset (NetGame.restart): every ship back in the lobby, picks kept.
func reset() -> void:
	launched.clear()
	abandoned.clear()
	refresh_pause()
	for ship: Dictionary in game.crew_ships():
		_sync_captain_seat(ship["id"])


## Moves a session to (ship, seat) without the pick rules, as the server decides it (NetFleet:
## a ship's new id at Start, a handover, a relaunch), with its `picked` event.
func move(s: NetSession, ship: int, seat: String) -> void:
	_answer_pick(s, ship, seat, "")


## Start for `s` (FT-NET-019), as Ready{true} would press it: refused (request_rejected) from
## a session that is not crew, a started ship or one failing coverage; the universe starts
## once every crewed ship has pressed it (NetFleet.press_start, M4-Q4).
func mark_ready(s: NetSession) -> void:
	var reason: String = ""
	var extra: Dictionary = {}
	if not s.is_crew():
		reason = NetGame.NOT_CREW
	elif launched.has(s.ship):
		reason = NetGame.STARTED
	elif not NetCoverage.passes(seats_of(s.ship), min_crew()):
		reason = NetGame.NOT_COVERED
		extra = {"uncovered": NetCoverage.uncovered(seats_of(s.ship))}
	if game.refuse(s, NetProtocol.Type.READY, reason, extra):
		return
	var ships: Array[int] = game.fleet.press_start(s)  # all together (M4-Q4)
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
	var was_captain: bool = s.seat == StationViews.CAPTAIN
	var keep: Array[String] = []
	if ship == old_ship:
		keep = StationViews.stations_of(seat)
	game.release_claims(s, keep)
	s.ship = ship
	s.seat = seat
	if ship >= 0:
		s.home_ship = ship
	s.shares = game.shares.active_of(ship)
	game.transport.set_view(s.id, s.view_key())
	if votes.has(old_ship):
		votes[old_ship].keep_only(game.connected_crew(old_ship))
		_send_votes(old_ship)
	for each: int in [old_ship, ship]:
		if game.crewable(each):
			game.settle(each)
			if was_captain or seat == StationViews.CAPTAIN:
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
	if not game.crewable(ship) or not StationViews.is_seat(seat, game.dev_all):
		reason = NetGame.BAD_PICK
	else:
		reason = pick_rule(s, ship, seat)
	_answer_pick(s, ship, seat, reason)


func _on_release(s: NetSession, _msg: Dictionary, _now_us: int) -> void:
	_answer_pick(s, -1, "", pick_rule(s, -1, ""))


## Ready{true} presses Start (mark_ready); Ready{false} does nothing (a started run isn't
## stopped from the lobby).
func _on_ready(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	if msg["ready"]:
		mark_ready(s)


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
			game.transport.set_view(each.id, each.view_key())
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
	_answer_pick(s, ship, seat, "")
	game.fleet.took_over(s, ship, seat, from_ship)


# --- Internals. ---


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
