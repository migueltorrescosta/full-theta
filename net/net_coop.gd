class_name NetCoop
extends CoopEvents
## Watches the server for the cooperative events of FT-PAIR-013 that are not chips (NetChips
## counts those, and NetShares the data shortcuts a source station shares): a mark one
## station placed and another used, a probe-enabled scan. ServerSession calls the hooks;
## the counts and the log lines are CoopEvents'. A joint view's own stations are no pair
## between players, so work inside one view counts nothing.

## Ticks between two counts of the same mark used by the same player (60 Hz: 10 s).
const REUSE_TICKS: int = 600
## Ticks between two looks at whether a ship reached a scan position (60 Hz: 0.5 s).
const SCAN_LOOK_TICKS: int = 30

## The owning session, held weakly (it owns this object).
var session: ServerSession:
	get:
		return _session.get_ref() as ServerSession

var _session: WeakRef
## Ship -> whether its open scan or hack started inside a probe's bubble.
var _probe_scans: Dictionary[int, bool] = {}
## "ship|slot|user session" -> tick of the last count.
var _used_at: Dictionary[String, int] = {}
## The tick of the last look for a ship at a scan position.
var _looked_at: int = -SCAN_LOOK_TICKS
## "ship|zone id" -> true once the ship reached that scan position.
var _reached: Dictionary[String, bool] = {}


func _init(server_session: ServerSession) -> void:
	_session = weakref(server_session)


## A sim event of the tick.
func on_sim_event(e: SimEvent) -> void:
	match e.kind:
		&"scan_started", &"hack_started":
			_probe_scans[e.ship_id] = (
				e.ship_id < session.world.science.size()
				and (session.world.science.probe[e.ship_id] == 1)
			)
		&"scan_done", &"hack_done":
			if _probe_scans.get(e.ship_id, false):
				record(
					PROBE_SCAN, pair_of("science", "relay"), e.ship_id, {"event": String(e.kind)}
				)
			_probe_scans.erase(e.ship_id)
		&"scan_failed", &"hack_failed", &"hack_traced", &"science_refused":
			_probe_scans.erase(e.ship_id)


## A ping on mark `slot` by a session: a use when another station placed it.
func on_mark_pinged(user: NetSession, slot: int) -> void:
	_mark_used(user, slot)


## An accepted command: a guided shot at a mark's contact uses that mark.
func on_command(session_id: int, c: SimCommand) -> void:
	if c.kind() != &"fire_guided":
		return
	var user: NetSession = session.by_id.get(session_id)
	if user == null:
		return
	var g: FireGuidedCommand = c as FireGuidedCommand
	var marks: CrewMarks = session.crew.marks
	for m: Dictionary in marks.marks_of(c.ship_id):
		if m["contact"] == g.target:
			_mark_used(user, m["slot"])


## Once per frame: a ship reaching the scan position Science marked uses that mark (P3).
func step() -> void:
	var world: SimWorld = session.world
	if world.tick - _looked_at < SCAN_LOOK_TICKS and world.tick >= _looked_at:
		return
	_looked_at = world.tick
	for ship: int in session.launched:
		if not session.in_play(ship):
			continue
		for z: Dictionary in session.crew.relay.zones_of(ship):
			var key: String = "%d|%d" % [ship, z["id"]]
			if z["kind"] != CrewRelay.KIND_SCAN or z["by"] != NetCrewState.SCIENCE_BY:
				continue
			if _reached.has(key):
				continue
			if _within(world, ship, z):
				_reached[key] = true
				record(MARK_USED, pair_of("science", "helm"), ship, {"mark": "scan_position"})


func reset_ship(ship: int) -> void:
	_probe_scans.erase(ship)
	for key: String in _used_at.keys():
		if key.begins_with("%d|" % ship):
			_used_at.erase(key)
	for key: String in _reached.keys():
		if key.begins_with("%d|" % ship):
			_reached.erase(key)


func _within(world: SimWorld, ship: int, z: Dictionary) -> bool:
	var kin: Kinematics = world.kin
	if kin.site[ship] != z["site"]:
		return false
	var p: PackedFloat64Array = kin.point_at(ship, Vector3.ZERO)
	var d: Vector3 = Vector3(
		kin.wrap(z["x"] - p[0]), kin.wrap(z["y"] - p[1]), kin.wrap(z["z"] - p[2])
	)
	return d.length() <= float(z["radius"])


func _mark_used(user: NetSession, slot: int) -> void:
	var placer: NetSession = session.by_id.get(session.crew.marks.placer_of(user.ship, slot))
	if placer == null or placer.id == user.id or placer.ship != user.ship:
		return
	var pair: String = _first_pair(
		StationViews.stations_of(placer.entry), StationViews.stations_of(user.entry)
	)
	if pair == "":
		return
	var key: String = "%d|%d|%d" % [user.ship, slot, user.id]
	var tick: int = session.world.tick
	if _used_at.has(key) and tick - _used_at[key] < REUSE_TICKS:
		return
	_used_at[key] = tick
	record(MARK_USED, pair, user.ship, {"mark": slot})


## The pair of the first station of the placer and the first of the user that aren't each
## other's own stations; "" when they share all of them.
static func _first_pair(placed: Array[String], used: Array[String]) -> String:
	for a: String in placed:
		for b: String in used:
			if a != b and not used.has(a) and not placed.has(b):
				return pair_of(a, b)
	return ""
