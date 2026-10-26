class_name NetHostPause
extends RefCounted
## The host pause (FT-MIS-040, D100, D127): in a co-op session the host pauses or resumes
## the whole universe through the pause events of the coverage pause (FT-NET-034), without
## an abandon vote. The flag is ServerSession.host_paused; it is independent of the
## coverage pause, which a host pause leaves alone: the `resume` event goes out only when
## neither pause is left. Message: HostPause{on}.

## request_rejected reason: any two crew factions are hostile, or the session has no host.
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
	var on: bool = msg["on"]
	if on == session.host_paused:
		return
	session.host_paused = on
	if not on and not session.paused.is_empty():
		return  # a coverage pause still holds the universe: no resume until it ends
	var ids: PackedInt32Array = PackedInt32Array(session.by_id.keys())
	var type: String = NetProtocol.EVENT_PAUSE if on else NetProtocol.EVENT_RESUME
	var body: Dictionary = payload() if on else {"tick": session.world.tick, "host": true}
	session.transport.post_event(ids, session.world.tick, type, body)


## Whether any two crew factions are hostile (PvP: no pause).
func is_pvp() -> bool:
	var ships: Array = session.crew_ships()
	for i: int in ships.size():
		for j: int in range(i + 1, ships.size()):
			if (
				session.world.relation(ships[i]["faction"], ships[j]["faction"])
				== SimWorld.Relation.HOSTILE
			):
				return true
	return false


## The `pause` event of a host pause: no ship, nothing uncovered.
func payload() -> Dictionary:
	return {"host": true, "ship": -1, "uncovered": [], "crew": 0, "min_crew": session.min_crew()}


## A (re)joining client starts in sync.
func send_to(to: NetSession) -> void:
	if session.host_paused:
		session.notify(to, NetProtocol.EVENT_PAUSE, payload())
