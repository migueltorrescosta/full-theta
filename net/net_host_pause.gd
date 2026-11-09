class_name NetHostPause
extends RefCounted
## The host pause (FT-MIS-040, D100, D127): in a co-op session the host pauses or resumes
## the whole universe through the pause events of the coverage pause (FT-NET-034), without
## an abandon vote. The flag is `paused` here; it is independent of the
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

## Whether the host paused the universe (ServerSession.sim_running reads it).
var paused: bool = false

var _session: WeakRef


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)
	server_session.add_handler(NetProtocol.Type.HOST_PAUSE, on_host_pause)


## HostPause{on}: `pvp_no_pause` in PvP or without a host, `not_host` from anyone else.
func on_host_pause(s: NetSession, msg: Dictionary, _now_us: int) -> void:
	var reason: String = ""
	if session.host_secret == "" or is_pvp():
		reason = PVP_NO_PAUSE
	elif not s.is_host:
		reason = ServerSession.NOT_HOST
	if session.refuse(s, NetProtocol.Type.HOST_PAUSE, reason, {}):
		return
	set_paused(msg["on"])


## Sets the host pause and tells every client; a no-op when it already is so. The `resume`
## goes out even while a coverage pause holds: a client clears only the flag it names.
func set_paused(on: bool) -> void:
	if on == paused:
		return
	paused = on
	if on:
		session.broadcast(NetProtocol.EVENT_PAUSE, payload())
	else:
		session.broadcast(NetProtocol.EVENT_RESUME, FleetMessages.resume(session.world.tick, true))


## Whether the session's mode is PvP (SessionRules.is_pvp, NetFleet.rules): no host pause.
func is_pvp() -> bool:
	return session.fleet.rules.is_pvp()


## The `pause` event of a host pause: no ship, nothing uncovered.
func payload() -> Dictionary:
	return FleetMessages.pause(-1, [], 0, session.lobby.min_crew(), true)


## A (re)joining client starts in sync.
func send_to(to: NetSession) -> void:
	if paused:
		session.notify(to, NetProtocol.EVENT_PAUSE, payload())
