class_name NetShares
extends RefCounted
## Explicit data shortcuts (spec §7.2, FT-PAIR-007, D84, D210): with a shortcut's toggle on,
## the source station still has to press share before the partner sees the data. A press
## keeps the shortcut open for DataToggles.share_seconds() (a newer press renews it); then
## the partner's view loses it again. A joint view holding both stations needs no press
## (FT-JNT-005). Each press is a cooperative event of the pair (CoopEvents.SHORTCUT_SHARED).
## Message: Share{feature}. The open set of a ship goes to the sessions' views as the
## "#a,b" suffix of the toggle code (NetSession.view_code, ViewFilter) and to the clients as
## the `shares` event, so a client's own shortcuts (hazard countdowns) follow. Crew state
## outside the sim, like chips; a run reset clears it.

## request_rejected reasons.
const OFF: String = "share_off"
const BAD_FEATURE: String = "share_bad_feature"
const NOT_SOURCE: String = "share_not_source"
const SAME_SCREEN: String = "share_same_screen"

## The owning session, held weakly (it owns this object).
var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession

var _session: WeakRef
## Ship -> feature -> sim tick the share ends at.
var _until: Dictionary[int, Dictionary] = {}


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)


## Share{feature}.
func on_share(conn: int, msg: Dictionary, _now_us: int) -> void:
	var s: NetSession = session.by_conn.get(conn)
	if s == null:
		return
	var why: String = share(s, msg["feature"])
	if why != "":
		session.request_rejected(s, NetProtocol.Type.SHARE, why, {"feature": msg["feature"]})


## Opens (or renews) a shortcut from the session's station; the reason it can't, or "".
func share(s: NetSession, feature: String) -> String:
	var id: StringName = StringName(feature)
	var def: DataToggleDef = DataToggles.toggle_def(id)
	var why: String = ""
	if def == null or not DataToggles.shareable().has(id):
		why = BAD_FEATURE
	elif not s.has_pick():
		why = NOT_SOURCE
	elif not session.toggles.on(id):
		why = OFF
	else:
		var stations: Array[String] = StationViews.stations_of(s.entry)
		if not stations.has(String(def.source)):
			why = NOT_SOURCE
		elif stations.has(String(def.target)):
			why = SAME_SCREEN
	if why != "":
		return why
	var ticks: int = ceili(DataToggles.share_seconds() * SimWorld.HZ)
	(_until.get_or_add(s.ship, {}) as Dictionary)[id] = session.world.tick + ticks
	var pair: String = CoopEvents.pair_of(String(def.source), String(def.target))
	session.coop.record(CoopEvents.SHORTCUT_SHARED, pair, s.ship, {"event": feature})
	_apply(s.ship, true)
	return ""


## Whether the shortcut is open on the ship now.
func active(ship: int, feature: StringName) -> bool:
	return _until.get(ship, {}).has(feature)


## The ship's open shortcuts, sorted.
func active_of(ship: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _until.get(ship, {}):
		out.append(id)
	out.sort()
	return out


## Closes the shares whose time is up.
func step() -> void:
	var tick: int = session.world.tick
	for ship: int in _until.keys():
		var open: Dictionary = _until[ship]
		var ended: bool = false
		for id: StringName in open.keys():
			if tick >= int(open[id]):
				open.erase(id)
				ended = true
		if open.is_empty():
			_until.erase(ship)
		if ended:
			_apply(ship, false)


## A run reset: every share goes.
func reset(ship: int) -> void:
	if _until.erase(ship):
		_apply(ship, false)


## Tells a session its ship's shares (a pick or a rejoin).
func send_to(s: NetSession) -> void:
	session.notify(s, NetProtocol.EVENT_SHARES, _payload(s.ship))


## The set of a ship changed: the picks' views and clients follow, routes and the revealed
## causes catch up. `pressed` is true after a press, which also hands over what exists now.
func _apply(ship: int, pressed: bool) -> void:
	var open: Array[StringName] = active_of(ship)
	for s: NetSession in session.by_id.values():
		if s.ship != ship or not s.has_pick():
			continue
		s.shares = open
		session.transport.set_view(s.id, s.view_key())
		session.notify(s, NetProtocol.EVENT_SHARES, _payload(ship))
	session.crew.sync_routes(ship)
	session.crew.sync_lanes(ship)
	if pressed and active(ship, ViewFilter.DIAGNOSED_CAUSES):
		prefill_causes(ship)


## The pick of one subsystem's revealed cause, unless Engineering made one (D210: also when
## Science shares the diagnosed causes after the scan).
func prefill_cause(ship: int, subsystem: StringName) -> void:
	var t: DamageTable = session.world.damage
	var r: int = t.find_subsystem(ship, subsystem)
	if r < 0 or t.fault_pick[r] != &"":
		return
	var c: PickFaultCauseCommand = PickFaultCauseCommand.new()
	c.ship_id = ship
	c.subsystem_id = subsystem
	c.cause = DamageSystem.known_fault_cause(session.world, ship, subsystem)
	if c.cause != &"":
		session.world.submit(c)


## Every revealed cause of the ship becomes Engineering's pick (the diagnosed causes were
## just shared).
func prefill_causes(ship: int) -> void:
	var t: DamageTable = session.world.damage
	var r: int = t.hull_row(ship) + 1
	while r > 0 and r < t.size() and t.ship_ids[r] == ship:
		if t.fault_known[r] == 1:
			prefill_cause(ship, t.part_ids[r])
		r += 1


func _payload(ship: int) -> Dictionary:
	var left: Dictionary = {}
	var tick: int = session.world.tick
	for id: StringName in _until.get(ship, {}):
		left[String(id)] = maxf(0.0, (int(_until[ship][id]) - tick) * SimWorld.DT)
	return {"ship": ship, "left": left}
