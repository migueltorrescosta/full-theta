class_name ServerSession
extends RefCounted
## Session logic on the server's main thread, fed with the decoded messages NetTransport
## takes off the sockets; it never touches a socket and answers through the transport's
## queue. It owns:
## - the handshake (protocol version, tokens, the host secret, D127) and the session cap
##   (admit_rule, T046);
## - the lobby (T043): picks (pick_rule: one Captain per ship, FT-NET-016; no mid-run
##   change that breaks coverage, FT-NET-043), the coverage check (NetCoverage) and
##   Start, sent to clients as `lobby` events;
## - claims and ship-wide controls (T044, NetClaims, claim_rule, the OWNERSHIP section);
## - grace, the universe pause, the abandon vote and takeover (T045, FT-NET-033 to
##   FT-NET-036, FT-NET-041, FT-NET-042). NetServer steps the sim only while
##   sim_running(): after a Start and outside a pause;
## - each ship's marks, alert level and pings: NetCrewState, whose Alert, Mark and Ping
##   handlers it registers;
## - the voice seam: with a VoiceService in `voice` (the app composes it), the first
##   Start calls start_session() with the closed set, and the ship computer speaks
##   hull, shield, fault and collision alerts to the stations concerned (FT-AUD-006).
## Add a message handler in _handlers. docs/protocol.md describes the behaviour.

const DEFAULT_RATE: float = 90.0
const DEFAULT_BURST: float = 180.0
## Reasons of request_rejected (lobby, claim and pause requests) and picked events.
const NOT_IMPLEMENTED: String = "not_implemented"
const NOT_PAUSED: String = "not_paused"
const NOT_HOST: String = "not_host"
const NOT_CREW: String = "not_crew"
const BAD_PICK: String = "bad_pick"
const BAD_ITEM: String = "bad_item"
const NOT_CLAIMED: String = "not_claimed"
const CAPTAIN_TAKEN: String = "captain_taken"
const NOT_COVERED: String = "coverage"
const STARTED: String = "started"

var transport: NetTransport
var world: SimWorld
var sessions: NetSessions = NetSessions.new()
var claims: NetClaims = NetClaims.new()
var dev_all: bool = false
## The host secret (D127): a client presenting it in Hello is the host; "" for none.
var host_secret: String = ""
## The session's language, chosen by the host (--language), sent in Welcome (FT-AUD-013).
var language: String = "en"
## Most sessions connected at once (FT-NET-014; T046 owns the rule).
var max_sessions: int = 64
## Per-session command rate limit (FT-NET-006; provisional: see
## docs/protocol.md, Rates and limits).
var rate: float = DEFAULT_RATE
var burst: float = DEFAULT_BURST
## Live sessions: connected or within their grace period. A lapsed session leaves
## (its token still resumes it, FT-NET-026).
var by_id: Dictionary[int, NetSession] = {}
var by_conn: Dictionary[int, NetSession] = {}
## Counts of rejected commands by reason (tests, logs).
var rejections: Dictionary = {}
## Ships whose crew pressed Start (FT-NET-019).
var launched: Dictionary[int, bool] = {}
## Ships abandoned during a pause (out of play from then on, D96).
var abandoned: Dictionary[int, bool] = {}
## Paused ships still in play: ship -> uncovered stations. The universe is paused while
## this is not empty (FT-NET-034).
var paused: Dictionary[int, Array] = {}
## Ship -> NetAbandonVote, during a pause (D128).
var votes: Dictionary[int, NetAbandonVote] = {}
## Ship -> {control: [session id, name]}: last writers of ship-wide controls.
var writers: Dictionary[int, Dictionary] = {}
## Marks, alert level and pings (D171).
var crew: NetCrewState
## The seam to the host's voice service (ServerVoice; its `voice` is null without one).
var voice: ServerVoice

var _next_id: int = 1
## Submitted commands awaiting the sim's verdict: [session id, seq, SimCommand, tick].
var _pending: Array = []
var _handlers: Dictionary = {}
## Ships whose OWNERSHIP table changed since the last post.
var _ownership_dirty: Dictionary[int, bool] = {}
## Ship -> the lobby payload last sent.
var _lobby_sent: Dictionary[int, Dictionary] = {}
## Something a lobby state depends on may have changed since the last _publish().
var _lobby_dirty: bool = true
## crew_ships(), computed at the first call: M1's ships and AIs don't change during a run.
var _crew_ships: Array = []


func _init(net: NetTransport, sim_world: SimWorld) -> void:
	transport = net
	world = sim_world
	voice = ServerVoice.new(world)
	crew = NetCrewState.new(self)
	_handlers = {
		NetProtocol.Type.HELLO: _on_hello,
		NetProtocol.Type.PICK: _on_pick,
		NetProtocol.Type.RELEASE: _on_release,
		NetProtocol.Type.READY: _on_ready,
		NetProtocol.Type.CLAIM: _on_claim,
		NetProtocol.Type.RELEASE_CLAIM: _on_claim,
		NetProtocol.Type.COMMAND: _on_command,
		NetProtocol.Type.ABANDON: _on_abandon,
		NetProtocol.Type.ABANDON_VOTE: _on_abandon_vote,
		NetProtocol.Type.TAKEOVER: _on_takeover,
		NetProtocol.Type.ALERT: crew.on_alert,
		NetProtocol.Type.MARK: crew.on_mark,
		NetProtocol.Type.PING: crew.on_ping,
		NetProtocol.Type.MARK_SEND: crew.on_mark_send,
		NetProtocol.Type.MARK_ACCEPT: crew.on_mark_accept,
		NetProtocol.Type.BYE: _on_bye,
		NetTransport.CLOSED: _on_closed,
	}


## Handles everything the transport received since the last call, lapses the sessions
## whose grace ran out (wall clock, so also while paused), and publishes lobby and
## ownership changes.
func process(now_us: int) -> void:
	for item: Array in transport.take_inbound():
		var msg: Dictionary = item[1]
		var from: NetSession = by_conn.get(item[0])
		if from != null and msg["t"] in NetProtocol.RATED_REQUESTS and not from.bucket.take(now_us):
			rejections[CommandGate.RATE_LIMITED] = rejections.get(CommandGate.RATE_LIMITED, 0) + 1
			continue
		var handler: Callable = _handlers.get(msg["t"], Callable())
		if handler.is_valid():
			handler.call(item[0], msg, now_us)
	for gone: NetSession in sessions.expire(now_us):
		_lapse(gone)
	_publish()


## Whether NetServer steps the sim: a ship has started and the universe isn't paused.
func sim_running() -> bool:
	return not launched.is_empty() and paused.is_empty()


## After the sim stepped: reports commands the sim rejected (or dropped, for a destroyed
## ship) to their senders, records last writers, and routes the tick's events
## (FT-NET-011).
func after_ticks(events: Array[SimEvent]) -> void:
	var still: Array = []
	for p: Array in _pending:
		var c: SimCommand = p[2]
		if c.tick >= 0:
			if not c.accepted:
				_reject(p[0], p[1], CommandGate.SIM_REJECTED)
			else:
				_wrote(p[0], c)
		elif world.tick > int(p[3]):
			_reject(p[0], p[1], CommandGate.SHIP_DESTROYED)
		else:
			still.append(p)
	_pending = still
	var left_play: bool = false
	for e: SimEvent in events:
		var payload: Dictionary = {
			"ship": e.ship_id,
			"faction": e.faction,
			"other": e.other_id,
			"value": e.value,
			"vector": e.vector,
			"tag": String(e.tag),
		}
		transport.post_event(event_audience(e), e.tick, String(e.kind), payload)
		crew.on_sim_event(e)
		if _crewable(e.ship_id):
			voice.on_event(e)
		left_play = left_play or e.kind == &"outcome" or e.kind == &"destroyed"
	# A sim event may change a ship's run status (lobby_state in_play).
	_lobby_dirty = _lobby_dirty or not events.is_empty()
	if left_play:
		_refresh_pause()
	_publish()


## Sessions that receive a sim event (FT-NET-009, FT-NET-010): those holding a pick on
## a ship of the event's faction whose entry sees the event kind
## (StationViews.EVENT_STATIONS). Events of no ship go to nobody.
func event_audience(e: SimEvent) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if e.faction < 0:
		return out
	for s: NetSession in by_id.values():
		if not s.has_pick() or s.ship >= world.ship_count():
			continue
		if world.faction_of(s.ship) == e.faction and StationViews.sees_event(s.entry, e.kind):
			out.append(s.id)
	return out


## The sessions on a ship whose pick covers any of the stations: a ship-computer line's
## audience (FT-AUD-006; VoiceService.computer_audience).
func computer_audience(ship: int, stations: PackedStringArray) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: NetSession in by_id.values():
		if s.ship != ship:
			continue
		for station: String in StationViews.stations_of(s.entry):
			if stations.has(station):
				out.append(s.id)
				break
	return out


## The run reset (D178, NetRunReset): the rebuilt world replaces the old one, every
## ship is back in the lobby with its picks and claims, its crew state cleared, the
## old run's pending commands dropped and its queued voice lines too.
func restart(sim_world: SimWorld) -> void:
	world = sim_world
	voice.restart(sim_world)
	_pending.clear()
	launched.clear()
	abandoned.clear()
	writers.clear()
	_refresh_pause()
	for ship: Dictionary in crew_ships():
		crew.reset(ship["id"])
		_ownership_dirty[ship["id"]] = true
	_publish()


## Adds a message handler kept outside this class (NetRunReset).
func add_handler(type: int, handler: Callable) -> void:
	_handlers[type] = handler


## Ships a client may pick: those without an AI (M1: the crewed ship). Cached at the
## first call; read-only for callers.
func crew_ships() -> Array:
	if not _crew_ships.is_empty():
		return _crew_ships
	for id: int in world.ship_count():
		if not world.ai.is_enabled(id):
			var def: ShipDef = world.defs[id]
			_crew_ships.append(
				{
					"id": id,
					"def": String(def.id),
					"name": def.display_name,
					"faction": world.faction_of(id)
				}
			)
	return _crew_ships


## Sends a server event to one session.
func notify(session: NetSession, type: String, payload: Dictionary) -> void:
	transport.post_event(PackedInt32Array([session.id]), world.tick, type, payload)


## Starts a ship's run (Start, or a test fixture): the sim steps from now on.
func launch(ship: int) -> void:
	launched[ship] = true
	_lobby_dirty = true


## A ship that started and is still in the encounter: not destroyed, retreated or
## abandoned (D96). Only these count for the pause.
func in_play(ship: int) -> bool:
	return (
		launched.has(ship)
		and not abandoned.has(ship)
		and world.run.status[ship] == RunTable.Status.IN_PLAY
	)


## Crew players a ship needs: 3, or 1 with --dev-all-stations (FT-NET-029).
func min_crew() -> int:
	return 1 if dev_all else NetCoverage.MIN_CREW


## The entries held on a ship by its live sessions (connected or within grace).
func entries_of(ship: int) -> Array:
	var out: Array = []
	for s: NetSession in by_id.values():
		if s.ship == ship and s.entry != "":
			out.append(s.entry)
	return out


## The lobby state of a ship, as sent in `lobby` events (FT-NET-021).
func lobby_state(ship: int) -> Dictionary:
	var entries: Array = entries_of(ship)
	var captain: String = ""
	for s: NetSession in by_id.values():
		if s.ship == ship and s.entry == StationViews.CAPTAIN:
			captain = s.name
	return {
		"ship": ship,
		"crew": NetCoverage.crew_count(entries),
		"min_crew": min_crew(),
		"uncovered": NetCoverage.uncovered(entries),
		"ready": NetCoverage.passes(entries, min_crew()),
		"started": launched.has(ship),
		"in_play": not abandoned.has(ship) and world.run.status[ship] == RunTable.Status.IN_PLAY,
		"captain": captain,
	}


# --- Rules. ---


## Why a new session can't be admitted, or "" (T046: FT-NET-014's 65th connection).
func admit_rule() -> String:
	var connected: int = 0
	for s: NetSession in by_id.values():
		if s.connected():
			connected += 1
	return NetProtocol.REJECT_FULL if connected >= max_sessions else ""


## Why a session may not move to (ship, entry), or "" ("" entry: back to the pick
## screen). One Captain per ship (FT-NET-016, CLASH-10, counting one within grace);
## on a ship in play that passes coverage and isn't paused, no change that would make
## it fail (FT-NET-043). During a pause the paused ship's crew may rearrange freely
## (FT-NET-035).
func pick_rule(session: NetSession, ship: int, entry: String) -> String:
	if entry == StationViews.CAPTAIN:
		for o: NetSession in by_id.values():
			if o != session and o.ship == ship and o.entry == StationViews.CAPTAIN:
				return CAPTAIN_TAKEN
	if session.has_pick() and in_play(session.ship) and not paused.has(session.ship):
		var before: Array = entries_of(session.ship)
		if NetCoverage.passes(before, min_crew()):
			var after: Array = before.duplicate()
			after.erase(session.entry)
			if ship == session.ship and entry != "":
				after.append(entry)
			if not NetCoverage.passes(after, min_crew()):
				return CommandGate.BREAKS_COVERAGE
	return ""


## Why the claims refuse a command, or "": a claimed item takes commands only from its
## claimer (FT-NET-023, FT-NET-045: Align and face are Helm flight, aim and fire the
## mount's).
func claim_rule(session: NetSession, command: SimCommand) -> String:
	var item: String = StationViews.item_of(command)
	if item == "" or not StationViews.is_claimable(item):
		return ""
	var holder: int = claims.holder(session.ship, item)
	return CommandGate.CLAIMED if holder >= 0 and holder != session.id else ""


## A session's connection dropped: its pick and claims stay for the grace period
## (FT-NET-033); a vote it cast no longer counts (D128: connected crew only).
func on_disconnect(session: NetSession, _now_us: int) -> void:
	for ship: int in votes:
		if votes[ship].voters.has(session.id):
			votes[ship].cast(session.id, "", false)
			_send_votes(ship)


# --- Handlers. ---


func _on_hello(conn: int, msg: Dictionary, now_us: int) -> void:
	if by_conn.has(conn):
		transport.close(conn, NetTransport.CLOSE_PROTOCOL, "second hello")
		return
	if msg.get("invalid", false):
		var reason: String = NetProtocol.REJECT_BAD_HELLO
		if msg.get("v", -1) != NetProtocol.PROTOCOL_VERSION:
			reason = NetProtocol.REJECT_VERSION
		_refuse(conn, reason)
		return
	var session: NetSession = null
	if msg["token"] != "":
		session = sessions.resume(msg["token"], now_us)
	# A grace that ran out after the last expire(): lapse it now, so a refused rejoin
	# leaves no live session holding the pick and claims.
	if session != null and session.lapsed and by_id.has(session.id):
		_lapse(session)
	var resumed: bool = session != null
	# The cap counts connected sessions, so every Hello that adds one is checked: a new
	# session, a lapsed one, and one within its grace; a takeover of a connected session
	# replaces its socket (FT-NET-014).
	if session == null or not session.connected():
		var why: String = admit_rule()
		if why != "":
			_refuse(conn, why)
			return
	if not resumed:
		session = NetSession.new(_next_id, rate, burst)
		_next_id += 1
		sessions.issue(session)
		by_id[session.id] = session
	elif session.connected():
		by_conn.erase(session.conn)
	session.name = msg["name"]
	session.client_kind = msg["kind"]
	session.is_host = host_secret != "" and msg["host_secret"] == host_secret
	session.conn = conn
	by_conn[conn] = session
	if session.lapsed:
		_restore(session)
	# The name may have changed (the lobby's captain).
	_lobby_dirty = true
	var welcome: Dictionary = {
		"v": NetProtocol.PROTOCOL_VERSION,
		"token": session.token,
		"session": session.id,
		"resumed": resumed,
		"tick": world.tick,
		"period": world.kin.period,
		"ev_from": 0,
		"ship": session.ship,
		"entry": session.entry,
		"dev_all": dev_all,
		"host": session.is_host,
		"lang": language,
	}
	transport.bind(conn, session.id, welcome, session.view_key(), not resumed)
	(
		transport
		. send(
			conn,
			(
				NetProtocol
				. encode(
					NetProtocol.Type.CATALOGUE,
					{
						"ships": crew_ships(),
						"entries": StationViews.catalogue(dev_all),
						"load_tags": StationViews.LOAD_TAGS.duplicate(),
					}
				)
			)
		)
	)
	# The current lobby, pause and vote state, so a (re)joining client starts in sync.
	for ship: Dictionary in crew_ships():
		if _lobby_visible(session, ship["id"]):
			notify(session, NetProtocol.EVENT_LOBBY, lobby_state(ship["id"]))
	for ship: int in paused:
		notify(session, NetProtocol.EVENT_PAUSE, _pause_payload(ship))
		_send_votes(ship, session)
	if session.has_pick():
		crew.send_to(session)
	_publish()


func _refuse(conn: int, reason: String) -> void:
	transport.send(conn, NetProtocol.hello_rejected(reason))
	transport.close(conn, NetTransport.CLOSE_REJECTED, reason)


func _on_pick(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	var ship: int = msg["ship"]
	var entry: String = msg["entry"]
	var reason: String = ""
	if not _crewable(ship) or not StationViews.is_entry(entry, dev_all):
		reason = BAD_PICK
	else:
		reason = pick_rule(s, ship, entry)
	_answer_pick(s, ship, entry, reason)


func _on_release(conn: int, _msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s != null:
		_answer_pick(s, -1, "", pick_rule(s, -1, ""))


## Applies an accepted pick, or reports why not: a `picked` event, plus CommandRejected
## (seq -1) for a change refused because it breaks coverage (FT-NET-043).
func _answer_pick(s: NetSession, ship: int, entry: String, reason: String) -> void:
	if reason == "":
		_set_pick(s, ship, entry)
	elif reason == CommandGate.BREAKS_COVERAGE:
		_reject(s.id, -1, reason)
	notify(s, NetProtocol.EVENT_PICKED, {"ship": ship, "entry": entry, "reason": reason})
	if reason == "" and s.has_pick():
		crew.send_to(s)
	_publish()


## Start (FT-NET-019): Ready{true} from a crew player of a ship whose coverage check
## passes starts that ship's run; the universe steps once a ship has started.
## Ready{false} does nothing (a started run isn't stopped from the lobby).
func _on_ready(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null or not msg["ready"]:
		return
	var reason: String = ""
	var extra: Dictionary = {}
	if not s.has_pick() or not StationViews.is_crew(s.entry):
		reason = NOT_CREW
	elif launched.has(s.ship):
		reason = STARTED
	elif not NetCoverage.passes(entries_of(s.ship), min_crew()):
		reason = NOT_COVERED
		extra = {"uncovered": NetCoverage.uncovered(entries_of(s.ship))}
	if reason != "":
		request_rejected(s, NetProtocol.Type.READY, reason, extra)
		return
	launch(s.ship)
	_broadcast(NetProtocol.EVENT_STARTED, {"ship": s.ship, "tick": world.tick})
	voice.start(language, crew_ships().map(func(c: Dictionary) -> int: return c["faction"]))
	_publish()


## Claim and ReleaseClaim (FT-NET-022 to FT-NET-024): an item of the ship, of a
## station the sender's pick covers; a claim fails while another player holds it.
func _on_claim(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	var item: String = msg["item"]
	var type: int = msg["t"]
	var reason: String = ""
	if not s.has_pick() or not _items_of(s.ship).has(item):
		reason = BAD_ITEM
	elif not StationViews.stations_of(s.entry).has(StationViews.station_of_item(item)):
		reason = CommandGate.NOT_YOUR_STATION
	elif type == NetProtocol.Type.CLAIM:
		if not claims.claim(s.ship, item, s.id):
			reason = CommandGate.CLAIMED
	elif not claims.release(s.ship, item, s.id):
		reason = NOT_CLAIMED
	if reason != "":
		request_rejected(s, type, reason, {"item": item})
		return
	_claim_changed(s.ship, item)
	_settle(s.ship)
	_publish()


func _on_command(conn: int, msg: Dictionary, now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	if s.has_pick() and abandoned.has(s.ship):
		_reject(s.id, msg["seq"], CommandGate.SHIP_ABANDONED)
		return
	var result: Array = CommandGate.check(s, msg["cmd"], now_us, claim_rule)
	if result[0] == null:
		_reject(s.id, msg["seq"], result[1])
		return
	world.submit(result[0])
	_pending.append([s.id, msg["seq"], result[0], world.tick])


## The host abandons a paused ship alone (FT-NET-041, D96, D127).
func _on_abandon(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	var ship: int = msg["ship"]
	if not paused.has(ship):
		request_rejected(s, NetProtocol.Type.ABANDON, NOT_PAUSED, {"ship": ship})
	elif not s.is_host:
		request_rejected(s, NetProtocol.Type.ABANDON, NOT_HOST, {"ship": ship})
	else:
		_abandon(ship, "host")
	_publish()


## A remaining connected crew player of a paused ship casts or withdraws an abandon
## vote; more than half of them abandon it (D128).
func _on_abandon_vote(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	var ship: int = msg["ship"]
	var members: Array[int] = connected_crew(ship)
	if not paused.has(ship):
		request_rejected(s, NetProtocol.Type.ABANDON_VOTE, NOT_PAUSED, {"ship": ship})
		return
	if not members.has(s.id):
		request_rejected(s, NetProtocol.Type.ABANDON_VOTE, NOT_CREW, {"ship": ship})
		return
	var vote: NetAbandonVote = votes.get_or_add(ship, NetAbandonVote.new())
	vote.cast(s.id, s.name, msg["vote"])
	vote.keep_only(members)
	_send_votes(ship)
	if vote.passes(members.size()):
		_abandon(ship, "vote")
	_publish()


## During a pause, the Captain or a Viewer of the paused ship takes an uncovered
## station (FT-NET-042). Players of other ships are #11 (CLASH-1 b); a crew player of
## the ship changes its pick with Pick.
func _on_takeover(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	var ship: int = msg["ship"]
	var entry: String = msg["entry"]
	var reason: String = ""
	if not paused.has(ship):
		reason = NOT_PAUSED
	elif s.ship != ship:
		reason = NOT_IMPLEMENTED
	elif not (s.entry == StationViews.CAPTAIN or s.entry == StationViews.VIEWER):
		reason = CommandGate.NOT_ALLOWED
	elif not StationViews.is_entry(entry, dev_all) or not StationViews.is_crew(entry):
		reason = BAD_PICK
	if reason != "":
		request_rejected(s, NetProtocol.Type.TAKEOVER, reason, {"ship": ship, "entry": entry})
		return
	_answer_pick(s, ship, entry, "")


func _on_bye(conn: int, _msg: Dictionary, _now_us: int) -> void:
	transport.close(conn, 1000, "bye")


func _on_closed(conn: int, _msg: Dictionary, now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	by_conn.erase(conn)
	if s == null or s.conn != conn:
		return
	sessions.drop(s, now_us)
	on_disconnect(s, now_us)
	_publish()


# --- Internals. ---


func _crewable(ship: int) -> bool:
	return ship >= 0 and ship < world.ship_count() and not world.ai.is_enabled(ship)


## Moves a session to (ship, entry): claims of stations it no longer covers are
## released (FT-NET-024: station change), the snapshot view follows, and the claims
## and pause are settled again.
func _set_pick(s: NetSession, ship: int, entry: String) -> void:
	var old_ship: int = s.ship
	var keep: Array[String] = []
	if ship == old_ship:
		keep = StationViews.stations_of(entry)
	for released: Array in claims.release_session(s.id, keep):
		_claim_changed(released[0], released[1])
	s.ship = ship
	s.entry = entry
	transport.set_view(s.id, s.view_key())
	if votes.has(old_ship):
		votes[old_ship].keep_only(connected_crew(old_ship))
		_send_votes(old_ship)
	for each: int in [old_ship, ship]:
		if _crewable(each):
			_settle(each)
	_refresh_pause()


## The grace ran out (FT-NET-033, FT-NET-024): pick and claims are released and
## remembered for a rejoin; the session leaves the live set; coverage may now fail and
## pause the universe (FT-NET-034).
func _lapse(s: NetSession) -> void:
	s.lapsed = true
	s.last_ship = s.ship
	s.last_entry = s.entry
	s.last_claims = claims.items_of(s.ship, s.id)
	by_id.erase(s.id)
	_set_pick(s, -1, "")
	_refresh_pause(true)


## A lapsed session rejoins (FT-NET-026): it gets its ship back, and its pick and claims
## where still free; otherwise it is on that ship's pick screen (entry "").
func _restore(s: NetSession) -> void:
	s.lapsed = false
	by_id[s.id] = s
	if not _crewable(s.last_ship):
		return
	s.ship = s.last_ship
	if s.last_entry != "" and pick_rule(s, s.last_ship, s.last_entry) == "":
		_set_pick(s, s.last_ship, s.last_entry)
		var stations: Array[String] = StationViews.stations_of(s.entry)
		for item: String in s.last_claims:
			if stations.has(StationViews.station_of_item(item)):
				if claims.claim(s.ship, item, s.id):
					_claim_changed(s.ship, item)
	s.last_claims = []


## Abandons a paused ship (FT-NET-041): out of play at once, so the pause can end, and
## through a logged server command the sim marks it ABANDONED and gives it a loss.
func _abandon(ship: int, by: String) -> void:
	abandoned[ship] = true
	votes.erase(ship)
	var c: AbandonShipCommand = AbandonShipCommand.new()
	c.ship_id = ship
	world.submit(c)
	_broadcast(NetProtocol.EVENT_ABANDONED, {"ship": ship, "by": by})
	_refresh_pause()


## Recomputes the paused ships, and marks the lobby states for a check. A grace ending
## (may_pause) pauses every ship in play that fails coverage (FT-NET-034); other changes
## only update or end a pause: a ship that passes again or leaves play is no longer
## paused (FT-NET-035). New or changed paused ships get a `pause` event to every
## client; when none is left the universe resumes and the votes clear (D128).
func _refresh_pause(may_pause: bool = false) -> void:
	_lobby_dirty = true
	var now: Dictionary[int, Array] = {}
	for ship: int in launched:
		if in_play(ship) and (may_pause or paused.has(ship)):
			var entries: Array = entries_of(ship)
			if not NetCoverage.passes(entries, min_crew()):
				now[ship] = NetCoverage.uncovered(entries)
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
		_broadcast(NetProtocol.EVENT_PAUSE, _pause_payload(ship))
	if was_paused and paused.is_empty():
		_broadcast(NetProtocol.EVENT_RESUME, {"tick": world.tick})


func _pause_payload(ship: int) -> Dictionary:
	return {
		"ship": ship,
		"uncovered": (paused.get(ship, []) as Array).duplicate(),
		"crew": NetCoverage.crew_count(entries_of(ship)),
		"min_crew": min_crew(),
	}


## Every claimable item of a ship (StationViews.claim_items), flat.
func _items_of(ship: int) -> Array[String]:
	var out: Array[String] = []
	if not _crewable(ship):
		return out
	var by_station: Dictionary = StationViews.claim_items(world, ship)
	for station: String in by_station:
		out.append_array(by_station[station])
	return out


## A player alone on a station holds all its free claims (FT-NET-044).
func _settle(ship: int) -> void:
	var covering: Dictionary = {}
	for s: NetSession in by_id.values():
		if s.ship != ship:
			continue
		for station: String in StationViews.stations_of(s.entry):
			(covering.get_or_add(station, []) as Array).append(s.id)
	for claimed: Array in claims.settle(ship, covering, StationViews.claim_items(world, ship)):
		_claim_changed(ship, claimed[0])


## Tells the ship's clients at the item's station who holds it now (session -1: free),
## like the OWNERSHIP section (FT-NET-023), and marks that section for an update.
func _claim_changed(ship: int, item: String) -> void:
	var holder: int = claims.holder(ship, item)
	var holder_name: String = by_id[holder].name if by_id.has(holder) else ""
	var payload: Dictionary = {"ship": ship, "item": item, "session": holder, "name": holder_name}
	var station: String = StationViews.station_of_item(item)
	for s: NetSession in by_id.values():
		if s.ship == ship and StationViews.stations_of(s.entry).has(station):
			notify(s, NetProtocol.EVENT_CLAIM, payload)
	_ownership_dirty[ship] = true


## An accepted command on a ship-wide control: its writer is now the last writer
## (FT-NET-044).
func _wrote(session_id: int, c: SimCommand) -> void:
	var item: String = StationViews.item_of(c)
	if item == "" or StationViews.is_claimable(item):
		return
	var who: NetSession = by_id.get(session_id)
	var entry: Array = [session_id, who.name if who != null else ""]
	var table: Dictionary = writers.get_or_add(c.ship_id, {})
	if table.get(item, []) != entry:
		table[item] = entry
		_ownership_dirty[c.ship_id] = true


## Session ids of a ship's connected crew players: the voters of D128 and D178.
func connected_crew(ship: int) -> Array[int]:
	var out: Array[int] = []
	for s: NetSession in by_id.values():
		if s.ship == ship and s.connected() and StationViews.is_crew(s.entry):
			out.append(s.id)
	return out


## abandon_votes to every client, or to one (D128).
func _send_votes(ship: int, to: NetSession = null) -> void:
	var vote: NetAbandonVote = votes.get(ship, NetAbandonVote.new())
	var payload: Dictionary = {
		"ship": ship,
		"voters": vote.names(),
		"sessions": vote.sessions(),
		"needed": NetAbandonVote.needed(connected_crew(ship).size()),
	}
	if to != null:
		notify(to, NetProtocol.EVENT_ABANDON_VOTES, payload)
	else:
		_broadcast(NetProtocol.EVENT_ABANDON_VOTES, payload)


func _broadcast(type: String, payload: Dictionary) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for id: int in by_id:
		ids.append(id)
	transport.post_event(ids, world.tick, type, payload)


## Lobby state of a ship goes to the clients on the pick screen and to those on ships
## of its faction (FT-NET-010).
func _lobby_visible(s: NetSession, ship: int) -> bool:
	return s.ship < 0 or world.faction_of(s.ship) == world.faction_of(ship)


## Sends changed lobby states (checked only when something they depend on changed) and
## posts changed ownership tables.
func _publish() -> void:
	if _lobby_dirty:
		_lobby_dirty = false
		for ship: Dictionary in crew_ships():
			var id: int = ship["id"]
			var state: Dictionary = lobby_state(id)
			if _lobby_sent.get(id, {}) != state:
				_lobby_sent[id] = state
				for s: NetSession in by_id.values():
					if _lobby_visible(s, id):
						notify(s, NetProtocol.EVENT_LOBBY, state)
	for ship: int in _ownership_dirty:
		var table: Dictionary = {"claims": {}, "writers": writers.get(ship, {}).duplicate()}
		var held: Dictionary = claims.table(ship)
		for item: String in held:
			var who: NetSession = by_id.get(held[item])
			table["claims"][item] = [held[item], who.name if who != null else ""]
		transport.post_ownership(ship, table)
	_ownership_dirty.clear()


## A `request_rejected` event to one session: the request type, the reason and extra
## fields.
func request_rejected(s: NetSession, type: int, reason: String, extra: Dictionary) -> void:
	var payload: Dictionary = {"request": type, "reason": reason}
	payload.merge(extra)
	notify(s, NetProtocol.EVENT_REQUEST_REJECTED, payload)


func _reject(session_id: int, seq: int, reason: String) -> void:
	rejections[reason] = rejections.get(reason, 0) + 1
	transport.post_event(
		PackedInt32Array([session_id]),
		world.tick,
		NetProtocol.EVENT_COMMAND_REJECTED,
		{"seq": seq, "reason": reason}
	)
