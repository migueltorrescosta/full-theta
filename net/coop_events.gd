class_name CoopEvents
extends RefCounted
## The cooperative events of a session, counted per pair of stations (FT-PAIR-013, D35):
## a request chip sent and answered, a data shortcut shared, a mark one station placed and
## another used, a probe-enabled scan, and (with Comms, #10) a scan-unlocked dialogue
## option. Each one is counted here and written to the session log (SessionLog counters
## `coop.<pair>.<kind>` and one `coop` line per event), which the debrief of #10 shows.
## Pairs are the ids of spec §7.3, p1 to p15, in the order of StationViews.ENTRIES' joint
## views. An unanswered chip that expired is counted as `chip_expired` and is no
## cooperative event.

const CHIP_SENT: String = "chip_sent"
const CHIP_ANSWERED: String = "chip_answered"
const CHIP_DECLINED: String = "chip_declined"
const CHIP_EXPIRED: String = "chip_expired"
const SHORTCUT_SHARED: String = "shortcut_shared"
const MARK_USED: String = "mark_used"
const PROBE_SCAN: String = "probe_scan"
## A dialogue option a scan fact unlocked and Comms chose (P14, #10).
const SCAN_OPTION: String = "scan_option"
# --- strand F ---
## A debrief line, no cooperative event: Weapons destroyed a contact Comms had accepted the
## surrender of (P9, rep.destroy_surrendered); the fields name the victim and the change.
const SURRENDER_KILLED: String = "surrender_killed"
# --- end strand F ---
## The kinds that count as a cooperative event in the debrief.
const COOPERATIVE: Array[String] = [
	CHIP_ANSWERED, SHORTCUT_SHARED, MARK_USED, PROBE_SCAN, SCAN_OPTION
]

## "a|b" (stations in StationViews.CREW order) -> pair id, built once from the catalogue.
static var _pairs: Dictionary = _build_pairs()

## The session log, or null (counted, not written).
var session_log: SessionLog = null
## pair -> kind -> count.
var _counts: Dictionary = {}


## The pair id (p1 to p15) of two stations in either order, or "" for the same station or an
## unknown one.
static func pair_of(a: String, b: String) -> String:
	return _pairs.get(_pair_key(a, b), "")


## The two stations of a pair id, in CREW order; [] for an unknown id.
static func stations_of(pair: String) -> Array:
	for key: String in _pairs:
		if _pairs[key] == pair:
			return key.split("|")
	return []


## Counts one event of a kind for a pair on a ship and writes it to the log.
func record(kind: String, pair: String, ship: int, fields: Dictionary = {}) -> void:
	var by_kind: Dictionary = _counts.get_or_add(pair, {})
	by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	if session_log != null:
		session_log.count("coop.%s.%s" % [pair, kind])
		var line: Dictionary = {"coop": kind, "pair": pair, "ship": ship}
		line.merge(fields)
		session_log.event("coop", line)


# --- strand F ---
## The STORY events that are a pair's cooperative event or a debrief line (P5, P9, P14, P15):
## a scan-unlocked option chosen, a lane Comms placed that Helm docked by, a mission Relay
## marked, and a surrendered contact destroyed. NetCoop passes the sim events to it.
func on_story_event(e: SimEvent) -> void:
	match e.kind:
		&"scan_option":
			record(SCAN_OPTION, pair_of("science", "comms"), e.ship_id, {"fact": String(e.tag)})
		&"dock_cleared":
			record(MARK_USED, pair_of("helm", "comms"), e.ship_id, {"mark": "lane"})
		&"mission_marked":
			record(MARK_USED, pair_of("relay", "comms"), e.ship_id, {"mark": "mission"})
		&"surrender_killed":
			var fields: Dictionary = {"victim": e.other_id, "rep": snappedf(e.value, 0.1)}
			record(SURRENDER_KILLED, pair_of("weapons", "comms"), e.ship_id, fields)


# --- end strand F ---


## pair -> kind -> count since the session (or the last reset) began.
func counts() -> Dictionary:
	return _counts.duplicate(true)


## How many of a kind a pair has.
func count_of(pair: String, kind: String) -> int:
	return int(_counts.get(pair, {}).get(kind, 0))


## The cooperative events of a pair (the kinds in COOPERATIVE), for the debrief.
func cooperative(pair: String) -> int:
	var n: int = 0
	for kind: String in COOPERATIVE:
		n += count_of(pair, kind)
	return n


## The debrief's rows, one per pair with anything counted, in pair order: {pair, stations,
## events (the cooperative total), counts (kind -> n)}.
func debrief() -> Array:
	var out: Array = []
	for i: int in range(1, 16):
		var pair: String = "p%d" % i
		if _counts.has(pair):
			(
				out
				. append(
					{
						"pair": pair,
						"stations": stations_of(pair),
						"events": cooperative(pair),
						"counts": (_counts[pair] as Dictionary).duplicate(),
					}
				)
			)
	return out


func reset() -> void:
	_counts.clear()


static func _pair_key(a: String, b: String) -> String:
	var ia: int = StationViews.CREW.find(a)
	var ib: int = StationViews.CREW.find(b)
	if ia < 0 or ib < 0 or ia == ib:
		return ""
	return "%s|%s" % [a, b] if ia < ib else "%s|%s" % [b, a]


static func _build_pairs() -> Dictionary:
	var out: Dictionary = {}
	var n: int = 0
	for id: String in StationViews.ENTRIES:
		var st: Array = StationViews.ENTRIES[id][2]
		if st.size() == 2:
			n += 1
			out[_pair_key(st[0], st[1])] = "p%d" % n
	return out
