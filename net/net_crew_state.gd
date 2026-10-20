class_name NetCrewState
extends RefCounted
## Each ship's marks, alert level and pings (D171): crew state outside the sim, the
## command log and the state hash. It holds the rules (CrewMarks, CrewPings) and answers
## the Alert, Mark and Ping messages for ServerSession, which registers these handlers;
## events go to every pick on the sender's ship only (FT-SPA-016, FT-SPA-020).
## A contact a mark or ping names must be one of the sender's faction or one it detects,
## and a site one the world has; unknown and undetected ids get the same refusal, so a
## client can't count the ships it doesn't see.

## The owning session, held weakly: it owns this object, and a strong reference back
## would leak both (and the world they hold) when the server goes.
var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession
var marks: CrewMarks = CrewMarks.new()
var pings: CrewPings = CrewPings.new()

var _session: WeakRef


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)


## The current alert and marks of the session's ship, after a (re)join or a pick.
func send_to(s: NetSession) -> void:
	session.notify(s, NetProtocol.EVENT_ALERT, _alert_payload(s.ship, ""))
	session.notify(s, NetProtocol.EVENT_MARKS, _marks_payload(s.ship))


## A run reset: the ship's marks and pings cleared and its alert back to Normal, told to
## its picks.
func reset(ship: int) -> void:
	marks.reset(ship)
	pings.reset(ship)
	_to_ship(ship, NetProtocol.EVENT_MARKS, _marks_payload(ship))
	_to_ship(ship, NetProtocol.EVENT_ALERT, _alert_payload(ship, ""))


## Alert{level}: any crew pick sets its ship's alert level (FT-STN-008, D89).
func on_alert(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var level: int = msg["level"]
	var why: String = marks.set_alert(s.ship, CrewMarks.role_of(s.entry), level)
	if why != "":
		session.request_rejected(s, NetProtocol.Type.ALERT, why, {"level": level})
		return
	_to_ship(s.ship, NetProtocol.EVENT_ALERT, _alert_payload(s.ship, s.name))


## Mark{op, ...}: place, move, rename or delete one of the ship's marks (CrewMarks).
func on_mark(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var role: CrewMarks.Role = CrewMarks.role_of(s.entry)
	var slot: int = msg["slot"]
	var why: String = ""
	if not s.has_pick():
		why = ServerSession.NOT_CREW
	else:
		match msg["op"]:
			"place":
				why = marks.place(s.ship, role, s.id, s.name, slot, msg["name"], _spot(s, msg))
			"move":
				why = marks.move(s.ship, role, s.id, slot, _spot(s, msg))
			"rename":
				why = marks.rename(s.ship, role, s.id, slot, msg["name"])
			"delete":
				why = marks.delete(s.ship, role, s.id, slot)
			_:
				why = CrewMarks.BAD_MARK
	if why != "":
		session.request_rejected(s, NetProtocol.Type.MARK, why, {"op": msg["op"], "slot": slot})
		return
	_to_ship(s.ship, NetProtocol.EVENT_MARKS, _marks_payload(s.ship))


## Ping{kind, id, site, x, y, z}: any crew pick and the Captain ping an item for every
## pick on the ship, viewers included (FT-SPA-016, FT-SPA-020), rate-limited per session
## (FT-SPA-017); a ping on an item another session pinged within 3 s is a copy naming
## that first pinger (FT-SPA-031).
func on_ping(conn: int, msg: Dictionary, now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var kind: String = msg["kind"]
	var payload: Dictionary = {"ship": s.ship, "kind": kind, "id": -1, "site": -1}
	payload.merge({"x": 0.0, "y": 0.0, "z": 0.0})
	var why: String = ""
	if not s.has_pick() or CrewMarks.role_of(s.entry) == CrewMarks.Role.NONE:
		why = ServerSession.NOT_CREW
	elif not pings.take(s.id, now_us):
		why = CommandGate.RATE_LIMITED
	else:
		match kind:
			"contact":
				payload["id"] = msg["id"]
				if not _known(s, msg["id"]):
					why = CrewPings.BAD_PING
			"mark":
				payload["id"] = msg["id"]
				if not marks.has_mark(s.ship, msg["id"]):
					why = CrewPings.BAD_PING
			"site", "point":
				payload["site"] = msg["site"]
				var at: PackedFloat64Array = session.world.kin.wrap_point(
					msg["x"], msg["y"], msg["z"]
				)
				if not _is_site(msg["site"]) or (kind == "point" and at.is_empty()):
					why = CrewPings.BAD_PING
				elif kind == "point":
					payload.merge({"x": at[0], "y": at[1], "z": at[2]}, true)
			_:
				why = CrewPings.BAD_PING
	if why != "":
		session.request_rejected(s, NetProtocol.Type.PING, why, {"kind": kind})
		return
	payload["by"] = s.name
	payload["copy"] = pings.copy_of(
		s.ship, kind, payload["id"], payload["site"], s.id, s.name, now_us
	)
	_to_ship(s.ship, NetProtocol.EVENT_PING, payload)


## Whether the sender's faction may name this ship: its own, or one it detects now.
func _known(s: NetSession, contact: int) -> bool:
	var world: SimWorld = session.world
	return (
		contact >= 0
		and contact < world.ship_count()
		and KnowledgeSystem.is_detected(world, world.faction_of(s.ship), contact)
	)


## Whether a ship of the world is at the site.
func _is_site(site: int) -> bool:
	return site >= 0 and session.world.kin.site.has(site)


## A Mark message's place as CrewMarks takes it: a contact the sender can't name becomes
## -2, a site the world lacks -1, and a free point is wrapped onto the site's cube
## (NaN when not finite), so CrewMarks refuses them all alike (BAD_MARK).
func _spot(s: NetSession, msg: Dictionary) -> Dictionary:
	var contact: int = msg["contact"]
	if contact >= 0 and not _known(s, contact):
		contact = -2
	var at: PackedFloat64Array = session.world.kin.wrap_point(msg["x"], msg["y"], msg["z"])
	if at.is_empty():
		at = PackedFloat64Array([NAN, NAN, NAN])
	var site: int = msg["site"] if _is_site(msg["site"]) else -1
	return {"contact": contact, "site": site, "x": at[0], "y": at[1], "z": at[2]}


func _alert_payload(ship: int, by: String) -> Dictionary:
	return {"ship": ship, "level": marks.alert(ship), "by": by}


func _marks_payload(ship: int) -> Dictionary:
	return {"ship": ship, "marks": marks.marks_of(ship)}


## An event to every session with a pick on the ship, and no other ship (FT-SPA-016,
## FT-SPA-020).
func _to_ship(ship: int, type: String, payload: Dictionary) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for s: NetSession in session.by_id.values():
		if s.ship == ship and s.has_pick():
			ids.append(s.id)
	session.transport.post_event(ids, session.world.tick, type, payload)
