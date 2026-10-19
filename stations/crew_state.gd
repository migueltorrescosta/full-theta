class_name CrewState
extends RefCounted
## The client's model of everything that isn't a snapshot (#7): pick, catalogue, lobby,
## Start, claims, pause and abandon votes, alert level, marks, pings and the selection
## every panel of this client shares. Built from Welcome, the Catalogue and the event
## stream (docs/protocol.md "Events"); pure, time passed in. Panels read it and listen to
## `changed`; they never write it except through select() and the intents they send.

## What changed: &"picked", &"catalogue", &"lobby", &"started", &"claims", &"pause",
## &"votes", &"abandoned", &"alert", &"marks", &"pings", &"selection", &"reset",
## &"run_over" (the outcome card and its "Run again" votes, D178).
signal changed(what: StringName)
## A toast to show: translation key and format arguments (I18n strings).
signal toast(key: String, args: Dictionary)
## A new (not copy) ping arrived: the chime seam (FT-SPA-016; the alerts strand plays it).
signal pinged(ping: Dictionary)
## An event this model doesn't keep (sim events: hit, fault, ...): StationAlerts' seam.
signal sim_event(kind: StringName, payload: Dictionary)

## Marks per ship, named by slot (FT-SPA-012).
const MARK_NAMES: Array[String] = [
	"Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"
]
const MAX_MARKS: int = 8
## A ping pulses its item this long on every screen (FT-SPA-016).
const PING_MS: int = 3000
## Alert levels (provisional): 0 Normal, 1 Yellow, 2 Red.
const ALERT_NORMAL: int = 0
const ALERT_YELLOW: int = 1
const ALERT_RED: int = 2
const ALERT_LEVELS: int = 3
## Sim ticks per second (spec: 60 Hz), for the mission timer.
const TICK_HZ: float = 60.0

var session: int = -1
var ship: int = -1
var entry: String = ""
var host: bool = false
var dev_all: bool = false
var lang: String = "en"
## Catalogue message fields: ships [{id, def, name, faction}], entries [StationDef
## dicts], load_tags.
var catalogue: Dictionary = {}
## ship -> `lobby` payload.
var lobby: Dictionary = {}
## ship -> Start tick.
var started: Dictionary = {}
## ship -> `pause` payload, while paused.
var paused: Dictionary = {}
## ship -> {"voters": [...], "needed": int}.
var votes: Dictionary = {}
## ship -> "vote" | "host".
var abandoned: Dictionary = {}
## ship -> `run_over` payload {ship, outcome, time_s, hull} plus "voters" and "needed"
## from `run_votes`, from the outcome until the reset (D178).
var run_over: Dictionary = {}
## item -> {"session": int, "name": String} (claim events; free items erased).
var claims: Dictionary = {}
var alert: int = ALERT_NORMAL
var alert_by: String = ""
## Sorted by slot: {"slot", "name", "contact", "site", "pos" (Vector3, m), "by"}.
var marks: Array[Dictionary] = []
## Active pings, oldest first: {"kind", "id", "site", "pos", "by", "at_ms", "copies"}.
var pings: Array[Dictionary] = []
## The shared selection: {"kind": "contact" | "mark" | "site", "id": int}, or {}.
var selection: Dictionary = {}


## Takes the Welcome fields (NetClient.welcome).
func welcome(w: Dictionary) -> void:
	session = int(w.get("session", -1))
	ship = int(w.get("ship", -1))
	entry = str(w.get("entry", ""))
	host = bool(w.get("host", false))
	dev_all = bool(w.get("dev_all", false))
	lang = str(w.get("lang", "en"))
	changed.emit(&"picked")


func set_catalogue(c: Dictionary) -> void:
	catalogue = c
	changed.emit(&"catalogue")


## The StationDef dict of the current pick, or {}.
func entry_def() -> Dictionary:
	return def_of(entry)


func def_of(id: String) -> Dictionary:
	for d: Dictionary in catalogue.get("entries", []):
		if d.get("id", "") == id:
			return d
	return {}


## Functional stations of the pick (one, two for a joint view, six for the dev entry).
func stations() -> Array:
	return entry_def().get("stations", [])


## Crew picks set the alert level and place marks; Captain and viewers can't set the
## alert (FT-STN-008).
func is_crew() -> bool:
	return bool(entry_def().get("crew", false))


func ship_name(id: int = ship) -> String:
	for s: Dictionary in catalogue.get("ships", []):
		if int(s.get("id", -2)) == id:
			return str(s.get("name", ""))
	return ""


func is_started(id: int = ship) -> bool:
	return started.has(id) or bool(lobby.get(id, {}).get("started", false))


## Mission time (s) at sim tick `tick`; 0 before Start.
func mission_seconds(tick: int) -> float:
	if not started.has(ship):
		return 0.0
	return maxf(0.0, float(tick - int(started[ship])) / TICK_HZ)


## Consumes one event ({"type", "payload", ...}); false when it isn't one of the
## events this model keeps.
func handle_event(e: Dictionary, now_ms: int) -> bool:
	var p: Dictionary = e.get("payload", {})
	match str(e.get("type", "")):
		"picked":
			return _on_picked(p)
		"lobby":
			_on_lobby(p)
		"started":
			started[int(p["ship"])] = int(p.get("tick", 0))
			changed.emit(&"started")
		"claim":
			_on_claim(p)
		"pause":
			paused[int(p["ship"])] = p
			changed.emit(&"pause")
		"resume":
			paused.clear()
			votes.clear()
			changed.emit(&"pause")
		"abandon_votes":
			votes[int(p["ship"])] = {"voters": p.get("voters", []), "needed": p.get("needed", 0)}
			changed.emit(&"votes")
		"abandoned":
			abandoned[int(p["ship"])] = str(p.get("by", ""))
			changed.emit(&"abandoned")
		"run_over", "run_votes":
			var card: Dictionary = run_over.get_or_add(int(p["ship"]), {})
			card.merge(p, true)
			changed.emit(&"run_over")
		"alert":
			_on_alert(p)
		"marks":
			_on_marks(p)
		"ping":
			_on_ping(p, now_ms)
		"request_rejected", "command_rejected":
			toast.emit("toast." + str(p.get("reason", "rejected")), p)
		_:
			sim_event.emit(StringName(str(e.get("type", ""))), p)
			return false
	return true


## Sets the shared selection ({} clears it).
func select(kind: String, id: int) -> void:
	var s: Dictionary = {} if kind == "" else {"kind": kind, "id": id}
	if s == selection:
		return
	selection = s
	changed.emit(&"selection")


## Cycle target (FT-STN-009): the candidate after the selected one, in the given order
## (e.g. contacts by range); wraps; the first when nothing in the list is selected.
func cycle(kind: String, ids: Array) -> void:
	if ids.is_empty():
		return
	var i: int = -1
	if selection.get("kind", "") == kind:
		i = ids.find(selection["id"])
	select(kind, int(ids[(i + 1) % ids.size()]))


## The newest live ping, or {}.
func last_ping(now_ms: int) -> Dictionary:
	_expire(now_ms)
	return pings.back() if not pings.is_empty() else {}


## Select the last pinged item (Y / hold RB); false with no live ping or a point ping.
func select_pinged(now_ms: int) -> bool:
	var p: Dictionary = last_ping(now_ms)
	if p.is_empty() or p["kind"] == "point":
		return false
	select(p["kind"], p["id"])
	return true


## Pulse strength 1..0 of an item over PING_MS since its newest ping; 0 when none.
func pulse(kind: String, id: int, now_ms: int) -> float:
	var best: float = 0.0
	for p: Dictionary in pings:
		if p["kind"] == kind and p["id"] == id:
			best = maxf(best, 1.0 - float(now_ms - int(p["at_ms"])) / float(PING_MS))
	return clampf(best, 0.0, 1.0)


## Pings still pulsing at now_ms (point pings included).
func live_pings(now_ms: int) -> Array[Dictionary]:
	_expire(now_ms)
	return pings.duplicate()


func mark_in_slot(slot: int) -> Dictionary:
	for m: Dictionary in marks:
		if m["slot"] == slot:
			return m
	return {}


## Who holds a claim item ("" when free).
func claimer(item: String) -> String:
	return str(claims.get(item, {}).get("name", ""))


## Clears the run's state for a new run: marks, pings, selection, alert, outcome-era
## flags (FT-M1-012).
func reset_run() -> void:
	marks.clear()
	pings.clear()
	selection = {}
	alert = ALERT_NORMAL
	alert_by = ""
	started.erase(ship)
	abandoned.erase(ship)
	run_over.erase(ship)
	changed.emit(&"reset")


func _mine(p: Dictionary) -> bool:
	return int(p.get("ship", ship)) == ship


func _on_picked(p: Dictionary) -> bool:
	var reason: String = str(p.get("reason", ""))
	if reason != "":
		toast.emit("toast." + reason, p)
		return true
	ship = int(p.get("ship", -1))
	entry = str(p.get("entry", ""))
	claims.clear()
	changed.emit(&"picked")
	return true


func _on_lobby(p: Dictionary) -> void:
	var id: int = int(p["ship"])
	var was_started: bool = bool(lobby.get(id, {}).get("started", false))
	lobby[id] = p
	changed.emit(&"lobby")
	# The server resets a finished run: the ship is back in the lobby (FT-M1-012).
	if id == ship and was_started and not bool(p.get("started", false)):
		reset_run()


func _on_claim(p: Dictionary) -> void:
	if not _mine(p):
		return
	if int(p.get("session", -1)) < 0:
		claims.erase(str(p["item"]))
	else:
		claims[str(p["item"])] = {"session": int(p["session"]), "name": str(p.get("name", ""))}
	changed.emit(&"claims")


func _on_alert(p: Dictionary) -> void:
	if not _mine(p):
		return
	alert = clampi(int(p.get("level", 0)), 0, ALERT_LEVELS - 1)
	alert_by = str(p.get("by", ""))
	changed.emit(&"alert")


func _on_marks(p: Dictionary) -> void:
	if not _mine(p):
		return
	marks.clear()
	for m: Dictionary in p.get("marks", []):
		var slot: int = int(m.get("slot", 0))
		var mark_name: String = str(m.get("name", ""))
		if mark_name == "" and slot >= 0 and slot < MARK_NAMES.size():
			mark_name = MARK_NAMES[slot]
		(
			marks
			. append(
				{
					"slot": slot,
					"name": mark_name,
					"contact": int(m.get("contact", -1)),
					"site": int(m.get("site", 0)),
					"pos":
					Vector3(float(m.get("x", 0)), float(m.get("y", 0)), float(m.get("z", 0))),
					"by": str(m.get("by", "")),
				}
			)
		)
	marks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["slot"] < b["slot"])
	# A deleted mark can't stay selected.
	if selection.get("kind", "") == "mark" and mark_in_slot(selection["id"]).is_empty():
		selection = {}
		changed.emit(&"selection")
	changed.emit(&"marks")


## A copy (FT-SPA-031) names its station on the original ping, silently.
func _on_ping(p: Dictionary, now_ms: int) -> void:
	if not _mine(p):
		return
	_expire(now_ms)
	var kind: String = str(p.get("kind", "point"))
	var id: int = int(p.get("id", -1))
	# `copy` is the first pinger's name, "" for an original (docs/protocol.md).
	var copy: bool = str(p.get("copy", "")) not in ["", "false"]
	if copy:
		for old: Dictionary in pings:
			if old["kind"] == kind and old["id"] == id:
				(old["copies"] as Array).append(str(p.get("by", "")))
				changed.emit(&"pings")
				return
	var ping: Dictionary = {
		"kind": kind,
		"id": id,
		"site": int(p.get("site", 0)),
		"pos": Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0))),
		"by": str(p.get("by", "")),
		"at_ms": now_ms,
		"copies": [],
	}
	pings.append(ping)
	changed.emit(&"pings")
	if not copy:
		pinged.emit(ping)


func _expire(now_ms: int) -> void:
	while not pings.is_empty() and now_ms - int(pings[0]["at_ms"]) >= PING_MS:
		pings.pop_front()
