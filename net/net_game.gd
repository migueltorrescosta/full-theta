# gdlint: disable=max-public-methods
class_name NetGame
extends RefCounted
## Session logic on the server's main thread, fed with the decoded messages NetTransport
## takes off the sockets; it never touches a socket and answers through the transport's
## queue. It owns:
## - the handshake (protocol version, tokens, the host secret, D127) and the session cap
##   (admit_rule, T046);
## - the session maps (by_id, by_conn) and the message handlers: every handler but Hello,
##   Bye and the transport's close gets the sender's resolved NetSession (F2, R06-3);
## - claims and ship-wide controls (T044, NetClaims, claim_rule, the OWNERSHIP section);
## - grace (FT-NET-033): a lapsed session leaves the live set, a rejoin restores it;
## - the routing of the sim's events to their audiences (FT-NET-009 to FT-NET-011) and of
##   the sim's verdicts on commands.
## Its parts: NetLobby (picks, Start, toggles, the coverage pause, the abandon vote and
## takeover), NetHostPause, NetFleet (the multi-ship lobby), NetCrewState (marks, alert,
## pings, relay), NetChips, NetShares, NetCoop and NetTraining. They change this class's state
## only through its methods. The voice seam: with a VoiceService in `voice` (the app composes
## it), the first Start calls start_session() with the closed set, and the ship computer
## speaks hull, shield, fault and collision alerts to the stations concerned (FT-AUD-006).
## Add a handler with add_handler(). docs/protocol.md describes the behaviour.

const DEFAULT_RATE: float = 90.0
const DEFAULT_BURST: float = 180.0
## Reasons of request_rejected (lobby, claim and pause requests) and picked events.
const NOT_IMPLEMENTED: String = "not_implemented"
const NOT_PAUSED: String = "not_paused"
## Abandon outside a pause (D241): the ship is not in a started run.
const NOT_IN_RUN: String = "not_in_run"
const NOT_HOST: String = "not_host"
const NOT_CREW: String = NetProtocol.REASON_NOT_CREW
const NOT_YOUR_SHIP: String = "not_your_ship"
const BAD_PICK: String = "bad_pick"
const BAD_ITEM: String = "bad_item"
const NOT_CLAIMED: String = "not_claimed"
const CAPTAIN_TAKEN: String = "captain_taken"
const NOT_COVERED: String = "coverage"
const STARTED: String = "started"
const TOGGLES_LOCKED: String = "toggles_locked"
const BAD_TOGGLES: String = "bad_toggles"
## Messages handled with the connection id rather than a session: the handshake, Bye and the
## transport's close.
const CONN_TYPES: Array[int] = [NetProtocol.Type.HELLO, NetProtocol.Type.BYE, NetTransport.CLOSED]

var transport: NetTransport
var world: SimWorld
var sessions: NetSessions = NetSessions.new()
var claims: NetClaims = NetClaims.new()
var dev_all: bool = false
## The host secret (D127): a client presenting it in Hello is the host; "" for none.
var host_secret: String = ""
## The session's language, chosen by the host (--language), sent in Welcome (FT-AUD-013).
var language: String = "en"
## The server serves its page and WebSocket over TLS (--tls-cert, D294), sent in Welcome so
## the host's lobby shows an https join URL.
var tls: bool = false
## Most sessions connected at once (FT-NET-014; T046 owns the rule).
var max_sessions: int = 64
## Per-session command rate limit (FT-NET-006; provisional: docs/protocol.md, Rates).
var rate: float = DEFAULT_RATE
var burst: float = DEFAULT_BURST
## Live sessions: connected or within grace; a lapsed one leaves (its token resumes, FT-NET-026).
## Parts read these; only this class adds or removes entries.
var by_id: Dictionary[int, NetSession] = {}
var by_conn: Dictionary[int, NetSession] = {}
## Counts of rejected commands by reason (tests, logs).
var rejections: Dictionary = {}
## Ship -> {control: [session id, name]}: last writers of ship-wide controls.
var writers: Dictionary[int, Dictionary] = {}
## The lobby and the coverage pause (NetLobby).
var lobby: NetLobby
## Marks, alert level and pings (D171).
var crew: NetCrewState
## The seam to the host's voice service (ServerVoice; its `voice` is null without one).
var voice: ServerVoice
## The server log (D199) once NetServer.start_server_log() opened it; counts commands.
var server_log: ServerLog:
	set(value):
		server_log = value
		if coop != null:
			coop.server_log = value

## Request chips (NetChips) and the cooperative events counted for the debrief (CoopEvents).
var chips: NetChips
var coop: NetCoop
## When each station first used each core action, for the debrief (FT-MIS-038).
var first_use: FirstUse = FirstUse.new()
var shares: NetShares
var host_pause: NetHostPause
## The multi-ship lobby and PvP rules (#11).
var fleet: NetFleet
var training: NetTraining  # solo lessons (D303)

var _next_id: int = 1
## Submitted commands awaiting the sim's verdict: [session id, seq, SimCommand, tick].
var _pending: Array = []
## Message type -> Callable(NetSession, msg, now_us); CONN_TYPES take the connection id.
var _handlers: Dictionary[int, Callable] = {}
## Ships whose OWNERSHIP table changed since the last post.
var _ownership_dirty: Dictionary[int, bool] = {}
## crew_ships(), computed at the first call: M1's ships and AIs don't change during a run.
var _crew_ships: Array = []


func _init(net: NetTransport, sim_world: SimWorld) -> void:
	transport = net
	world = sim_world
	voice = ServerVoice.new(world)
	add_handler(NetProtocol.Type.HELLO, _on_hello)
	add_handler(NetProtocol.Type.BYE, _on_bye)
	add_handler(NetTransport.CLOSED, _on_closed)
	add_handler(NetProtocol.Type.CLAIM, _on_claim)
	add_handler(NetProtocol.Type.RELEASE_CLAIM, _on_claim)
	add_handler(NetProtocol.Type.COMMAND, _on_command)
	add_handler(NetProtocol.Type.CLIENT_FRAME, _on_client_frame)
	add_handler(NetProtocol.Type.RENAME, _on_rename)
	# Each part registers its own messages.
	lobby = NetLobby.new(self)
	crew = NetCrewState.new(self)
	chips = NetChips.new(self)
	coop = NetCoop.new(self)
	shares = NetShares.new(self)
	host_pause = NetHostPause.new(self)
	fleet = NetFleet.new(self)
	training = NetTraining.new(self)


## Registers the handler of a message type: Callable(NetSession, msg, now_us), or
## Callable(conn, msg, now_us) for CONN_TYPES. A type has one handler: a second
## registration is an error and is ignored (R13-4).
func add_handler(type: int, handler: Callable) -> void:
	if _handlers.has(type):
		push_error("NetGame: a handler for message type %d is already registered" % type)
		return
	_handlers[type] = handler


## Handles everything the transport received since the last call, lapses the sessions
## whose grace ran out (wall clock, so also while paused), and publishes lobby and
## ownership changes.
func process(now_us: int) -> void:
	for item: Array in transport.take_inbound():
		var conn: int = item[0]
		var msg: Dictionary = item[1]
		var type: int = msg["t"]
		var handler: Callable = _handlers.get(type, Callable())
		if CONN_TYPES.has(type):
			if handler.is_valid():
				handler.call(conn, msg, now_us)
			continue
		var from: NetSession = by_conn.get(conn)
		if from == null:
			continue
		if type in NetProtocol.rated_requests and not from.bucket.take(now_us):
			rejections[CommandGate.RATE_LIMITED] = rejections.get(CommandGate.RATE_LIMITED, 0) + 1
			# The client waits for an answer to its Pick, Claim or Ready (#45 B2, R11-4).
			request_rejected(from, type, CommandGate.RATE_LIMITED, {})
			continue
		if handler.is_valid():
			handler.call(from, msg, now_us)
	for gone: NetSession in sessions.expire(now_us):
		_lapse(gone)
	for evicted: NetSession in sessions.evict(now_us):
		transport.forget(evicted.id)
		crew.pings.forget(evicted.id)
	chips.step()
	shares.step()
	coop.step()
	publish()


## Whether NetServer steps the sim: a ship has started and the universe isn't paused.
func sim_running() -> bool:
	return lobby.any_launched() and not lobby.any_paused() and not host_pause.paused


## After the sim stepped: reports commands the sim rejected (or dropped, for a destroyed
## ship) to their senders, records last writers, and routes the tick's events
## (FT-NET-011).
func after_ticks(events: Array[SimEvent]) -> void:
	var still: Array = []
	for p: Array in _pending:
		var c: SimCommand = p[2]
		if c.tick >= 0:
			if not c.accepted:
				_reject(p[0], p[1], _verdict(c))
			else:
				_wrote(p[0], c)
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
		var audience: PackedInt32Array = event_audience(e)
		_post_event(audience, e, payload)
		crew.on_sim_event(e)
		coop.on_sim_event(e)
		if e.kind == &"fault_cause_revealed":
			_prefill_cause(e)
		if crewable(e.ship_id):
			voice.on_event(e)
		left_play = left_play or e.kind == &"outcome" or e.kind == &"destroyed"
	# A sim event may change a ship's run status (lobby_state in_play).
	if not events.is_empty():
		lobby.mark_dirty()
	fleet.after_ticks(events)
	if left_play:
		lobby.refresh_pause()
	publish()


## The reason a rejected command goes back with: the sim's own reason (a PowerSystem refusal
## names the reactor cap, F5, R12-7), else ship_destroyed for a command the sim dropped for a
## destroyed ship (it stamps the tick all the same), else sim_rejected.
func _verdict(c: SimCommand) -> String:
	if CommandGate.SIM_REASONS.has(c.reject_reason):
		return CommandGate.SIM_REASONS[c.reject_reason]
	if not world.kin.is_alive(c.ship_id) and not c.applies_to_destroyed():
		return CommandGate.SHIP_DESTROYED
	return CommandGate.SIM_REJECTED


## Posts an event; an EXACT_EVENTS value goes to each session as its view may carry it, so
## the audience is split by that value (D224).
func _post_event(audience: PackedInt32Array, e: SimEvent, payload: Dictionary) -> void:
	if not EventRouting.EXACT_EVENTS.has(e.kind):
		transport.post_event(audience, e.tick, String(e.kind), payload)
		return
	var groups: Dictionary = {}
	for id: int in audience:
		var s: NetSession = by_id.get(id)
		if s == null:
			continue
		var v: float = EventRouting.event_value(s.entry, e.kind, e.value, s.view_code())
		var ids: PackedInt32Array = groups.get(v, PackedInt32Array())
		ids.append(id)
		groups[v] = ids
	for v: float in groups:
		var scrubbed: Dictionary = payload.duplicate()
		scrubbed["value"] = v
		transport.post_event(groups[v], e.tick, String(e.kind), scrubbed)


## P10 on Easy (FT-ENG-006): the cause Science's own-ship scan revealed is pre-filled as
## Engineering's pick once Science shared the diagnosed causes (D210), through a logged
## server command like any other pick, unless Engineering already picked one. The scan reveals
## the cause at every difficulty; the toggle only decides whether the pick is made for
## Engineering (FT-PAIR-014).
func _prefill_cause(e: SimEvent) -> void:
	if shares.active(e.ship_id, ViewFilter.DIAGNOSED_CAUSES):
		shares.prefill_cause(e.ship_id, e.tag)


## Sessions that receive a sim event (FT-NET-009, FT-NET-010): those holding a pick on
## a ship of the event's faction whose entry sees the event kind
## (EventRouting.EVENT_STATIONS). Events of no ship go to nobody.
func event_audience(e: SimEvent) -> PackedInt32Array:
	# A spoken line reaches only its conversation's claimer or Comms' subtitle, through
	# ServerVoice (FT-COM-006): the raw event, whose tag is the line id, goes to nobody.
	if e.faction < 0 or e.kind == &"say" or NetFleet.OWN_EVENTS.has(e.kind):
		return PackedInt32Array()
	return audience(
		func(s: NetSession) -> bool:
			return (
				s.has_pick()
				and s.ship < world.ship_count()
				and world.faction_of(s.ship) == e.faction
				and EventRouting.sees_event(s.entry, e.kind, s.view_code())
			)
	)


## The sessions on a ship whose pick covers any of the stations: a ship-computer line's
## audience (FT-AUD-006; VoiceService.computer_audience).
func computer_audience(ship: int, stations: PackedStringArray) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: NetSession in by_id.values():
		if s.ship != ship:
			continue
		# The Captain seat is its own entry with no crew station: its station name
		# is "captain" (the Shakedown's Captain track, review 2, M1).
		var names: Array[String] = StationViews.stations_of(s.entry)
		if s.entry == StationViews.CAPTAIN:
			names = [StationViews.CAPTAIN]
		for station: String in names:
			if stations.has(station):
				out.append(s.id)
				break
	return out


## The session holding the claim on the conversation `npc_key` names, as
## VoiceService.npc_audience wants it: empty while nobody holds it (FT-AUD-005,
## FT-COM-006). The key is ServerVoice.card_key(card): only the ships that see the card
## are asked, so one ship's NPC never reaches another ship's claimer.
func npc_audience(npc_key: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var card: int = ServerVoice.card_of_key(npc_key)
	if card < 0 or card >= world.story.size():
		return out
	for ship: Dictionary in crew_ships():
		if not Story.visible_to(world, card, ship["id"]):
			continue
		var holder: int = claims.holder(ship["id"], "npc:" + str(card))
		if holder >= 0 and by_id.has(holder):
			out.append(holder)
	return out


## The ids of the live sessions `pred` (Callable(NetSession) -> bool) holds for (R06-9).
func audience(pred: Callable) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: NetSession in by_id.values():
		if pred.call(s):
			out.append(s.id)
	return out


## The run reset (D178, NetRunReset): the rebuilt world replaces the old one, every
## ship is back in the lobby with its picks and claims, its crew state cleared, the
## old run's pending commands dropped and its queued voice lines too.
func restart(sim_world: SimWorld) -> void:
	world = sim_world
	voice.restart(sim_world)
	_pending.clear()
	writers.clear()
	_crew_ships.clear()
	fleet.reset()
	lobby.reset()
	for ship: Dictionary in crew_ships():
		crew.reset(ship["id"])
		chips.reset(ship["id"])
		shares.reset(ship["id"])
		coop.reset_ship(ship["id"])
		_ownership_dirty[ship["id"]] = true
	coop.reset()
	first_use.reset()
	publish()


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
					"name": fleet.name_of(id, def.display_name),
					"faction": world.faction_of(id)
				}
			)
	return _crew_ships


## Whether a client may pick the ship: it exists and no AI flies it.
func crewable(ship: int) -> bool:
	return ship >= 0 and ship < world.ship_count() and not world.ai.is_enabled(ship)


## Sends a server event to one session.
func notify(s: NetSession, type: String, payload: Dictionary) -> void:
	transport.post_event(PackedInt32Array([s.id]), world.tick, type, payload)


func broadcast(type: String, payload: Dictionary) -> void:
	transport.post_event(PackedInt32Array(by_id.keys()), world.tick, type, payload)


## The one send path of the three crew votes (abandon, run again, relaunch; R06-1): the vote's
## payload among `voters` voters goes to `to`. Returns the payload.
func send_votes(
	event: String, ship: int, vote: NetVote, voters: int, to: PackedInt32Array
) -> Dictionary:
	var payload: Dictionary = vote.payload(ship, voters)
	transport.post_event(to, world.tick, event, payload)
	return payload


## The Catalogue message: the crewable ships and the entries (after Welcome, and again after
## the multi-ship lobby rebuilt the world).
func catalogue() -> PackedByteArray:
	var body: Dictionary = {
		"ships": crew_ships(),
		"entries": StationViews.catalogue(dev_all),
		"load_tags": StationViews.LOAD_TAGS.duplicate(),
	}
	return NetProtocol.encode(NetProtocol.Type.CATALOGUE, body)


## Starts a ship's run (NetLobby.launch; Start, or a test fixture).
func launch(ship: int) -> void:
	lobby.launch(ship)


func in_play(ship: int) -> bool:
	return lobby.in_play(ship)


func entries_of(ship: int) -> Array:
	return lobby.entries_of(ship)


func lobby_state(ship: int) -> Dictionary:
	return lobby.lobby_state(ship)


# --- Rules. ---


## Why a new session can't be admitted, or "" (T046: FT-NET-014's 65th connection).
func admit_rule() -> String:
	var connected: int = 0
	for s: NetSession in by_id.values():
		if s.connected():
			connected += 1
	return NetProtocol.REJECT_FULL if connected >= max_sessions else ""


## Why the claims refuse a command, or "": a claimed item takes commands only from its
## claimer (FT-NET-023, FT-NET-045: Align and face are Helm flight, aim and fire the
## mount's).
func claim_rule(s: NetSession, command: SimCommand) -> String:
	var item: String = StationBlocks.item_of(command)
	if item == "" or not StationViews.is_claimable(item):
		return ""
	var holder: int = claims.holder(s.ship, item)
	return CommandGate.CLAIMED if holder >= 0 and holder != s.id else ""


# --- Handlers. ---


func _on_hello(conn: int, msg: Dictionary, now_us: int) -> void:
	if by_conn.has(conn):
		transport.close(conn, NetTransport.CLOSE_PROTOCOL, "second hello")
		return
	var version_ok: bool = msg.get("v", -1) == NetProtocol.PROTOCOL_VERSION
	if msg.get("invalid", false) or not version_ok:
		var reason: String = (
			NetProtocol.REJECT_BAD_HELLO if version_ok else NetProtocol.REJECT_VERSION
		)
		_refuse(conn, reason)
		return
	var s: NetSession = null
	if msg["token"] != "":
		s = sessions.resume(msg["token"], now_us)
	# A grace that ran out after the last expire(): lapse it now, so a refused rejoin
	# leaves no live session holding the pick and claims.
	if s != null and s.lapsed and by_id.has(s.id):
		_lapse(s)
	var resumed: bool = s != null
	# The cap counts connected sessions, so every Hello that adds one is checked: a new
	# session, a lapsed one, and one within its grace; a takeover of a connected session
	# replaces its socket (FT-NET-014).
	if s == null or not s.connected():
		var why: String = admit_rule()
		if why != "":
			_refuse(conn, why)
			return
	if not resumed:
		s = NetSession.new(_next_id, rate, burst)
		_next_id += 1
		sessions.issue(s)
		by_id[s.id] = s
	elif s.connected():
		by_conn.erase(s.conn)
	s.name = msg["name"]
	s.client_kind = msg["kind"]
	s.is_host = host_secret != "" and msg["host_secret"] == host_secret
	if s.is_host:
		# One host: a relaunch with a lost token file leaves the old session in its grace.
		for other: NetSession in sessions.all():
			if other != s:
				other.is_host = false
	s.conn = conn
	s.toggles = lobby.toggles.encode()
	by_conn[conn] = s
	if s.lapsed:
		_restore(s)
	# The name may have changed (the lobby's captain).
	lobby.mark_dirty()
	transport.bind(conn, s.id, _welcome(s, resumed), s.view_key(), not resumed)
	if server_log != null:
		var fields: Dictionary = {
			"session": s.id, "name": s.name, "client": s.client_kind, "resumed": resumed
		}
		server_log.event("join", fields)
	transport.send(conn, catalogue())
	# The current lobby, pause and vote state, so a (re)joining client starts in sync.
	lobby.send_to(s)
	host_pause.send_to(s)
	fleet.send_to(s)
	if s.has_pick():
		crew.send_to(s)
	publish()
	training.on_join(s)


func _welcome(s: NetSession, resumed: bool) -> Dictionary:
	return {
		"v": NetProtocol.PROTOCOL_VERSION,
		"token": s.token,
		"session": s.id,
		"resumed": resumed,
		"tick": world.tick,
		"period": world.kin.period,
		"ev_from": 0,
		"ship": s.ship,
		"entry": s.entry,
		"dev_all": dev_all,
		"host": s.is_host,
		"lang": language,
		"tls": tls,
	}


func _refuse(conn: int, reason: String) -> void:
	transport.send(conn, NetProtocol.hello_rejected(reason))
	transport.close(conn, NetTransport.CLOSE_REJECTED, reason)


## Claim and ReleaseClaim (FT-NET-022 to FT-NET-024): an item of the ship, of a
## station the sender's pick covers; a claim fails while another player holds it.
func _on_claim(s: NetSession, msg: Dictionary, _now_us: int) -> void:
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
	if refuse(s, type, reason, {"item": item}):
		return
	_claim_changed(s.ship, item)
	settle(s.ship)
	publish()


func _on_command(s: NetSession, msg: Dictionary, now_us: int) -> void:
	if s.has_pick() and lobby.abandoned.has(s.ship):
		_reject(s.id, msg["seq"], CommandGate.SHIP_ABANDONED)
		return
	var result: Array = CommandGate.check(s, msg["cmd"], now_us, claim_rule)
	if result[0] == null:
		_reject(s.id, msg["seq"], result[1])
		return
	# A stopped sim would queue the command and run it on resume (#45 A4): refused once it is
	# otherwise valid. Next (Shakedown) is the one command the lessons press while it is stopped.
	if not sim_running() and not result[0] is TrainingNextCommand:
		_reject(s.id, msg["seq"], CommandGate.PAUSED)
		return
	world.submit(result[0])
	if server_log != null:
		server_log.count("commands")
	_pending.append([s.id, msg["seq"], result[0]])


func _on_bye(conn: int, _msg: Dictionary, _now_us: int) -> void:
	transport.close(conn, 1000, "bye")


## Rename{name} (#35 A5): the session takes the name (an empty one is ignored); the lobby's
## seats and captain follow, and claims and votes name it from then on.
func _on_rename(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	if str(msg["name"]) == "" or msg["name"] == s.name:
		return
	if server_log != null:
		server_log.event("rename", {"session": s.id, "from": s.name, "to": msg["name"]})
	s.name = msg["name"]
	lobby.mark_dirty()
	publish()


## A client's long frame (#28) goes to the server log, with whose it was.
func _on_client_frame(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	if server_log == null:
		return
	var what: String = NetProtocol.clip_utf8(msg["what"], NetProtocol.MAX_FRAME_WHAT_BYTES)
	var fields: Dictionary = {
		"session": s.id, "name": s.name, "client": s.client_kind, "ms": msg["ms"], "what": what
	}
	server_log.event("long_frame", fields)


## A session's connection dropped: its pick and claims stay for the grace period
## (FT-NET-033); a vote it cast no longer counts (D128: connected crew only).
func _on_closed(conn: int, _msg: Dictionary, now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	by_conn.erase(conn)
	if s == null or s.conn != conn:
		return
	sessions.drop(s, now_us)
	lobby.on_disconnect(s)
	publish()


# --- Claims, grace and publishing (the parts call these). ---


## Releases the session's claims except those of `keep` stations (FT-NET-024: station change).
func release_claims(s: NetSession, keep: Array[String]) -> void:
	for released: Array in claims.release_session(s.id, keep):
		_claim_changed(released[0], released[1])


## A fresh claims table: the multi-ship lobby rebuilt the world at Start (NetFleet).
func reset_claims() -> void:
	claims = NetClaims.new()


## A player alone on a station holds all its free claims (FT-NET-044).
func settle(ship: int) -> void:
	var covering: Dictionary = {}
	for s: NetSession in by_id.values():
		if s.ship != ship:
			continue
		for station: String in StationViews.stations_of(s.entry):
			(covering.get_or_add(station, []) as Array).append(s.id)
	for claimed: Array in claims.settle(ship, covering, StationBlocks.claim_items(world, ship)):
		_claim_changed(ship, claimed[0])


## Session ids of a ship's connected crew players: the voters of D128 and D178.
func connected_crew(ship: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(audience(func(s: NetSession) -> bool: return s.ship == ship and s.is_live_crew()))
	return out


## Sends changed lobby states (NetLobby, NetFleet) and posts changed ownership tables.
func publish() -> void:
	fleet.publish(lobby.publish())
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


## The refusal tail of a handler (R06-3): with a reason, request_rejected and true; with "",
## false.
func refuse(s: NetSession, type: int, reason: String, extra: Dictionary) -> bool:
	if reason == "":
		return false
	request_rejected(s, type, reason, extra)
	return true


## CommandRejected{seq, reason} to one session (FT-NET-007), counted in `rejections`.
func reject_command(session_id: int, seq: int, reason: String) -> void:
	_reject(session_id, seq, reason)


# --- Internals. ---


## The grace ran out (FT-NET-033, FT-NET-024): pick and claims are released and
## remembered for a rejoin; the session leaves the live set; coverage may now fail and
## pause the universe (FT-NET-034).
func _lapse(s: NetSession) -> void:
	s.lapsed = true
	s.last_ship = s.ship
	s.last_entry = s.entry
	s.last_claims = claims.items_of(s.ship, s.id)
	by_id.erase(s.id)
	lobby.set_pick(s, -1, "")
	if s.is_host:
		host_pause.set_paused(false)  # Q19: the host did not return within the grace
	lobby.refresh_pause(true)


## A lapsed session rejoins (FT-NET-026): it gets its ship back, and its pick and claims
## where still free; otherwise it is on that ship's pick screen (entry "").
func _restore(s: NetSession) -> void:
	s.lapsed = false
	by_id[s.id] = s
	if not crewable(s.last_ship):
		return
	s.ship = s.last_ship
	if s.last_entry != "" and lobby.pick_rule(s, s.last_ship, s.last_entry) == "":
		lobby.set_pick(s, s.last_ship, s.last_entry)
		var stations: Array[String] = StationViews.stations_of(s.entry)
		for item: String in s.last_claims:
			if stations.has(StationViews.station_of_item(item)):
				if claims.claim(s.ship, item, s.id):
					_claim_changed(s.ship, item)
	s.last_claims = []


## Every claimable item of a ship (StationBlocks.claim_items), flat.
func _items_of(ship: int) -> Array[String]:
	var out: Array[String] = []
	if not crewable(ship):
		return out
	var by_station: Dictionary = StationBlocks.claim_items(world, ship)
	for station: String in by_station:
		out.append_array(by_station[station])
	return out


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
	coop.on_command(session_id, c)
	var item: String = StationBlocks.item_of(c)
	if item == "" or StationViews.is_claimable(item):
		return
	var who: NetSession = by_id.get(session_id)
	var entry: Array = [session_id, who.name if who != null else ""]
	var table: Dictionary = writers.get_or_add(c.ship_id, {})
	if table.get(item, []) != entry:
		table[item] = entry
		_ownership_dirty[c.ship_id] = true


func _reject(session_id: int, seq: int, reason: String) -> void:
	rejections[reason] = rejections.get(reason, 0) + 1
	transport.post_event(
		PackedInt32Array([session_id]),
		world.tick,
		NetProtocol.EVENT_COMMAND_REJECTED,
		{"seq": seq, "reason": reason}
	)
