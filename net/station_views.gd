class_name StationViews
extends RefCounted
## The one data-driven place for catalogue entries (FT-ARC-014, FT-NET-008, FT-NET-040):
## the tables below define every StationDef (functional stations, the M1 joint views,
## Captain, Viewer and the dev entry), what each sees (snapshot sections and the field
## sets of the block sections), which crew commands it sends, its claimable items and
## ship-wide controls (FT-NET-022, FT-NET-044), and which sim events reach it. Joint
## views are the union of their stations (D20, FT-JNT-005). Field sets follow
## docs/spec/05-stations.md for what M1's sim has; adding a field is one line here.

## Section kinds (u8 on the wire). KIN, the block sections, NEAR, PROJECTILES and
## OWNERSHIP are per ship; CONTACTS is per faction.
enum Section {
	KIN = 1,
	STATUS = 2,
	HELM = 3,
	ENGINEERING = 4,
	MOUNTS = 5,
	CONTACTS = 6,
	NEAR = 7,
	PROJECTILES = 8,
	OWNERSHIP = 9,
	# Science contact card, scan and hack state.
	SCIENCE = 10,
	# Relay probes, coverage, routes, hazards and inbox.
	RELAY = 11,
	# Captain and main screen: main-screen view, open chips, cards.
	CAPTAIN = 12,
	# Open request chips of the ship.
	CHIPS = 13,
	# What Weapons gets from other stations' work when a toggle lets it: weak points and
	# resistances, hack windows, track feeds (P7 and P8).
	FEEDS = 14,
	# Comms' card board: cards, the open conversation nodes, offers, modules and credits.
	COMMS = 15,
	# The named sites the faction knows, sent on change (SitesSection, D229, FT-SPA-015);
	# 15 is COMMS.
	SITES = 16,
}

## The CAPTAIN block's objective kinds, as clients name them (stations/ may not name
## sim/): Objectives.Kind's values, which test_net_main_screen_rules checks.
const OBJECTIVE_DESTROY_HOSTILES: int = 1

## Most probes a RELAY block lists.
const RELAY_PROBE_ROWS: int = 64

## Load tags (FT-STN-015, D126).
const LIGHT: String = "light"
const BUSY: String = "busy"
const INTENSE: String = "intense"
const LOAD_TAGS: Array[String] = [LIGHT, BUSY, INTENSE]

## The toggle part of the view key (D14, D69, D84): a DataToggles code, "easy", "normal",
## "hard" or an edited set ("normal:1011000"). Every session of a server shares one, set
## in the lobby and locked at Start (FT-PAIR-017); a first launch is Easy (FT-STN-016).
## The sections that depend on it are FILTERED and are encoded once per ViewFilter
## signature, not once per ship.
const DEFAULT_TOGGLES: String = "easy"
## The sections whose content a ViewFilter changes.
const FILTERED: Array[int] = [
	Section.STATUS,
	Section.HELM,
	Section.ENGINEERING,
	Section.RELAY,
	Section.FEEDS,
	Section.CHIPS,
	Section.COMMS,
]

const CREW: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
const CAPTAIN: String = "captain"
const VIEWER: String = "viewer"
## Development entry holding every station (FT-NET-029, D72), offered with
## --dev-all-stations only.
const ALL: String = "all"
## stations_of() of an unknown id.
const NO_STATIONS: Array[String] = []

## Catalogue entries other than the six stations, in catalogue order: id -> [name,
## load tag, covered stations]. One joint view per pair of functional stations, in
## §7.3 pair order (FT-JNT-004, FT-NET-032, spec §3.3); a joint view takes the busier
## of its stations' load tags (D198).
const ENTRIES: Dictionary = {
	"drive": ["Drive", INTENSE, ["engineering", "helm"]],
	"tactical": ["Tactical", INTENSE, ["helm", "weapons"]],
	"survey": ["Survey", INTENSE, ["helm", "science"]],
	"nav": ["Nav", INTENSE, ["helm", "relay"]],
	"approach": ["Approach", INTENSE, ["helm", "comms"]],
	"gunnery": ["Gunnery", INTENSE, ["weapons", "engineering"]],
	"targeting": ["Targeting", INTENSE, ["weapons", "science"]],
	"fire_control": ["Fire Control", INTENSE, ["weapons", "relay"]],
	"parley": ["Parley", INTENSE, ["weapons", "comms"]],
	"systems": ["Systems", BUSY, ["engineering", "science"]],
	"logistics": ["Logistics", BUSY, ["engineering", "relay"]],
	"quartermaster": ["Quartermaster", BUSY, ["engineering", "comms"]],
	"sensors": ["Sensors", BUSY, ["science", "relay"]],
	"intel": ["Intel", BUSY, ["science", "comms"]],
	"ops": ["Ops", LIGHT, ["relay", "comms"]],
	"captain": ["Captain", LIGHT, []],
	"viewer": ["Viewer", "", []],
}
## Station -> [name, load tag] (D126).
const STATIONS: Dictionary = {
	"helm": ["Helm", INTENSE],
	"weapons": ["Weapons", INTENSE],
	"engineering": ["Engineering", BUSY],
	"science": ["Science", BUSY],
	"relay": ["Relay", LIGHT],
	"comms": ["Comms", LIGHT],
}

## Sections per station or seat: every station has the top bar (STATUS, and CAPTAIN for the
## goal chip's open objectives) and the disc radar (CONTACTS, FT-STN-001, FT-STN-002); the
## views that draw ship models and tracers (Helm cockpit, Weapons turret, Captain and main
## screen) add NEAR and PROJECTILES; the stations with claims or ship-wide controls add OWNERSHIP
## (FT-NET-023, FT-NET-044).
const STATION_SECTIONS: Dictionary = {
	"helm":
	[
		Section.KIN,
		Section.STATUS,
		Section.CAPTAIN,
		Section.HELM,
		Section.CONTACTS,
		Section.NEAR,
		Section.PROJECTILES,
		Section.OWNERSHIP,
		Section.CHIPS,
	],
	"weapons":
	[
		Section.KIN,
		Section.STATUS,
		Section.CAPTAIN,
		Section.MOUNTS,
		Section.CONTACTS,
		Section.NEAR,
		Section.PROJECTILES,
		Section.OWNERSHIP,
		Section.FEEDS,
		Section.CHIPS,
	],
	"engineering":
	[
		Section.KIN,
		Section.STATUS,
		Section.CAPTAIN,
		Section.ENGINEERING,
		Section.CONTACTS,
		Section.RELAY,
		Section.OWNERSHIP,
		Section.CHIPS,
	],
	"science":
	[
		Section.KIN,
		Section.STATUS,
		Section.CAPTAIN,
		Section.SCIENCE,
		Section.CONTACTS,
		Section.RELAY,
		Section.OWNERSHIP,
		Section.CHIPS,
	],
	"relay":
	[
		Section.KIN,
		Section.STATUS,
		Section.CAPTAIN,
		Section.CONTACTS,
		Section.RELAY,
		Section.OWNERSHIP,
		Section.CHIPS,
	],
	"comms":
	[
		Section.KIN,
		Section.STATUS,
		Section.CAPTAIN,
		Section.CONTACTS,
		Section.CHIPS,
		Section.COMMS,
	],
	"captain":
	[
		Section.KIN,
		Section.STATUS,
		Section.CONTACTS,
		Section.NEAR,
		Section.PROJECTILES,
		Section.CAPTAIN,
		Section.CHIPS,
		Section.COMMS,
	],
	"viewer":
	[
		Section.KIN,
		Section.STATUS,
		Section.CONTACTS,
		Section.NEAR,
		Section.PROJECTILES,
		Section.CAPTAIN,
	],
}

## Crew command kinds (SimCommand.kind()) per station. A command is accepted only from
## a client whose pick covers its station (FT-NET-006). Commands missing here
## (reset_ship, abandon_ship) are server-only. Science, Relay and Comms get theirs with
## #8 to #10.
const STATION_COMMANDS: Dictionary = {
	"helm":
	[
		&"helm_input",
		&"helm_decoupled",
		&"helm_all_stop",
		&"helm_align",
		&"helm_select_target",
		&"set_shield_focus",
		&"helm_jump",
		&"helm_dock",
		&"helm_undock",
	],
	"weapons": [&"aim_mount", &"fire", &"fire_guided", &"set_ammo_type"],
	"engineering":
	[
		&"set_pips",
		&"boost",
		&"set_shield",
		&"dispatch_repair",
		&"recall_repair",
		&"pick_fault_cause",
		&"harden",
		# Probe fabrication (FT-ENG-008); Engineering only sends it.
		&"fabricate_probe",
	],
	"science":
	[
		&"science_scan",
		&"science_scan_submit",
		&"science_hack",
		&"science_hack_move",
		&"science_cancel",
		&"science_self_scan",
		&"science_sensor_mode",
		&"science_ping",
		&"science_scan_mark",
		&"science_select",
	],
	"relay": [&"launch_probe", &"flag_lanes"],
	# Trading is Comms' alone (FT-PAIR-011, D68); accepting and declining need no claim
	# (FT-COM-003).
	"comms":
	[
		&"comms_hail",
		&"comms_answer",
		&"comms_reply",
		&"comms_accept",
		&"comms_decline",
		&"comms_trade",
		&"comms_buy_module",
		&"comms_sell_module",
	],
	# Next (Shakedown, D235) is sent by every crew station and the Captain.
	"captain": [&"training_next"],
}

## Core actions per station (D232, FT-MIS-038), in StationDef.core_actions' "action=source"
## form. Relay's mark and route are net-side crew ops (NetCrewState), the rest commands.
const STATION_CORE_ACTIONS: Dictionary = {
	"helm":
	[
		"face=helm_input.face",
		"approach=helm_input.approach",
		"all_stop=helm_all_stop",
		"jump=helm_jump",
	],
	"weapons": ["aim=aim_mount", "fire=fire|fire_guided", "ammo_type=set_ammo_type"],
	"engineering": ["pips=set_pips", "dispatch_repair=dispatch_repair", "boost=boost"],
	"science": ["scan=science_scan", "hack=science_hack"],
	"relay": ["mark=op:mark_place", "probe=launch_probe", "route=op:route_add"],
	"comms":
	[
		"answer_hail=comms_answer",
		"reply=comms_reply",
		"accept_card=comms_accept",
		"trade=comms_trade"
	],
}

## Claimable item kinds (FT-NET-022, D18). An item is the kind, or "kind:index" for
## one of several (a mount, a repair crew). The active scan or hack, probes and NPC
## conversations come with #9 and #10.
const CLAIM_FLIGHT: String = "flight"
const CLAIM_SHIELD_FACING: String = "shield_facing"
const CLAIM_MOUNT: String = "mount"
const CLAIM_CREW: String = "crew"
## The one active scan or hack (or own-ship scan) at a time (FT-NET-022, FT-SCI-004).
const CLAIM_SCAN: String = "scan"
## Relay's probe launcher: a second Relay seat claims it to launch.
const CLAIM_PROBE: String = "probe"
## One NPC conversation, item "npc:<card id>" (FT-COM-006, D18): only its claimer
## replies and hears the NPC. The items are the ship's open conversations (claim_items).
const CLAIM_NPC: String = "npc"
## Station -> claimable item kinds.
const STATION_CLAIMS: Dictionary = {
	"helm": [CLAIM_FLIGHT, CLAIM_SHIELD_FACING],
	"weapons": [CLAIM_MOUNT],
	"engineering": [CLAIM_CREW],
	"science": [CLAIM_SCAN],
	"relay": [CLAIM_PROBE],
	"comms": [CLAIM_NPC],
}
## Station -> ship-wide controls: last writer wins, and snapshots name the last writer
## (FT-NET-044). A control is the name, or "name:index" (pips per subsystem kind).
const STATION_CONTROLS: Dictionary = {
	"helm": ["target"],
	"engineering": ["pips", "shield", "boost"],
}
## Command kind -> [claim kind or control, the command field holding its index or ""].
## Align and face (HelmInputCommand.face) are Helm flight (FT-NET-045); so are dock
## and jump when they exist, and an ammo-type command joins the mount claim.
const COMMAND_ITEMS: Dictionary = {
	&"helm_input": [CLAIM_FLIGHT, ""],
	&"helm_decoupled": [CLAIM_FLIGHT, ""],
	&"helm_all_stop": [CLAIM_FLIGHT, ""],
	&"helm_align": [CLAIM_FLIGHT, ""],
	&"helm_jump": [CLAIM_FLIGHT, ""],
	&"helm_dock": [CLAIM_FLIGHT, ""],
	&"helm_undock": [CLAIM_FLIGHT, ""],
	&"set_shield_focus": [CLAIM_SHIELD_FACING, ""],
	&"aim_mount": [CLAIM_MOUNT, "mount_index"],
	&"fire": [CLAIM_MOUNT, "mount_index"],
	&"fire_guided": [CLAIM_MOUNT, "mount_index"],
	&"set_ammo_type": [CLAIM_MOUNT, "mount_index"],
	&"dispatch_repair": [CLAIM_CREW, "crew"],
	&"recall_repair": [CLAIM_CREW, "crew"],
	&"helm_select_target": ["target", ""],
	&"set_pips": ["pips", "subsystem_kind"],
	&"set_shield": ["shield", ""],
	&"boost": ["boost", ""],
	&"science_scan": [CLAIM_SCAN, ""],
	&"science_scan_submit": [CLAIM_SCAN, ""],
	&"science_hack": [CLAIM_SCAN, ""],
	&"science_hack_move": [CLAIM_SCAN, ""],
	&"science_cancel": [CLAIM_SCAN, ""],
	&"science_self_scan": [CLAIM_SCAN, ""],
	&"launch_probe": [CLAIM_PROBE, ""],
	# A reply or an opening acts on one conversation; accepting, declining and
	# trading are Comms' alone and need no claim (FT-COM-003).
	&"comms_answer": [CLAIM_NPC, "card"],
	&"comms_reply": [CLAIM_NPC, "card"],
}

## Field sets of the block sections (BlockSchema, the wire schema; kept here for callers).
const BLOCKS: Dictionary = BlockSchema.BLOCKS

## Entry id -> StationDef, built once when the class loads (read-only after, so both
## threads may read it).
static var _defs: Dictionary = _build_all()


## A view key (FT-NET-040): ship, catalogue entry, difficulty-toggle set.
static func key(ship: int, entry: String, toggles: String = DEFAULT_TOGGLES) -> String:
	return "%d|%s|%s" % [ship, entry, toggles]


## [ship, entry, toggles] of a view key.
static func parse_key(view_key: String) -> Array:
	var parts: PackedStringArray = view_key.split("|")
	return [parts[0].to_int(), parts[1], parts[2]]


## Whether entry names a catalogue entry; ALL only with dev_all.
static func is_entry(entry: String, dev_all: bool = false) -> bool:
	return STATIONS.has(entry) or ENTRIES.has(entry) or (dev_all and entry == ALL)


## The StationDef of an entry, or null for an unknown id.
static func def(entry: String) -> StationDef:
	return _defs.get(entry)


## The catalogue in order: the six stations, the joint views, Captain, Viewer, and ALL
## under dev_all (FT-NET-015, FT-NET-017).
static func catalogue_ids(dev_all: bool) -> Array[String]:
	var out: Array[String] = []
	out.assign(CREW)
	for id: String in ENTRIES:
		out.append(id)
	if dev_all:
		out.append(ALL)
	return out


## The catalogue as sent in Catalogue.entries: StationDef.to_dict() of each entry.
static func catalogue(dev_all: bool) -> Array:
	var out: Array = []
	for id: String in catalogue_ids(dev_all):
		out.append(def(id).to_dict())
	return out


## The stations an entry covers (none for Captain, Viewer or an unknown id): the
## StationDef's own array, read-only for callers.
static func stations_of(entry: String) -> Array[String]:
	var d: StationDef = def(entry)
	return d.stations if d != null else NO_STATIONS


## Whether an entry is a crew entry: it covers a functional station (FT-NET-020).
static func is_crew(entry: String) -> bool:
	var d: StationDef = def(entry)
	return d != null and d.is_crew()


## The sections an entry sees, ascending (none for an unknown id).
static func sections_of(entry: String) -> Array[int]:
	var d: StationDef = def(entry)
	var out: Array[int] = []
	if d != null:
		out.assign(d.sections)
	return out


## The station a crew command kind belongs to, or "" (server-only or unknown).
static func station_of_command(kind: StringName) -> String:
	for station: String in STATION_COMMANDS:
		if (STATION_COMMANDS[station] as Array).has(kind):
			return station
	return ""


## The kind of an item or control ("mount" for "mount:1").
static func base_of(item: String) -> String:
	return item.get_slice(":", 0)


## Whether an item is claimable (a claim kind), not a ship-wide control.
static func is_claimable(item: String) -> bool:
	var base: String = base_of(item)
	for station: String in STATION_CLAIMS:
		if (STATION_CLAIMS[station] as Array).has(base):
			return true
	return false


## The station a claim item or control belongs to, or "".
static func station_of_item(item: String) -> String:
	var base: String = base_of(item)
	for station: String in STATION_CLAIMS:
		if (STATION_CLAIMS[station] as Array).has(base):
			return station
	for station: String in STATION_CONTROLS:
		if (STATION_CONTROLS[station] as Array).has(base):
			return station
	return ""


## The OWNERSHIP section content an entry sees: the claims and last writers of its own
## stations' items (FT-NET-023: "to others at that station").
static func ownership_for(entry: String, data: Dictionary) -> Dictionary:
	var stations: Array[String] = stations_of(entry)
	var out: Dictionary = {"claims": {}, "writers": {}}
	for part: String in out:
		var src: Dictionary = data.get(part, {})
		for item: String in src:
			if stations.has(station_of_item(item)):
				out[part][item] = src[item]
	return out


static func _build_all() -> Dictionary:
	var out: Dictionary = {}
	for id: String in catalogue_ids(true):
		out[id] = _build(id)
	return out


static func _build(entry: String) -> StationDef:
	var d: StationDef = StationDef.new()
	d.id = entry
	var seats: Array[String] = []
	if STATIONS.has(entry):
		d.display_name = STATIONS[entry][0]
		d.load_tag = STATIONS[entry][1]
		d.stations.append(entry)
	elif entry == ALL:
		d.display_name = "All stations (dev)"
		d.load_tag = INTENSE
		d.stations.assign(CREW)
	else:
		d.display_name = ENTRIES[entry][0]
		d.load_tag = ENTRIES[entry][1]
		d.stations.assign(ENTRIES[entry][2])
		if d.stations.is_empty():
			seats.append(entry)
	var seen: Dictionary = {}
	for s: String in d.stations + seats:
		for kind: int in STATION_SECTIONS[s]:
			seen[kind] = true
		if STATION_COMMANDS.has(s):
			d.commands.append_array(STATION_COMMANDS[s])
		d.claims.append_array(STATION_CLAIMS.get(s, []))
		d.controls.append_array(STATION_CONTROLS.get(s, []))
		d.core_actions.append_array(STATION_CORE_ACTIONS.get(s, []))
	seen[Section.SITES] = true  # Every view sees the named sites (FT-SPA-015).
	d.sections.assign(seen.keys())
	d.sections.sort()
	for kind: int in d.sections:
		if BLOCKS.has(kind):
			d.fields[kind] = (BLOCKS[kind] as Array).map(func(f: Array) -> String: return f[0])
	return d
