class_name EventRouting
extends RefCounted
## Which sessions a sim event reaches and with what value (F4, R13-8; FT-NET-009, D224): the
## server's event tables, apart from the station model (StationCatalogue) the clients read.
## NetGame.event_audience and ServerVoice use them.

## Sim events that only some stations get (FT-NET-009): kind -> stations; a session
## gets one if its pick covers a listed station. Kinds not listed go to every session
## of the event's faction (alerts and toasts for all). ai_mode is the AI's own.
const EVENT_STATIONS: Dictionary = {
	&"repair_started": ["engineering"],
	&"repair_finished": ["engineering"],
	&"repair_no_parts": ["engineering"],
	&"repair_recalled": ["engineering"],
	&"fire_blocked": ["weapons"],
	&"friendly_fire_warning": ["weapons"],
	&"mount_overheated": ["weapons", "engineering"],
	&"mount_cooled": ["weapons", "engineering"],
	&"guidance_lost": ["weapons"],
	&"weak_point_hit": ["weapons"],
	# Exact-value events (EXACT_EVENTS, D224): Engineering's, or a plain alert elsewhere.
	&"subsystem_damaged": ["engineering"],
	&"subsystem_destroyed": ["engineering"],
	&"shield_low": ["helm", "engineering"],
	&"fault_inflicted": ["engineering"],
	&"fault_cause_revealed": ["engineering"],
	&"fault_cause_picked": ["engineering"],
	&"fault_cleared": ["engineering"],
	&"hardened": ["engineering"],
	&"harden_expired": ["engineering"],
	&"harden_no_parts": ["engineering"],
	&"ai_mode": [],
	&"science_refused": ["science"],
	# Server-only (NetCoop's probe-scan stat, R02-7): no client reads them.
	&"scan_started": [],
	&"scan_done": ["science"],
	&"scan_failed": ["science"],
	&"scan_mark": ["science", "helm"],
	&"hack_started": [],
	&"hack_traced": ["science"],
	&"hack_failed": ["science"],
	&"hack_done": ["science", "weapons"],
	&"self_scan_done": ["science", "engineering"],
	# Relay's probes and lanes; fabrication also tells Engineering.
	&"probe_launched": ["relay"],
	&"probe_deployed": ["relay"],
	&"probe_no_stock": ["relay"],
	&"probe_fabricating": ["relay", "engineering"],
	&"probe_fabricated": ["relay", "engineering"],
	&"probe_no_parts": ["engineering"],
	&"lane_warning": ["weapons", "relay"],
	&"decoy_launched": ["relay"],
	&"decoy_spent": ["relay"],
	# Comms' pairs: a lane's dock, a surrender, a scan-unlocked reply, a
	# marked mission. None carries Engineering's data (FT-PAIR-010).
	&"dock_cleared": ["helm", "comms"],
	&"dock_uncleared": ["helm", "comms"],
	&"surrender_roll": ["comms"],
	&"surrender_killed": ["weapons", "comms"],
	&"scan_option": ["science", "comms"],
	&"mission_marked": ["relay", "comms"],
}

## Events whose `value` is Engineering's exact data (a health fraction, a heat, the shield
## fraction), D224: a view without Engineering gets the value as its summaries toggle says
## (exact, banded or 0), and a Comms view without Engineering gets the event not at all.
## Fault and shield_low double as plain alerts on the stations that depend on them.
const EXACT_EVENTS: Array[StringName] = [
	&"subsystem_damaged", &"subsystem_destroyed", &"fault", &"shield_low"
]

## Events that are a data shortcut when they leave the station that produced them: kind ->
## [toggle, source station]. The source's own sessions always get them; another station
## gets one when the toggle is on or it is in a joint view with the source (ShortcutFilter.grants,
## FT-PAIR-008). Hack windows and weak-point hits are Science's work shown on Weapons (P7),
## own-ship scan results Science's shown on Engineering (P10), flagged lanes Relay's shown
## on Weapons (P8). Scan-position marks are MARK items and reach Helm at every difficulty.
const EVENT_SHORTCUTS: Dictionary = {
	&"hack_done": [&"weak_points", "science"],
	&"self_scan_done": [&"diagnosed_causes", "science"],
	&"fault_cause_revealed": [&"diagnosed_causes", "science"],
	&"lane_warning": [&"track_feeds", "relay"],
}


## Whether a sim event of this kind reaches a session holding seat (faction and ship
## checks are NetGame.event_audience()'s).
static func sees_event(
	seat: String, kind: StringName, toggles: String = StationCatalogue.DEFAULT_TOGGLES
) -> bool:
	if EXACT_EVENTS.has(kind):
		var seen: ShortcutFilter = ShortcutFilter.of(seat, toggles)
		if seen != null and seen.condition_hidden:
			return false
	if CommsSection.EVENTS.has(kind):  # Comms' own events
		return StationCatalogue.stations_of(seat).has("comms")
	if not EVENT_STATIONS.has(kind):
		return true
	var shortcut: Array = EVENT_SHORTCUTS.get(kind, [])
	var filter: ShortcutFilter = null
	for station: String in StationCatalogue.stations_of(seat):
		if not (EVENT_STATIONS[kind] as Array).has(station):
			continue
		if shortcut.is_empty() or station == shortcut[1]:
			return true
		if filter == null:
			filter = ShortcutFilter.of(seat, toggles)
		if filter != null and filter.grants(shortcut[0]):
			return true
	return false


## The `value` of a sim event as a seat's view may carry it: an EXACT_EVENTS value as the
## summaries toggle says (exact for Engineering and at the exact setting, the middle of its
## D193 band, else 0; a fault's heat is Engineering's alone); any other event's value as it
## is (D224).
static func event_value(
	seat: String, kind: StringName, value: float, toggles: String = StationCatalogue.DEFAULT_TOGGLES
) -> float:
	if not EXACT_EVENTS.has(kind):
		return value
	var filter: ShortcutFilter = ShortcutFilter.of(seat, toggles)
	if filter == null:
		return 0.0
	# A fault's heat is no summary at any setting: Engineering's alone.
	if kind == &"fault":
		return value if filter.sees_all or filter.stations.has("engineering") else 0.0
	return filter.summarise(value, 1.0, ShortcutFilter.ENG)
