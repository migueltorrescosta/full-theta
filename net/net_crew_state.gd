class_name NetCrewState
extends RefCounted
## Each ship's marks, alert level and pings (D171): crew state outside the sim, the
## command log and the state hash. It holds the rules (CrewMarks, CrewPings) and answers
## the Alert, Mark and Ping messages for ServerSession, which registers these handlers;
## events go to every pick on the sender's ship only (FT-SPA-016, FT-SPA-020).
## A contact a mark or ping names must be one of the sender's faction or one it detects,
## and a site one the world has; unknown and undetected ids get the same refusal, so a
## client can't count the ships it doesn't see.

## Sim events kept in the ship's log: event kind -> log key (i18n relay.log.<key>).
## The `by` of the scan position Science's mark creates.
const SCIENCE_BY: String = "science"
const LOG_EVENTS: Dictionary = {
	&"contact_detected": "contact_detected",
	&"contact_lost": "contact_lost",
	&"probe_launched": "probe_launched",
	&"probe_deployed": "probe_deployed",
	&"probe_no_stock": "probe_no_stock",
	&"probe_fabricated": "probe_fabricated",
	&"lane_warning": "lane_warning",
}

## The owning session, held weakly: it owns this object, and a strong reference back
## would leak both (and the world they hold) when the server goes.
var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession
var marks: CrewMarks = CrewMarks.new()
var pings: CrewPings = CrewPings.new()
## Relay's zones, routes, mark inbox and log (E02).
var relay: CrewRelay = CrewRelay.new()
## Whether the sender's faction has scanned a contact's subsystem so far that its weak
## point shows (D202): Callable(world, faction, contact, subsystem) -> bool. Science's
## scan state (KNOW) answers it; until that lands nothing is revealed. Tests set it.
var weak_check: Callable = Callable()

var _session: WeakRef


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)


## The current alert and marks of the session's ship, after a (re)join or a pick.
func send_to(s: NetSession) -> void:
	session.notify(s, NetProtocol.EVENT_ALERT, _alert_payload(s.ship, ""))
	session.notify(s, NetProtocol.EVENT_MARKS, _marks_payload(s.ship))
	session.notify(s, NetProtocol.EVENT_SITES, _sites_payload())
	session.notify(s, NetProtocol.EVENT_ZONES, _zones_payload(s.ship))
	if _sees_routes(s):
		session.notify(s, NetProtocol.EVENT_ROUTES, _routes_payload(s.ship))
	if _is_relay(s):
		session.notify(s, NetProtocol.EVENT_INBOX, _inbox_payload(s.ship))
		session.notify(s, NetProtocol.EVENT_RELAY_LOG, _log_payload(s.ship, true))


## A run reset: the ship's marks and pings cleared and its alert back to Normal, told to
## its picks.
func reset(ship: int) -> void:
	marks.reset(ship)
	pings.reset(ship)
	relay.reset(ship)
	_to_ship(ship, NetProtocol.EVENT_ZONES, _zones_payload(ship))
	_to_ship(ship, NetProtocol.EVENT_ROUTES, _routes_payload(ship))
	_to_relay(ship, NetProtocol.EVENT_INBOX, _inbox_payload(ship))
	_to_relay(ship, NetProtocol.EVENT_RELAY_LOG, _log_payload(ship, true))
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
			"route_add", "route_clear", "hazard_add", "hazard_delete":
				why = _on_relay_item(s, role, msg)
				if why == "":
					return
			_:
				why = CrewMarks.BAD_MARK
	if why != "":
		session.request_rejected(s, NetProtocol.Type.MARK, why, {"op": msg["op"], "slot": slot})
		return
	_to_ship(s.ship, NetProtocol.EVENT_MARKS, _marks_payload(s.ship))


## MarkSend{slot, ship}: Relay sends one of its ship's marks to another ship of its
## faction; it waits in that ship's Relay inbox (FT-RLY-008, FT-SPA-021). An attached
## mark goes as the point where its contact is now.
func on_mark_send(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var to: int = msg["ship"]
	var why: String = ""
	if not s.has_pick() or CrewMarks.role_of(s.entry) != CrewMarks.Role.RELAY:
		why = CrewRelay.NOT_RELAY
	elif not marks.has_mark(s.ship, msg["slot"]):
		why = CrewMarks.BAD_MARK
	elif not _allied(s.ship, to):
		why = CrewRelay.BAD_TARGET
	if why == "":
		var mark: Dictionary = _resolved(s.ship, msg["slot"])
		if mark.is_empty():
			why = CrewMarks.BAD_MARK
		else:
			why = relay.send(to, s.ship, _ship_name(s.ship), mark)
	if why != "":
		session.request_rejected(s, NetProtocol.Type.MARK_SEND, why, {"slot": msg["slot"]})
		return
	_to_relay(to, NetProtocol.EVENT_INBOX, _inbox_payload(to))
	_log(s.ship, "mark_sent", {"name": _resolved(s.ship, msg["slot"])["name"]})
	_log(to, "mark_received", {"from": _ship_name(s.ship)})


## MarkAccept{id, accept, slot}: the receiving Relay accepts the pending mark `id` as one
## of its ship's marks, or declines it (FT-RLY-009, FT-SPA-021). With 8 marks an accept
## must name the slot to replace, else it is refused (FT-SPA-022, D182).
func on_mark_accept(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var why: String = ""
	var pending: Dictionary = {}
	if not s.has_pick() or CrewMarks.role_of(s.entry) != CrewMarks.Role.RELAY:
		why = CrewRelay.NOT_RELAY
	else:
		for item: Dictionary in relay.inbox_of(s.ship):
			if item["id"] == msg["id"]:
				pending = item
		if pending.is_empty():
			why = CrewRelay.BAD_INBOX
	if why == "" and msg["accept"]:
		var spot: Dictionary = {
			"contact": -1,
			"site": pending["site"],
			"x": pending["x"],
			"y": pending["y"],
			"z": pending["z"],
		}
		why = marks.place(
			s.ship, CrewMarks.Role.RELAY, s.id, s.name, msg["slot"], pending["name"], spot
		)
	if why != "":
		session.request_rejected(s, NetProtocol.Type.MARK_ACCEPT, why, {"id": msg["id"]})
		return
	relay.take(s.ship, msg["id"])
	_to_relay(s.ship, NetProtocol.EVENT_INBOX, _inbox_payload(s.ship))
	if msg["accept"]:
		_to_ship(s.ship, NetProtocol.EVENT_MARKS, _marks_payload(s.ship))
	_log(s.ship, "mark_accepted" if msg["accept"] else "mark_declined", {"name": pending["name"]})


## A sim event of the tick, for the ship's log (FT-RLY-006, FT-RLY-007): detections and
## losses, probes and lane warnings of the event's ship, as keys and arguments, never
## text of a character.
func on_sim_event(e: SimEvent) -> void:
	if e.kind == &"scan_mark":
		_science_scan_position(e.ship_id)
		return
	var key: String = LOG_EVENTS.get(e.kind, "")
	if key == "" or e.ship_id < 0:
		return
	var args: Dictionary = {}
	match e.kind:
		&"contact_detected", &"contact_lost":
			args = {"callsign": String(e.tag)}
		&"probe_launched", &"probe_deployed":
			args = {"n": int(e.value) + 1}
		&"lane_warning":
			args = {"callsign": _ship_name(e.other_id)}
	_log(e.ship_id, key, args, e.tick)


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


## The Mark message's zone and route ops (Relay only): the point is (site, x, y, z); a
## hazard's radius is `slot` hundreds of metres; `slot` is the route or zone id.
## Returns "" once it answered, else the refusal.
func _on_relay_item(s: NetSession, role: CrewMarks.Role, msg: Dictionary) -> String:
	if role != CrewMarks.Role.RELAY:
		return CrewRelay.NOT_RELAY
	var at: PackedFloat64Array = session.world.kin.wrap_point(msg["x"], msg["y"], msg["z"])
	var op: String = msg["op"]
	var slot: int = msg["slot"]
	var why: String = ""
	match op:
		"route_add":
			if at.is_empty() or not _is_site(msg["site"]):
				return CrewRelay.BAD_ROUTE
			why = relay.route_add(s.ship, slot, msg["site"], Vector3(at[0], at[1], at[2]))
		"route_clear":
			why = relay.route_clear(s.ship, slot)
		"hazard_add":
			if at.is_empty() or not _is_site(msg["site"]):
				return CrewRelay.BAD_ZONE
			var centre: Vector3 = Vector3(at[0], at[1], at[2])
			var radius: float = slot * 100.0
			why = relay.add_zone(s.ship, CrewRelay.KIND_HAZARD, msg["site"], centre, radius, s.name)
		_:
			why = relay.delete_zone(s.ship, slot)
	if why != "":
		return why
	if op.begins_with("route"):
		for t: NetSession in session.by_id.values():
			if t.ship == s.ship and t.has_pick() and _sees_routes(t):
				session.notify(t, NetProtocol.EVENT_ROUTES, _routes_payload(s.ship))
		_log(s.ship, "route_" + op.trim_prefix("route_"), {"route": slot + 1})
	else:
		_to_ship(s.ship, NetProtocol.EVENT_ZONES, _zones_payload(s.ship))
		_log(s.ship, "hazard_" + op.trim_prefix("hazard_"))
	return ""


## Adds a scan position (Science's, FT-SPA-028) as a zone of the ship and tells its picks.
func add_scan_position(ship: int, site: int, at: Vector3, radius: float, by: String) -> String:
	var why: String = relay.add_zone(ship, CrewRelay.KIND_SCAN, site, at, radius, by)
	if why == "":
		_to_ship(ship, NetProtocol.EVENT_ZONES, _zones_payload(ship))
	return why


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
	var spot: Dictionary = {"contact": contact, "site": site, "x": at[0], "y": at[1], "z": at[2]}
	# An attached mark's x names a scanned subsystem as index + 1 (FT-SPA-014, D202); one
	# whose weak point no scan revealed isn't placed.
	if contact >= 0 and msg["x"] >= 1.0:
		var sub: int = int(msg["x"]) - 1
		var def: ShipDef = session.world.defs[contact]
		if sub >= def.subsystems.size() or not _revealed(s, contact, sub):
			spot["contact"] = -2
		else:
			spot["sub"] = sub
			spot["off"] = def.subsystems[sub].position
	return spot


## Whether the sender's faction has revealed that subsystem's weak point (D202):
## weak_check when a test set one, else Science's scan knowledge (FT-SIM-023).
func _revealed(s: NetSession, contact: int, sub: int) -> bool:
	var world: SimWorld = session.world
	var faction: int = world.faction_of(s.ship)
	if weak_check.is_valid():
		return weak_check.call(world, faction, contact, sub)
	return sub in ScienceKnowledge.weak_points(world, faction, contact)


## Science's scan-position mark (FT-SCI-010) becomes a scan position of the ship's zones
## (FT-SPA-028): one per ship, replacing the one Science made before; unchanged marks add
## nothing.
func _science_scan_position(ship: int) -> void:
	var world: SimWorld = session.world
	var def: ScienceDef = world.science_def
	if def == null or ship < 0 or ship >= world.science.size():
		return
	var t: ScienceTable = world.science
	var at: Vector3 = Vector3(t.mark_x[ship], t.mark_y[ship], t.mark_z[ship])
	for z: Dictionary in relay.zones_of(ship):
		if z["kind"] != CrewRelay.KIND_SCAN or z["by"] != SCIENCE_BY:
			continue
		if z["site"] == t.mark_site[ship] and Vector3(z["x"], z["y"], z["z"]) == at:
			return
		relay.delete_zone(ship, z["id"])
	add_scan_position(ship, t.mark_site[ship], at, def.mark_radius, SCIENCE_BY)


func _ship_name(ship: int) -> String:
	var world: SimWorld = session.world
	return world.defs[ship].display_name if ship >= 0 and ship < world.ship_count() else ""


func _allied(a: int, b: int) -> bool:
	var world: SimWorld = session.world
	return (
		b >= 0
		and b < world.ship_count()
		and b != a
		and world.faction_of(a) == world.faction_of(b)
		and not world.ai.is_enabled(b)
	)


## A mark of the ship as a free point: an attached one at its contact's position now.
## {name, site, x, y, z}, or {} when the slot is empty.
func _resolved(ship: int, slot: int) -> Dictionary:
	for m: Dictionary in marks.marks_of(ship):
		if m["slot"] != slot:
			continue
		var out: Dictionary = {"name": m["name"], "site": m["site"]}
		out.merge({"x": m["x"], "y": m["y"], "z": m["z"]})
		var c: int = m["contact"]
		if c >= 0:
			var kin: Kinematics = session.world.kin
			out.merge({"site": kin.site[c]}, true)
			var here: PackedFloat64Array = kin.point_at(c, Vector3(m["x"], m["y"], m["z"]))
			var at: Vector3 = Vector3(here[0], here[1], here[2])
			out.merge({"x": at.x, "y": at.y, "z": at.z}, true)
		return out
	return {}


func _is_relay(s: NetSession) -> bool:
	return s.has_pick() and CrewMarks.role_of(s.entry) == CrewMarks.Role.RELAY


## Routes reach Relay always and the other stations unless the toggle set is Hard
## (FT-SPA-029, FT-PAIR-008).
func _sees_routes(s: NetSession) -> bool:
	return s.has_pick() and (_is_relay(s) or s.toggles != "hard")


func _sites_payload() -> Dictionary:
	var out: Array = []
	var names: Dictionary[int, String] = session.world.site_names
	var ids: Array = names.keys()
	ids.sort()
	for id: int in ids:
		out.append({"site": id, "name": names[id]})
	return {"sites": out}


func _zones_payload(ship: int) -> Dictionary:
	return {"ship": ship, "zones": relay.zones_of(ship)}


func _routes_payload(ship: int) -> Dictionary:
	return {"ship": ship, "routes": relay.routes_of(ship)}


func _inbox_payload(ship: int) -> Dictionary:
	return {"ship": ship, "items": relay.inbox_of(ship)}


## The ship's log, whole (replace) or as new entries.
func _log_payload(ship: int, replace: bool, fresh: Array = []) -> Dictionary:
	return {"ship": ship, "entries": relay.log_of(ship) if replace else fresh, "replace": replace}


## Appends a log entry and tells the ship's Relay picks.
func _log(ship: int, key: String, args: Dictionary = {}, tick: int = -1) -> void:
	var entry: Dictionary = relay.log_entry(
		ship, tick if tick >= 0 else session.world.tick, key, args
	)
	_to_relay(ship, NetProtocol.EVENT_RELAY_LOG, _log_payload(ship, false, [entry]))


func _alert_payload(ship: int, by: String) -> Dictionary:
	return {"ship": ship, "level": marks.alert(ship), "by": by}


func _marks_payload(ship: int) -> Dictionary:
	return {"ship": ship, "marks": marks.marks_of(ship)}


## An event to the ship's Relay picks only (the inbox and the log).
func _to_relay(ship: int, type: String, payload: Dictionary) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for s: NetSession in session.by_id.values():
		if s.ship == ship and _is_relay(s):
			ids.append(s.id)
	session.transport.post_event(ids, session.world.tick, type, payload)


## An event to every session with a pick on the ship, and no other ship (FT-SPA-016,
## FT-SPA-020).
func _to_ship(ship: int, type: String, payload: Dictionary) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	for s: NetSession in session.by_id.values():
		if s.ship == ship and s.has_pick():
			ids.append(s.id)
	session.transport.post_event(ids, session.world.tick, type, payload)
