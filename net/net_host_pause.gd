class_name NetHostPause
extends RefCounted
## The host pause (FT-MIS-040, D100, D127): in a co-op session the host pauses or resumes
## the whole universe through the pause events of the coverage pause (FT-NET-034), without
## an abandon vote. The flag is ServerSession.host_paused; it is independent of the
## coverage pause: each pause that lifts sends its own `resume` (`host` true for this one),
## and the sim runs only when neither holds (ServerSession.sim_running). A host who has
## not returned within the reconnect grace ends the pause by itself (Q19, owner
## 2026-10-26, D188). Message: HostPause{on}.

## request_rejected reason: the session's mode is PvP (FT-MIS-040), or it has no host.
const PVP_NO_PAUSE: String = "pvp_no_pause"

## The owning session, held weakly (it owns this object).
var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession

var _session: WeakRef


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)
	server_session.add_handler(NetProtocol.Type.HOST_PAUSE, on_host_pause)


## HostPause{on}: `pvp_no_pause` in PvP or without a host, `not_host` from anyone else.
func on_host_pause(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var reason: String = ""
	if session.host_secret == "" or is_pvp():
		reason = PVP_NO_PAUSE
	elif not s.is_host:
		reason = ServerSession.NOT_HOST
	if reason != "":
		session.request_rejected(s, NetProtocol.Type.HOST_PAUSE, reason, {})
		return
	set_paused(msg["on"])


## Sets the host pause and tells every client; a no-op when it already is so. The `resume`
## goes out even while a coverage pause holds: a client clears only the flag it names.
func set_paused(on: bool) -> void:
	if on == session.host_paused:
		return
	session.host_paused = on
	var ids: PackedInt32Array = PackedInt32Array(session.by_id.keys())
	var type: String = NetProtocol.EVENT_PAUSE if on else NetProtocol.EVENT_RESUME
	var body: Dictionary = payload() if on else {"tick": session.world.tick, "host": true}
	session.transport.post_event(ids, session.world.tick, type, body)


## Whether the session's mode is PvP (SessionRules.is_pvp, NetFleet.rules): no host pause.
func is_pvp() -> bool:
	return session.fleet.rules.is_pvp()


## The `pause` event of a host pause: no ship, nothing uncovered.
func payload() -> Dictionary:
	return {"host": true, "ship": -1, "uncovered": [], "crew": 0, "min_crew": session.min_crew()}


## A (re)joining client starts in sync.
func send_to(to: NetSession) -> void:
	if session.host_paused:
		session.notify(to, NetProtocol.EVENT_PAUSE, payload())
