# gdlint: disable=max-public-methods
class_name CrewState
extends RefCounted
## The client's model of everything that isn't a snapshot (#7): pick, catalogue, lobby,
## Start, claims, pause and abandon votes, alert level, marks, pings and the selection
## every panel of this client shares. Built from Welcome, the Catalogue and the event
## stream (docs/protocol.md "Events"); pure, time passed in. Panels read it and listen to
## `changed`; they never write it except through select() and the intents they send.

## What changed: &"picked", &"catalogue", &"lobby", &"started", &"claims", &"pause",
## &"votes", &"abandoned", &"alert", &"marks", &"pings", &"selection", &"reset",
## &"run_over" (the outcome card and its "Run again" votes, D178), and from Relay's events
## &"sites", &"zones", &"routes", &"inbox", &"relay_log"; &"main_view" (strand F).
signal changed(what: StringName)
## A toast to show: translation key and format arguments (I18n strings).
signal toast(key: String, args: Dictionary)
## A new (not copy) ping arrived: the chime seam (FT-SPA-016; the alerts strand plays it).
signal pinged(ping: Dictionary)
## An event this model doesn't keep (sim events: hit, fault, ...): StationAlerts' seam.
signal sim_event(kind: StringName, payload: Dictionary)

## Marks per ship, named by slot (FT-SPA-012): the server's rules (CrewMarks).
const MARK_NAMES: Array[String] = CrewMarks.DEFAULT_NAMES
const MAX_MARKS: int = CrewMarks.SLOTS
## A ping pulses its item this long on every screen (FT-SPA-016).
const PING_MS: int = 3000
## A Captain's ping on a card shows it on the main screen this long, or until the next
## ping (FT-CPT-005).
const CARD_MS: int = 10000
## Alert levels (D170): Normal, Yellow, Red.
const ALERT_NORMAL: int = CrewMarks.ALERT_NORMAL
const ALERT_YELLOW: int = CrewMarks.ALERT_YELLOW
const ALERT_RED: int = CrewMarks.ALERT_RED
const ALERT_LEVELS: int = CrewMarks.ALERT_RED + 1
## Most log entries kept (the server keeps CrewRelay.MAX_LOG).
const MAX_LOG: int = CrewRelay.MAX_LOG
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
## ship -> {"voters": [names], "sessions": [ids], "needed": int}.
var votes: Dictionary = {}
## ship -> "vote" | "host".
var abandoned: Dictionary = {}
## ship -> `run_over` payload {ship, outcome, time_s, hull} plus "voters", "sessions" and
## "needed" from `run_votes`, from the outcome until the reset (D178).
var run_over: Dictionary = {}
## item -> {"session": int, "name": String} (claim events; free items erased).
var claims: Dictionary = {}
var alert: int = ALERT_NORMAL
var alert_by: String = ""
## Sorted by slot: {"slot", "name", "contact", "site", "pos" (Vector3, m), "by"}.
var marks: Array[Dictionary] = []
## Active pings, oldest first: {"kind", "id", "site", "pos", "by", "at_ms", "copies"}.
var pings: Array[Dictionary] = []
## The main screen's view (MainScreen.View), set by the Captain or by Relay.
var main_view: int = MainScreen.View.FORWARD
var main_view_by: String = ""
## The Comms card the latest ping named: {"id", "by", "at_ms"}, or {} when a later ping
## named something else. Not in `pings`: it pulses nothing on the radar.
var card_ping: Dictionary = {}
## The shared selection: {"kind": "contact" | "mark" | "site" | "zone", "id": int}, or {}.
var selection: Dictionary = {}
## The scenario's site names, the callout layer every station shows (FT-SPA-027): [{"site",
## "name"}].
var sites: Array[Dictionary] = []
## Hazard zones and scan positions, outside the 8 marks (FT-SPA-028): {"id", "kind"
## ("hazard" | "scan"), "site", "pos" (Vector3, m), "radius" (m), "by"}.
var zones: Array[Dictionary] = []
## Relay's routes (FT-RLY-005), by route number: Array of {"site", "pos"} waypoints.
var routes: Array = []
## Relay only: marks other ships sent, waiting for Accept or Decline (FT-RLY-009): {"id",
## "from_ship", "from", "name", "site", "pos"}; and the ship's log (FT-RLY-006): {"tick",
## "key", "args"}, oldest first.
var inbox: Array[Dictionary] = []
var relay_log: Array[Dictionary] = []


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
			votes[int(p["ship"])] = p
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
		"main_view":
			_on_main_view(p)
		"marks":
			_on_marks(p)
		"ping":
			_on_ping(p, now_ms)
		"sites", "zones", "routes", "inbox", "relay_log":
			_on_relay(str(e["type"]), p)
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


## True when the shared selection is this item.
func is_selected(kind: String, id: int) -> bool:
	return selection.get("kind", "") == kind and int(selection.get("id", -1)) == id


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


## The names of the stations that copied the newest live ping on an item, silently
## (FT-SPA-031); [] when it has none.
func copies(kind: String, id: int, now_ms: int) -> Array:
	_expire(now_ms)
	for i: int in range(pings.size() - 1, -1, -1):
		if pings[i]["kind"] == kind and pings[i]["id"] == id:
			return (pings[i]["copies"] as Array).duplicate()
	return []


## Pings still pulsing at now_ms (point pings included).
func live_pings(now_ms: int) -> Array[Dictionary]:
	_expire(now_ms)
	return pings.duplicate()


## The name of a site, "" when the scenario gives none (FT-SPA-027).
func site_name(site: int) -> String:
	for d: Dictionary in sites:
		if d["site"] == site:
			return d["name"]
	return ""


func zone_by_id(id: int) -> Dictionary:
	for z: Dictionary in zones:
		if z["id"] == id:
			return z
	return {}


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
	zones.clear()
	routes.clear()
	inbox.clear()
	relay_log.clear()
	selection = {}
	card_ping = {}
	main_view = MainScreen.View.FORWARD
	main_view_by = ""
	alert = ALERT_NORMAL
	alert_by = ""
	started.erase(ship)
	abandoned.erase(ship)
	run_over.erase(ship)
	changed.emit(&"reset")


## The Relay and callout-layer events (docs/protocol.md "Relay").
func _on_relay(type: String, p: Dictionary) -> void:
	if type != "sites" and not _mine(p):
		return
	match type:
		"sites":
			sites.clear()
			for d: Dictionary in p.get("sites", []):
				sites.append({"site": int(d["site"]), "name": str(d["name"])})
		"zones":
			zones.clear()
			for z: Dictionary in p.get("zones", []):
				(
					zones
					. append(
						{
							"id": int(z["id"]),
							"kind": str(z["kind"]),
							"site": int(z["site"]),
							"pos": Vector3(float(z["x"]), float(z["y"]), float(z["z"])),
							"radius": float(z["radius"]),
							"by": str(z.get("by", "")),
						}
					)
				)
			if selection.get("kind", "") == "zone" and zone_by_id(selection["id"]).is_empty():
				selection = {}
				changed.emit(&"selection")
		"routes":
			routes.clear()
			for route: Array in p.get("routes", []):
				var points: Array = []
				for w: Dictionary in route:
					(
						points
						. append(
							{
								"site": int(w["site"]),
								"pos": Vector3(float(w["x"]), float(w["y"]), float(w["z"])),
							}
						)
					)
				routes.append(points)
		"inbox":
			inbox.clear()
			for m: Dictionary in p.get("items", []):
				(
					inbox
					. append(
						{
							"id": int(m["id"]),
							"from_ship": int(m["from_ship"]),
							"from": str(m["from"]),
							"name": str(m["name"]),
							"site": int(m["site"]),
							"pos": Vector3(float(m["x"]), float(m["y"]), float(m["z"])),
						}
					)
				)
		_:
			if bool(p.get("replace", false)):
				relay_log.clear()
			for entry: Dictionary in p.get("entries", []):
				relay_log.append(entry)
			while relay_log.size() > MAX_LOG:
				relay_log.pop_front()
	changed.emit(StringName(type))


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


func _on_main_view(p: Dictionary) -> void:
	if not _mine(p):
		return
	main_view = clampi(int(p.get("view", 0)), 0, MainScreen.NAMES.size() - 1)
	main_view_by = str(p.get("by", ""))
	changed.emit(&"main_view")


## Whether this ship has a Captain pick (connected or in grace), from the lobby event.
func captain_seated(id: int = ship) -> bool:
	return str(lobby.get(id, {}).get("captain", "")) != ""


## Whether this pick may switch the main screen now (FT-MSC-005): the Captain, or Relay
## while no Captain is seated. The server decides; this only hides dead buttons.
func may_switch_main_view() -> bool:
	if entry == StationViews.CAPTAIN:
		return true
	return stations().has("relay") and not captain_seated()


## The Comms card the main screen shows at now_ms (FT-CPT-005), or -1.
func shown_card(now_ms: int) -> int:
	if card_ping.is_empty() or now_ms - int(card_ping["at_ms"]) >= CARD_MS:
		return -1
	return int(card_ping["id"])


func _on_marks(p: Dictionary) -> void:
	if not _mine(p):
		return
	marks.clear()
	for m: Dictionary in p.get("marks", []):
		(
			marks
			. append(
				{
					"slot": int(m.get("slot", 0)),
					"name": str(m.get("name", "")),
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
	# A site ping names its site in `site` (docs/protocol.md); pulse() looks it up by id.
	var id: int = int(p.get("site" if kind == "site" else "id", -1))
	# `copy` is the first pinger's name, "" for an original (docs/protocol.md).
	var copy: bool = str(p.get("copy", "")) != ""
	if kind == "card":
		card_ping = {"id": int(p.get("id", -1)), "by": str(p.get("by", "")), "at_ms": now_ms}
		changed.emit(&"card")
		if not copy:
			pinged.emit(card_ping)
		return
	if not copy and not card_ping.is_empty():
		card_ping = {}
		changed.emit(&"card")
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
