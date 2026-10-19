class_name ServerSession
extends RefCounted
## Session logic on the server's main thread: the handshake (protocol version, tokens,
## the host secret), picks, command validation and routing of sim events, fed with the
## decoded messages NetTransport takes off the sockets. It never touches a socket: it
## answers through the transport's queue. Later tasks extend it at the marked hooks:
## T043 lobby (pick_rule, on_ready, coverage), T044 claims (claim_rule, on_claim),
## T045 grace/pause/abandon (on_disconnect, on_abandon*, on_takeover), T046 session cap
## (admit_rule). Add a message handler in _handlers.

const DEFAULT_RATE: float = 90.0
const DEFAULT_BURST: float = 180.0
const NOT_IMPLEMENTED: String = "not_implemented"
const NOT_PAUSED: String = "not_paused"
## Event to the sender when a lobby, claim or pause request is refused.
const EVENT_REQUEST_REJECTED: String = "request_rejected"

var transport: NetTransport
var world: SimWorld
var sessions: NetSessions = NetSessions.new()
var dev_all: bool = false
## --host-secret (D127): a client presenting it in Hello is the host; "" for none.
var host_secret: String = ""
## The session's language, chosen by the host (--language), sent in Welcome (FT-AUD-013).
var language: String = "en"
## Most sessions connected at once (FT-NET-014; T046 owns the rule).
var max_sessions: int = 64
## Per-session command rate limit (PROVISIONAL, FT-NET-006).
var rate: float = DEFAULT_RATE
var burst: float = DEFAULT_BURST
var by_id: Dictionary[int, NetSession] = {}
var by_conn: Dictionary[int, NetSession] = {}
## Counts of rejected commands by reason (tests, logs).
var rejections: Dictionary = {}

var _next_id: int = 1
## Submitted commands awaiting the sim's verdict: [session id, seq, SimCommand, tick].
var _pending: Array = []
var _handlers: Dictionary = {}


func _init(net: NetTransport, sim_world: SimWorld) -> void:
	transport = net
	world = sim_world
	_handlers = {
		NetProtocol.Type.HELLO: _on_hello,
		NetProtocol.Type.PICK: _on_pick,
		NetProtocol.Type.RELEASE: _on_release,
		NetProtocol.Type.READY: _on_ready,
		NetProtocol.Type.CLAIM: _on_claim,
		NetProtocol.Type.RELEASE_CLAIM: _on_claim,
		NetProtocol.Type.COMMAND: _on_command,
		NetProtocol.Type.ABANDON: _on_pause_request,
		NetProtocol.Type.ABANDON_VOTE: _on_pause_request,
		NetProtocol.Type.TAKEOVER: _on_pause_request,
		NetProtocol.Type.BYE: _on_bye,
		NetTransport.CLOSED: _on_closed,
	}


## Handles everything the transport received since the last call, and expires
## sessions whose grace ran out.
func process(now_us: int) -> void:
	for item: Array in transport.take_inbound():
		var msg: Dictionary = item[1]
		var handler: Callable = _handlers.get(msg["t"], Callable())
		if handler.is_valid():
			handler.call(item[0], msg, now_us)
	for gone: NetSession in sessions.expire(now_us):
		by_id.erase(gone.id)
		transport.forget(gone.id)


## After the sim stepped: reports commands the sim rejected (or dropped, for a destroyed
## ship) to their senders, and routes the tick's events (FT-NET-011).
func after_ticks(events: Array[SimEvent]) -> void:
	var still: Array = []
	for p: Array in _pending:
		var c: SimCommand = p[2]
		if c.tick >= 0:
			if not c.accepted:
				_reject(p[0], p[1], CommandGate.SIM_REJECTED)
		elif world.tick > int(p[3]):
			_reject(p[0], p[1], CommandGate.SHIP_DESTROYED)
		else:
			still.append(p)
	_pending = still
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


## Sessions that receive a sim event: those whose ship belongs to the event's faction
## (FT-NET-010: no knowledge of another faction); events of no ship go to every
## picked session. PROVISIONAL: T042 filters per station.
func event_audience(e: SimEvent) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: NetSession in by_id.values():
		if not s.has_pick() or s.ship >= world.ship_count():
			continue
		if e.faction < 0 or world.faction_of(s.ship) == e.faction:
			out.append(s.id)
	return out


## Ships a client may pick: those without an AI (M1: the crewed ship).
func crew_ships() -> Array:
	var out: Array = []
	for id: int in world.ship_count():
		if not world.ai.is_enabled(id):
			var def: ShipDef = world.defs[id]
			out.append(
				{
					"id": id,
					"def": String(def.id),
					"name": def.display_name,
					"faction": world.faction_of(id)
				}
			)
	return out


## Sends a server event to one session.
func notify(session: NetSession, type: String, payload: Dictionary) -> void:
	transport.post_event(PackedInt32Array([session.id]), world.tick, type, payload)


# --- Hooks for later tasks. ---


## Why a new session can't be admitted, or "" (T046: FT-NET-014's 65th connection).
func admit_rule() -> String:
	var connected: int = 0
	for s: NetSession in by_id.values():
		if s.connected():
			connected += 1
	return NetProtocol.REJECT_FULL if connected >= max_sessions else ""


## Why a session may not pick this entry, or "" (T043: Captain once per ship,
## coverage-breaking changes mid-run, FT-NET-016, FT-NET-043).
func pick_rule(_session: NetSession, _ship: int, _entry: String) -> String:
	return ""


## Why the claims refuse a command, or "" (T044: FT-NET-023, FT-NET-045).
func claim_rule(_session: NetSession, _command: SimCommand) -> String:
	return ""


## A session's connection dropped (T045: grace, coverage pause, FT-NET-033/034).
func on_disconnect(_session: NetSession, _now_us: int) -> void:
	pass


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
	var resumed: bool = session != null
	if not resumed:
		var why: String = admit_rule()
		if why != "":
			_refuse(conn, why)
			return
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
		"lang": language,
	}
	transport.bind(conn, session.id, welcome, session.view_key(), not resumed)
	transport.send(
		conn,
		NetProtocol.encode(
			NetProtocol.Type.CATALOGUE,
			{"ships": crew_ships(), "entries": StationViews.catalogue(dev_all), "load_tags": []}
		)
	)


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
	var crew: bool = ship >= 0 and ship < world.ship_count() and not world.ai.is_enabled(ship)
	if not crew or not StationViews.is_entry(entry, dev_all):
		reason = "bad_pick"
	else:
		reason = pick_rule(s, ship, entry)
	if reason == "":
		s.ship = ship
		s.entry = entry
		transport.set_view(s.id, s.view_key())
	notify(s, NetProtocol.EVENT_PICKED, {"ship": ship, "entry": entry, "reason": reason})


func _on_release(conn: int, _msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	s.ship = -1
	s.entry = ""
	s.ready = false
	transport.set_view(s.id, "")
	notify(s, NetProtocol.EVENT_PICKED, {"ship": -1, "entry": "", "reason": ""})


## T043 adds the coverage check and Start.
func _on_ready(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s != null:
		s.ready = msg["ready"] and s.has_pick()


## T044 implements claims.
func _on_claim(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s != null:
		notify(
			s,
			EVENT_REQUEST_REJECTED,
			{"request": int(msg["t"]), "item": msg["item"], "reason": NOT_IMPLEMENTED}
		)


## T045 implements abandon, abandon votes and takeover during a pause (D96, D128).
func _on_pause_request(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s != null:
		notify(s, EVENT_REQUEST_REJECTED, {"request": int(msg["t"]), "reason": NOT_PAUSED})


func _on_command(conn: int, msg: Dictionary, now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	if s == null:
		return
	var result: Array = CommandGate.check(s, msg["cmd"], now_us, claim_rule)
	if result[0] == null:
		_reject(s.id, msg["seq"], result[1])
		return
	world.submit(result[0])
	_pending.append([s.id, msg["seq"], result[0], world.tick])


func _on_bye(conn: int, _msg: Dictionary, _now_us: int) -> void:
	transport.close(conn, 1000, "bye")


func _on_closed(conn: int, _msg: Dictionary, now_us: int) -> void:
	var s: NetSession = by_conn.get(conn)
	by_conn.erase(conn)
	if s == null or s.conn != conn:
		return
	sessions.drop(s, now_us)
	on_disconnect(s, now_us)


func _reject(session_id: int, seq: int, reason: String) -> void:
	rejections[reason] = rejections.get(reason, 0) + 1
	transport.post_event(
		PackedInt32Array([session_id]),
		world.tick,
		NetProtocol.EVENT_COMMAND_REJECTED,
		{"seq": seq, "reason": reason}
	)
