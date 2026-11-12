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
## &"ship_outcome" (the outcome card and its "Run again" votes, D178), and from Relay's events
## &"zones", &"routes", &"inbox", &"relay_log"; &"main_view"; &"priority";
## &"toggles" when the session's data-shortcut set changed, &"shares" when a
## shortcut was shared or ran out, &"lanes" when the approach lanes changed (F); and from
## the multi-ship events (#11) &"fleet", &"scoreboard", &"eliminated", &"relaunch" (votes
## or a relaunch), &"handover" and &"game_over"; &"gap" when the quiet gap or its Ready
## count changed (gp-07).
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
## Most log entries kept (the server keeps NetProtocol.RELAY_LOG_MAX).
const MAX_LOG: int = NetProtocol.RELAY_LOG_MAX
## Sim ticks per second (spec: 60 Hz), for the mission timer.
const TICK_HZ: float = SimRate.HZ * 1.0

var session: int = -1
var ship: int = -1
var seat: String = ""
var host: bool = false
var dev_all: bool = false
var lang: String = "en"
## Catalogue message fields: ships [{id, def, name, faction}], seats [SeatDef
## dicts], load_tags.
var catalogue: Dictionary = {}
## ship -> `lobby` payload.
var lobby: Dictionary = {}
## ship -> Start tick.
var started: Dictionary = {}
## ship -> `pause` payload, while paused.
var paused: Dictionary = {}
## The host paused the universe (FT-MIS-040); independent of `paused`.
var host_paused: bool = false
## ship -> {"voters": [names], "sessions": [ids], "needed": int}.
var votes: Dictionary = {}
## ship -> "vote" | "host".
var abandoned: Dictionary = {}
## ship -> `ship_outcome` payload {ship, outcome, time, hull} plus "voters", "sessions" and
## "needed" from `run_votes`, from the outcome until the reset (D178).
var ship_outcome: Dictionary = {}
## ship -> its debrief record (RunDebrief.for_ship), sent right after `ship_outcome`.
var debrief: Dictionary = {}
## item -> {"session": int, "name": String} (claim events; free items erased).
var claims: Dictionary = {}
var alert: int = ALERT_NORMAL
var alert_by: String = ""
## Sorted by slot: {"slot", "name", "contact", "pos" (Vector3, m), "by"}.
var marks: Array[Dictionary] = []
## Pings still showing, oldest first: {"kind", "id", "pos", "by", "at_ms", "copies"}.
var pings: Array[Dictionary] = []
## The main screen's view (MainScreen.View), set by the Captain or by Relay.
var main_view: int = MainScreen.View.FORWARD
var main_view_by: String = ""
## The Captain's priority target (gp-15): a contact id, -1 for none.
var priority: int = -1
## The Comms card the latest ping named: {"id", "by", "at_ms", "card" (the ping's copy of
## its kind, title, detail and expires, for the main screen)}, or {} when a later ping
## named something else. Not in `pings`: it pulses nothing on the radar.
var card_ping: Dictionary = {}
## The shared selection: {"kind": "contact" | "mark" | "site" | "zone", "id": int}, or {}.
var selection: Dictionary = {}
## Hazard zones and scan positions, outside the 8 marks (FT-SPA-028): {"id", "kind"
## ("hazard" | "scan"), "pos" (Vector3, m), "radius" (m), "by"}.
var zones: Array[Dictionary] = []
## Relay's routes (FT-RLY-005), by route number: Array of {"pos"} waypoints.
var routes: Array = []
## Relay only: marks other ships sent, waiting for Accept or Decline (FT-RLY-009): {"id",
## "from_ship", "from", "name", "pos"}; and the ship's log (FT-RLY-006): {"tick",
## "key", "args"}, oldest first.
var inbox: Array[Dictionary] = []
var relay_log: Array[Dictionary] = []
## The session's data-shortcut toggles, from the `lobby` events (every ship shares them,
## FT-PAIR-017); Easy until the server says otherwise.
var toggles: DataToggles = DataToggles.of_preset(StationCatalogue.DEFAULT_TOGGLES)

## The shortcuts shared to this ship (the `shares` event, D210): feature -> client clock (ms)
## at which the share ends.
var shares: Dictionary = {}
## The ship's approach lanes (P5, the `lanes` event): {"card", "pos" (Vector3, m), "opens_ms",
## "closes_ms" (client clock, ms), "by"}. Only while the lanes toggle lets them reach this
## station (Comms always, the others once Comms shared them).
var lanes: Array[Dictionary] = []

## Multi-ship games (#11, docs/protocol.md "Multi-ship games and PvP"). The `fleet`
## payload: the lobby's ships, the host's mode and options, the ships still to press Start;
## {} until the server sends one (then the catalogue's ships are the lobby).
var fleet: Dictionary = {}
## The live scoreboard's rows (M4-Q9): status and progress only.
var scoreboard: Array = []
## ship -> `eliminated` payload {ship, reason, lives}, until it is relaunched.
var eliminated: Dictionary = {}
## ship -> `relaunch_votes` payload {ship, voters, sessions, needed}.
var relaunch_votes: Dictionary = {}
## This session's latest `handover` {ship (its eliminated ship), to_ship (-1 the
## scoreboard)}, {} when it was never handed over or its ship was relaunched.
var handover: Dictionary = {}
## The `game_over` payload, {} while the session goes on.
var game_over: Dictionary = {}
## The fleet's quiet gap (NetSkipGap, gp-07): {faction, ends_at, ready, voters}, {} outside one.
var gap: Dictionary = {}

var _filter: ShortcutFilter = null
var _filter_key: String = ""


## What this pick may see of other stations' data at the session's toggles (ShortcutFilter): the
## clients draw an em dash for an absent summary, a band for a banded one.
func filter() -> ShortcutFilter:
	var code: String = ShortcutFilter.code_with(toggles.encode(), shares.keys())
	var key: String = "%s|%s" % [seat, code]
	if _filter == null or key != _filter_key:
		_filter_key = key
		_filter = ShortcutFilter.of(seat, code)
	return _filter


## Seconds left of a shared shortcut, 0 when it isn't shared.
func share_left(feature: StringName, now_ms: int) -> float:
	return (
		maxf(0.0, (int(shares.get(feature, 0)) - now_ms) / 1000.0) if shares.has(feature) else 0.0
	)


## Every share's seconds left at `now_ms`: {feature: seconds}.
func shares_left(now_ms: int) -> Dictionary:
	var left: Dictionary = {}
	for id: StringName in shares:
		left[id] = share_left(id, now_ms)
	return left


## How the top bar shows the STATUS values that are another station's data at the session's
## toggles (FT-PAIR-019, D193): {key: {"text": word or dash, "band": HealthBand.Band or -1}}
## for the keys that aren't exact numbers; the keys whose numbers show stay out. `def` is the
## own ship's definition (the bands are shares of its maxima), null without one.
func summaries(status: Dictionary, def: ShipDef) -> Dictionary:
	var f: ShortcutFilter = filter()
	var out: Dictionary = {}
	if f == null or f.sees_all or def == null or status.is_empty():
		return out
	var maxima: Dictionary = {
		"hull": def.hull_max,
		"shields": def.shields.max_strength,
		"pips_used": float(status.get("pip_cap", def.power.reactor_pips)),
	}
	for key: String in maxima:
		# The hull is the ship's: exact unless the view holds Comms without Engineering,
		# when it is the band at every difficulty (FT-PAIR-010).
		var mode: int = f.summary_mode(ShortcutFilter.ENG)
		if key == "hull":
			mode = 1 if f.condition_hidden else 2
		if mode == 1:
			var share: float = float(status.get(key, 0.0)) / maxima[key]
			var band: HealthBand.Band = HealthBand.band_of(share, DataToggles.def().band_edges)
			var word: String = TranslationServer.translate("band." + HealthBand.word(band))
			out[key] = {"text": word, "band": band}
		elif mode == 0:
			out[key] = {"text": TranslationServer.translate("topbar.absent"), "band": -1}
	return out


## Takes the Welcome fields (NetClient.welcome).
func welcome(w: Dictionary) -> void:
	session = int(w.get("session", -1))
	ship = int(w.get("ship", -1))
	seat = str(w.get("seat", ""))
	host = bool(w.get("host", false))
	dev_all = bool(w.get("dev_all", false))
	lang = str(w.get("lang", "en"))
	changed.emit(&"picked")


func set_catalogue(c: Dictionary) -> void:
	catalogue = c
	changed.emit(&"catalogue")


## The SeatDef dict of the current pick, or {}.
func seat_def() -> Dictionary:
	return def_of(seat)


func def_of(id: String) -> Dictionary:
	for d: Dictionary in catalogue.get("seats", []):
		if d.get("id", "") == id:
			return d
	return {}


## Functional stations of the pick (one, two for a joint view, six for the dev seat).
func stations() -> Array:
	return seat_def().get("stations", [])


## Crew picks set the alert level and place marks; Captain and viewers can't set the
## alert (FT-STN-008).
func is_crew() -> bool:
	return bool(seat_def().get("crew", false))


## Co-op: the host's mode once the server sends `fleet`; before that, every crew ship
## sharing one faction (a client-side view of the server's rule, which also checks
## relations). PvP sessions have no pause control (FT-MIS-040).
func is_coop() -> bool:
	if not fleet.is_empty():
		return mode() == "coop"
	var factions: Dictionary = {}
	for s: Dictionary in catalogue.get("ships", []):
		factions[int(s.get("faction", 0))] = true
	return factions.size() <= 1


## Whether the menu offers the host pause.
func can_host_pause() -> bool:
	return host and is_coop()


## The menu's abandon-run control (D241, FT-MIS-016): "" none (not started, run over,
## out of play, not crew), else the string key of its label. In PvP it is the give-up
## (forfeit) vote, by the same majority (M4-Q10).
func abandon_control() -> String:
	if not started.has(ship) or ship_outcome.has(ship) or abandoned.has(ship):
		return ""
	if eliminated.has(ship) or not game_over.is_empty():
		return ""
	var kind: String = "abandon" if is_coop() else "forfeit"
	if host:
		return "settings." + kind
	if not is_crew():
		return ""
	return "settings.%s_%s" % [kind, "unvote" if has_abandon_vote() else "vote"]


## Whether this session's abandon vote for its ship stands.
func has_abandon_vote() -> bool:
	return session in votes.get(ship, {}).get("sessions", [])


func ship_name(id: int = ship) -> String:
	for s: Dictionary in catalogue.get("ships", []):
		if int(s.get("id", -2)) == id:
			return str(s.get("name", ""))
	return str(fleet_row(id).get("name", ""))


## Whether the ship's run is under way; with `fleet`, only once the universe has started
## (all ships together, M4-Q4).
func is_started(id: int = ship) -> bool:
	if not fleet.is_empty() and not bool(fleet.get("started", false)):
		return false
	return started.has(id) or bool(lobby.get(id, {}).get("started", false))


# --- Multi-ship games (#11). ---


## The host's mode (GameRules.MODE_NAMES): "coop" until `fleet` says otherwise, or
## "race" for a lobby of several crew factions with no `fleet`.
func mode() -> String:
	if fleet.is_empty():
		return "coop" if is_coop() else "race"
	return str(fleet.get("mode", "coop"))


func is_pvp() -> bool:
	return not is_coop()


## TEAMS and HOLDOUT put ships on team 0 or 1 (M4-Q6).
func has_teams() -> bool:
	return mode() in ["teams", "holdout"]


## The lobby's ships, each {ship, name, team, seats, crew, uncovered, ready, started}: the
## `fleet` rows, or the catalogue's ships (team 0) before any.
func fleet_ships() -> Array:
	if not fleet.is_empty():
		return fleet.get("ships", [])
	var out: Array = []
	for s: Dictionary in catalogue.get("ships", []):
		out.append({"ship": int(s.get("id", -1)), "name": str(s.get("name", "")), "team": 0})
	return out


## The ship's `fleet` row, {} when there is none.
func fleet_row(id: int) -> Dictionary:
	for row: Dictionary in fleet.get("ships", []):
		if int(row.get("ship", -2)) == id:
			return row
	return {}


func team_of(id: int) -> int:
	return int(fleet_row(id).get("team", 0))


## Whether two ships are on the same side: every ship in co-op, the same team in TEAMS and
## HOLDOUT, only itself in RACE and LAST_STANDING (GameRules.faction_for).
func allied(a: int, b: int) -> bool:
	if a == b or is_coop():
		return true
	return has_teams() and team_of(a) == team_of(b)


## The lobby state of a ship: its `lobby` payload, else its `fleet` row (seats, crew,
## uncovered, ready, started); {} for neither.
func ship_state(id: int) -> Dictionary:
	if lobby.has(id):
		return lobby[id]
	return fleet_row(id)


## Whether a player may add a ship now (M4-Q3): the server sent `fleet`, the universe hasn't
## started and there is room.
func can_add_ship() -> bool:
	return (
		not fleet.is_empty()
		and not bool(fleet.get("started", false))
		and fleet_ships().size() < int(fleet.get("max_ships", 6))
	)


## Whether a host client is connected (the `fleet` event's `host`): without one any Ready crew
## player may Start (#37 C1).
func host_here() -> bool:
	return bool(fleet.get("host", true))


## Whether the universe has started (the `fleet` event), or without one this ship's lobby
## state says its run has.
func game_started() -> bool:
	if not fleet.is_empty():
		return bool(fleet.get("started", false))
	return bool(ship_state(ship).get("started", false))


## This session's Ready, from its seat row on its ship (#37 C1).
func is_ready() -> bool:
	for row: Variant in ship_state(ship).get("seats", []):
		if int((row as Dictionary).get("session", -1)) == session:
			return bool((row as Dictionary).get("ready", false))
	return false


## Whether the lobby offers this player Ready: a crew player other than the host (the host's
## Start is its Ready), before the game starts (#37 C1).
func offers_ready() -> bool:
	return is_crew() and not host and not game_started()


## Whether the lobby offers this player Start: the host, or with no host connected a Ready
## crew player, before the game starts (#37 C1, the no-host rule).
func offers_start() -> bool:
	if game_started():
		return false
	return host or (not host_here() and is_crew() and is_ready())


## The lobby's crewed ships (a crew pick on them), in lobby order.
func crewed_ships() -> Array[int]:
	var out: Array[int] = []
	for row: Dictionary in fleet_ships():
		var id: int = int(row["ship"])
		if int(ship_state(id).get("crew", 0)) > 0:
			out.append(id)
	return out


## The names of the crew players not Ready yet, on every crewed ship (#37 C1).
func unready_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for id: int in crewed_ships():
		for row: Variant in ship_state(id).get("seats", []):
			var r: Dictionary = row
			if (
				bool(def_of(str(r.get("seat", ""))).get("crew", false))
				and not r.get("ready", false)
			):
				names.append(str(r.get("name", "")))
	return names


## The ship this session crewed: the eliminated one after a handover, else its pick's.
func home_ship() -> int:
	return int(handover["ship"]) if not handover.is_empty() else ship


## Whether the session shows the scoreboard: handed over to it (no friendly ship left, D91),
## or a PvP session that is over.
func on_scoreboard() -> bool:
	if not handover.is_empty() and int(handover.get("to_ship", 0)) == FleetMessages.TO_SCOREBOARD:
		return true
	return is_pvp() and not game_over.is_empty()


## Relaunches left for the home ship's side after its elimination (-1 unlimited), 0 for
## none or when it isn't eliminated.
func lives_left() -> int:
	return int(eliminated.get(home_ship(), {}).get("lives", 0))


## Whether this session may vote to relaunch its eliminated ship (M4-Q2).
func can_relaunch() -> bool:
	return eliminated.has(home_ship()) and lives_left() != 0 and game_over.is_empty()


## Whether this session's relaunch vote for its home ship stands.
func has_relaunch_vote() -> bool:
	return session in relaunch_votes.get(home_ship(), {}).get("sessions", [])


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
		NetProtocol.EVENT_PICKED:
			return _on_picked(p)
		NetProtocol.EVENT_LOBBY:
			_on_lobby(p)
		NetProtocol.EVENT_STARTED:
			started[int(p["ship"])] = int(p.get("tick", 0))
			changed.emit(&"started")
		NetProtocol.EVENT_CLAIM:
			_on_claim(p)
		NetProtocol.EVENT_PAUSE:
			if p.get("host", false):
				host_paused = true
			else:
				paused[int(p["ship"])] = p
			changed.emit(&"pause")
		NetProtocol.EVENT_RESUME:
			# Each pause that lifts has its own resume; clear only the one it names.
			if p.get("host", false):
				host_paused = false
			else:
				paused.clear()
				votes.clear()
			changed.emit(&"pause")
		NetProtocol.EVENT_ABANDON_VOTES:
			votes[int(p["ship"])] = p
			changed.emit(&"votes")
		NetProtocol.EVENT_ABANDONED:
			abandoned[int(p["ship"])] = str(p.get("by", ""))
			changed.emit(&"abandoned")
		NetProtocol.EVENT_SHIP_OUTCOME, NetProtocol.EVENT_RUN_VOTES:
			var card: Dictionary = ship_outcome.get_or_add(int(p["ship"]), {})
			card.merge(p, true)
			changed.emit(&"ship_outcome")
		NetProtocol.EVENT_DEBRIEF:
			debrief[int(p["ship"])] = p
			changed.emit(&"debrief")
		NetProtocol.EVENT_ALERT:
			_on_alert(p)
		NetProtocol.EVENT_MAIN_VIEW:
			_on_main_view(p)
		NetProtocol.EVENT_PRIORITY:
			_on_priority(p)
		NetProtocol.EVENT_MARKS:
			_on_marks(p)
		NetProtocol.EVENT_PING:
			_on_ping(p, now_ms)
		NetProtocol.EVENT_ZONES, NetProtocol.EVENT_ROUTES:
			_on_relay(str(e["type"]), p)
		NetProtocol.EVENT_INBOX, NetProtocol.EVENT_RELAY_LOG:
			_on_relay(str(e["type"]), p)
		NetProtocol.EVENT_CHIP_ANSWER:
			_on_chip_answer(p)
		NetProtocol.EVENT_LANES:
			if _mine(p):
				lanes.clear()
				for l: Dictionary in p.get("lanes", []):
					(
						lanes
						. append(
							{
								"card": int(l["card"]),
								"pos": Vector3(float(l["x"]), float(l["y"]), float(l["z"])),
								"opens_ms": now_ms + roundi(float(l["opens_in"]) * 1000.0),
								"closes_ms": now_ms + roundi(float(l["closes_in"]) * 1000.0),
								"by": str(l.get("by", "")),
							}
						)
					)
				changed.emit(&"lanes")
		NetProtocol.EVENT_SHARES:
			if _mine(p):
				shares.clear()
				for id: String in p.get("left", {}):
					shares[StringName(id)] = now_ms + roundi(float(p["left"][id]) * 1000.0)
				changed.emit(&"shares")
		NetProtocol.EVENT_FLEET, NetProtocol.EVENT_SCOREBOARD, NetProtocol.EVENT_ELIMINATED:
			_on_fleet_event(str(e["type"]), p)
		NetProtocol.EVENT_RELAUNCH_VOTES, NetProtocol.EVENT_RELAUNCHED, NetProtocol.EVENT_HANDOVER:
			_on_fleet_event(str(e["type"]), p)
		NetProtocol.EVENT_GAME_OVER:
			game_over = p
			changed.emit(&"game_over")
		NetProtocol.EVENT_GAP:
			gap = p if int(p.get("ends_at", 0)) > 0 else {}
			changed.emit(&"gap")
		NetProtocol.EVENT_TAKEOVER:
			_on_takeover(p)
		NetProtocol.EVENT_REQUEST_REJECTED, NetProtocol.EVENT_COMMAND_REJECTED:
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
	shares.clear()
	lanes.clear()
	inbox.clear()
	relay_log.clear()
	selection = {}
	card_ping = {}
	main_view = MainScreen.View.FORWARD
	main_view_by = ""
	priority = -1
	alert = ALERT_NORMAL
	alert_by = ""
	started.erase(ship)
	abandoned.erase(ship)
	ship_outcome.erase(ship)
	debrief.erase(ship)
	gap = {}
	changed.emit(&"reset")


## Whether this session votes on the quiet gap now (gp-07), and whether it is Ready.
func votes_on_gap() -> bool:
	return _lists(gap.get("voters", []), session)


func gap_ready() -> bool:
	return _lists(gap.get("ready", []), session)


static func _lists(ids: Variant, id: int) -> bool:
	for v: Variant in ids:
		if int(v) == id:
			return true
	return false


## The multi-ship events that only update the model (FleetMessages).
func _on_fleet_event(type: String, p: Dictionary) -> void:
	match type:
		NetProtocol.EVENT_FLEET:
			fleet = p
			changed.emit(&"fleet")
		NetProtocol.EVENT_SCOREBOARD:
			scoreboard = p.get("rows", [])
			changed.emit(&"scoreboard")
		NetProtocol.EVENT_ELIMINATED:
			eliminated[int(p["ship"])] = p
			changed.emit(&"eliminated")
		NetProtocol.EVENT_RELAUNCH_VOTES:
			relaunch_votes[int(p["ship"])] = p
			changed.emit(&"relaunch")
		NetProtocol.EVENT_RELAUNCHED:
			var id: int = int(p["ship"])
			eliminated.erase(id)
			relaunch_votes.erase(id)
			if home_ship() == id:
				handover = {}
			changed.emit(&"relaunch")
		NetProtocol.EVENT_HANDOVER:
			handover = p
			changed.emit(&"handover")


## A seat of an allied ship was taken over in its pause (M4-Q8): a toast naming who took
## what; the ship's side sees it.
func _on_takeover(p: Dictionary) -> void:
	var args: Dictionary = {
		"by": str(p.get("by", "")),
		"seat": TranslationServer.translate("seat." + str(p.get("seat", ""))),
		"ship": ship_name(int(p.get("ship", -1))),
	}
	toast.emit("toast.takeover", args)
	changed.emit(&"takeover")


## The Relay events (docs/protocol.md "Relay").
func _on_relay(type: String, p: Dictionary) -> void:
	if not _mine(p):
		return
	match type:
		NetProtocol.EVENT_ZONES:
			zones.clear()
			for z: Dictionary in p.get("zones", []):
				(
					zones
					. append(
						{
							"id": int(z["id"]),
							"kind": str(z["kind"]),
							"pos": Vector3(float(z["x"]), float(z["y"]), float(z["z"])),
							"radius": float(z["radius"]),
							"by": str(z.get("by", "")),
						}
					)
				)
			# Probe bubbles and sim hazards (ids below 0) are not in this list: only a
			# marked zone that is gone clears the selection (D222).
			if (
				selection.get("kind", "") == "zone"
				and int(selection["id"]) >= 0
				and zone_by_id(selection["id"]).is_empty()
			):
				selection = {}
				changed.emit(&"selection")
		NetProtocol.EVENT_ROUTES:
			routes.clear()
			for route: Array in p.get("routes", []):
				var points: Array = []
				for w: Dictionary in route:
					(
						points
						. append(
							{
								"pos": Vector3(float(w["x"]), float(w["y"]), float(w["z"])),
							}
						)
					)
				routes.append(points)
		NetProtocol.EVENT_INBOX:
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
	seat = str(p.get("seat", ""))
	claims.clear()
	changed.emit(&"picked")
	return true


func _on_lobby(p: Dictionary) -> void:
	var id: int = int(p["ship"])
	var was_started: bool = bool(lobby.get(id, {}).get("started", false))
	lobby[id] = p
	var code: String = str(p.get("toggles", toggles.encode()))
	var parsed: DataToggles = DataToggles.parse(code)
	if parsed != null and code != toggles.encode():
		toggles = parsed
		changed.emit(&"toggles")
	changed.emit(&"lobby")
	# The server resets a finished run: the ship is back in the lobby (FT-M1-012).
	if id == ship and was_started and not bool(p.get("started", false)):
		reset_run()


## A request chip this client sent was answered: a toast naming who and what.
func _on_chip_answer(p: Dictionary) -> void:
	var chip: Dictionary = {"chip": str(p.get("chip", "")), "arg": int(p.get("arg", -1))}
	var args: Dictionary = {"by": str(p.get("by", "")), "chip": ChipsReader.label(chip)}
	toast.emit(
		"toast.chip_answered" if bool(p.get("accept", false)) else "toast.chip_declined", args
	)


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


## A new priority target shows as a toast on Helm and Weapons, where its ring is drawn;
## a clear (-1) or an unchanged one says nothing.
func _on_priority(p: Dictionary) -> void:
	if not _mine(p):
		return
	var contact: int = int(p.get("contact", -1))
	if contact == priority:
		return
	priority = contact
	changed.emit(&"priority")
	if contact >= 0 and str(p.get("by", "")) != "":
		if stations().has("helm") or stations().has("weapons"):
			toast.emit("toast.priority", {"callsign": str(p.get("callsign", ""))})


## Whether this ship has a Captain pick (connected or in grace), from the lobby event.
func captain_seated(id: int = ship) -> bool:
	if lobby.has(id):
		return str(lobby[id].get("captain", "")) != ""
	for seat: Variant in fleet_row(id).get("seats", []):
		if str((seat as Dictionary).get("seat", "")) == StationCatalogue.CAPTAIN:
			return true
	return false


## Whether this pick may switch the main screen now (FT-MSC-005): the Captain, or Relay
## while no Captain is seated. The server decides; this only hides dead buttons.
func may_switch_main_view() -> bool:
	if seat == StationCatalogue.CAPTAIN:
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
	# A site ping names its named site in `id` (docs/protocol.md).
	var id: int = int(p.get("id", -1))
	# `copy` is the first pinger's name, "" for an original (docs/protocol.md).
	var copy: bool = str(p.get("copy", "")) != ""
	# A Viewer's ping names its pinger as one (gp-15): "Viewer Ana".
	var by: String = str(p.get("by", ""))
	if bool(p.get("viewer", false)):
		by = TranslationServer.translate("ping.by_viewer").format({"name": by})
	if kind == "card":
		card_ping = {
			"id": int(p.get("id", -1)),
			"by": str(p.get("by", "")),
			"at_ms": now_ms,
			"card": p.get("card", {}),
		}
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
				(old["copies"] as Array).append(by)
				changed.emit(&"pings")
				return
	var ping: Dictionary = {
		"kind": kind,
		"id": id,
		"pos": Vector3(float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0))),
		"by": by,
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
