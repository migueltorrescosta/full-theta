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
	# Reserved for M2 (#9); each strand fills its own section's fields and getter.
	# Science contact card, scan and hack state (strand A).
	SCIENCE = 10,
	# Relay probes, coverage, routes, hazards and inbox (strand B).
	RELAY = 11,
	# Captain and main screen: main-screen view, open chips, cards (strand F).
	CAPTAIN = 12,
	# Open request chips of the ship (strand G).
	CHIPS = 13,
	# What Weapons gets from other stations' work when a toggle lets it: weak points and
	# resistances, hack windows, track feeds (strand G, P7 and P8).
	FEEDS = 14,
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

## Sections per station or seat: every station has the top bar (STATUS) and the disc
## radar (CONTACTS, FT-STN-001, FT-STN-002); the views that draw ship models and
## tracers (Helm cockpit, Weapons turret, Captain and main screen) add NEAR and
## PROJECTILES; the stations with claims or ship-wide controls add OWNERSHIP
## (FT-NET-023, FT-NET-044).
const STATION_SECTIONS: Dictionary = {
	"helm":
	[
		Section.KIN,
		Section.STATUS,
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
		Section.CONTACTS,
		Section.RELAY,
		Section.OWNERSHIP,
		Section.CHIPS,
	],
	"comms": [Section.KIN, Section.STATUS, Section.CONTACTS, Section.CHIPS],
	"captain":
	[
		Section.KIN,
		Section.STATUS,
		Section.CONTACTS,
		Section.NEAR,
		Section.PROJECTILES,
		Section.CAPTAIN,
		Section.CHIPS,
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
		# Strand B's probe fabrication (FT-ENG-008); Engineering only sends it.
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
	"comms": [],
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
## Relay's probe launcher (strand B of #9): a second Relay seat claims it to launch.
const CLAIM_PROBE: String = "probe"
## Station -> claimable item kinds.
const STATION_CLAIMS: Dictionary = {
	"helm": [CLAIM_FLIGHT, CLAIM_SHIELD_FACING],
	"weapons": [CLAIM_MOUNT],
	"engineering": [CLAIM_CREW],
	"science": [CLAIM_SCAN],
	"relay": [CLAIM_PROBE],
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
}

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
	&"fault_inflicted": ["engineering"],
	&"fault_cause_revealed": ["engineering"],
	&"fault_cause_picked": ["engineering"],
	&"fault_cleared": ["engineering"],
	&"hardened": ["engineering"],
	&"harden_expired": ["engineering"],
	&"harden_no_parts": ["engineering"],
	&"ai_mode": [],
	&"science_refused": ["science"],
	&"scan_started": ["science"],
	&"scan_done": ["science"],
	&"scan_failed": ["science"],
	&"scan_mark": ["science", "helm"],
	&"hack_started": ["science"],
	&"hack_traced": ["science"],
	&"hack_failed": ["science"],
	&"hack_done": ["science", "weapons"],
	&"hack_window_end": ["science", "weapons"],
	&"self_scan_started": ["science"],
	&"self_scan_done": ["science", "engineering"],
	&"active_ping": ["science"],
	# Relay's probes and lanes (strand B of #9); fabrication also tells Engineering.
	&"probe_launched": ["relay"],
	&"probe_deployed": ["relay"],
	&"probe_no_stock": ["relay"],
	&"probe_fabricating": ["relay", "engineering"],
	&"probe_fabricated": ["relay", "engineering"],
	&"probe_no_parts": ["engineering"],
	&"lane_warning": ["weapons", "relay"],
}

## Events that are a data shortcut when they leave the station that produced them: kind ->
## [toggle, source station]. The source's own sessions always get them; another station
## gets one when the toggle is on or it is in a joint view with the source (ViewFilter.grants,
## FT-PAIR-008). Hack windows and weak-point hits are Science's work shown on Weapons (P7),
## own-ship scan results Science's shown on Engineering (P10), flagged lanes Relay's shown
## on Weapons (P8). Scan-position marks are MARK items and reach Helm at every difficulty.
const EVENT_SHORTCUTS: Dictionary = {
	&"hack_done": [&"weak_points", "science"],
	&"hack_window_end": [&"weak_points", "science"],
	&"self_scan_done": [&"diagnosed_causes", "science"],
	&"fault_cause_revealed": [&"diagnosed_causes", "science"],
	&"lane_warning": [&"track_feeds", "relay"],
}

## Field sets of the block sections: Section -> NetBlock schema. A block is sent whole
## when any field changes, else omitted from the delta. Getters are in _block_values().
const BLOCKS: Dictionary = {
	Section.STATUS:
	[
		["alive", "bool"],
		["status", "u8"],
		["outcome", "u8"],
		["hull", "f32"],
		["shields", "f32"],
		["pips_used", "u8"],
		["propellant", "f32"],
		# The main screen switches to chase while decoupled (FT-MSC-001).
		["decoupled", "bool"],
	],
	Section.HELM:
	[
		["decoupled", "bool"],
		["throttle_setpoint", "f32"],
		["face", "bool"],
		["approach", "bool"],
		["all_stop", "bool"],
		["align", "u8"],
		["target_kind", "u8"],
		["target_ship", "s16"],
		["shield_focus", "v3n"],
		["shield_track", "s16"],
		# The shield ring shows Engineering's tightness too (FT-HLM-011).
		["shield_tightness", "f32"],
		["shield_power", "f32"],
		# Engineering's thrust and torque envelope scales (FT-HLM-012).
		["thrust_scale", "f32"],
		["torque_scale", "f32"],
	],
	Section.ENGINEERING:
	[
		["boost_ticks", "u16"],
		["weapon_energy", "f32"],
		["hull", "f32"],
		["spare_parts", "u16"],
		["shield_strength", "f32"],
		["shield_tightness", "f32"],
		# Engineering's mirror of Helm's shield ring (§5.3).
		["shield_focus", "v3n"],
		[
			"subsystems",
			[
				"rows",
				[
					["health", "f32"],
					["pips", "u8"],
					["heat", "f32"],
					["crews", "u32"],
					["fault_armed", "bool"],
					# Unknown-cause fault (FT-SIM-025): whether one is open, the cause's
					# index in SubsystemDef.fault_causes plus 1 once revealed (else 0),
					# Engineering's pick the same way, and ticks of hardening left.
					["fault", "bool"],
					["fault_cause", "u8"],
					["fault_pick", "u8"],
					["hardened", "u16"],
				],
			],
		],
	],
	# Science (strand A, E01): sensors, the noise preview of the selected contact, the
	# scan-position mark, the open minigame session with its puzzle, the contact cards of
	# the faction's knowledge (FT-SCI-001, FT-SCI-002) and the faction's open hack
	# windows (P7). noise_flags: bit 0 active, 1 ping, 2 probe, 3 at the mark.
	Section.SCIENCE:
	[
		["active", "bool"],
		["ping_left", "f32"],
		["ping_cool", "f32"],
		["selected", "s16"],
		["noise", "f32"],
		["noise_range", "f32"],
		["noise_aspect", "f32"],
		["noise_health", "f32"],
		["noise_flags", "u8"],
		["mark_contact", "s16"],
		["mark_site", "s16"],
		["mark_pos", "v3f"],
		["self_scanned", "bool"],
		# Session: 0 none, 1 scan, 2 hack, 3 own-ship scan.
		["session", "u8"],
		["session_target", "s16"],
		["session_noise", "f32"],
		["session_start", "u32"],
		["session_probe", "bool"],
		# Scan: open axes mask (1 x, 2 y, 4 z), the wireframe and the cloud.
		["axes", "u8"],
		["wire", ["rows", [["p", "v3f"]]]],
		["cloud", ["rows", [["p", "v3f"]]]],
		# Hack: grid size, the node the route is at, the goal, the subsystem index,
		# the trace bar, the known-node mask and the edge mask of each known node.
		["hack_cols", "u8"],
		["hack_rows", "u8"],
		["hack_node", "s16"],
		["hack_goal", "s16"],
		["hack_sub", "s16"],
		["trace", "f32"],
		["known", "u32"],
		["edges", ["rows", [["mask", "u8"]]]],
		[
			"cards",
			[
				"rows",
				[
					["contact", "s16"],
					["detect", "f32"],
					["scan", "f32"],
					["class_id", "u32"],
					["intent", "u8"],
					["weak_mask", "u32"],
					["resist", ["rows", [["type", "u32"], ["factor", "f32"]]]],
					["hack", "bool"],
				],
			],
		],
		["hacks", ["rows", [["target", "s16"], ["sub", "u8"], ["left", "f32"], ["by", "s16"]]]],
	],
	# Relay's probes: the stock, Engineering's build in progress, the lane switch and
	# the ship's launched probes (site-local position in m, bubble radius in m); then the
	# sim hazards the faction knows (strand J, HazardView): zone, shell or plane, where now,
	# the radius now, a plane's direction and the forecast seconds to the ship (-1: none).
	Section.RELAY:
	[
		["stock", "u16"],
		["fab_left", "f32"],
		["lanes", "bool"],
		[
			"probes",
			[
				"rows",
				[
					["serial", "u16"],
					["deployed", "bool"],
					["pos", "v3f"],
					["range", "f32"],
				],
			],
		],
		[
			"hazards",
			[
				"rows",
				[
					["id", "u8"],
					["shape", "u8"],
					["pos", "v3f"],
					["radius", "f32"],
					["dir", "v3f"],
					["eta", "f32"],
				],
			],
		],
	],
	# The main screen's status view (strand F, FT-MSC-006): each subsystem's health in
	# ShipDef.subsystems order and the ship's open objectives (Objectives.Kind, how many
	# are left). The view itself and the open cards are crew state, not sim: the
	# `main_view` event and the ping events.
	Section.CAPTAIN:
	[
		["subsystems", ["rows", [["health", "f32"]]]],
		["objectives", ["rows", [["kind", "u8"], ["left", "u16"]]]],
	],
	Section.MOUNTS:
	[
		[
			"mounts",
			[
				"rows",
				[
					["barrel", "v3n"],
					["cooldown", "f32"],
					["ammo", "s32"],
					["heat", "f32"],
					["aim_set", "bool"],
					# Selected ammunition type (FT-WPN-006), overheat lock (P6).
					["ammo_type", "u8"],
					["locked", "bool"]
				],
			],
		],
	],
	# What Weapons gets from other stations when a toggle lets it (strand G, FeedsView): the
	# faction's scanned weak points (bit i: subsystem i of the contact) and resistances (P7),
	# the open hack windows (P7) and the track quality of detected contacts (P8, quality is
	# the detection confidence, probe whether a deployed probe covers the contact).
	Section.FEEDS:
	[
		[
			"weak",
			[
				"rows",
				[
					["contact", "s16"],
					["class_id", "u32"],
					["weak_mask", "u32"],
					["resist", ["rows", [["type", "u32"], ["factor", "f32"]]]],
				],
			],
		],
		["windows", ["rows", [["target", "s16"], ["sub", "u8"], ["left", "f32"], ["by", "s16"]]]],
		["tracks", ["rows", [["contact", "s16"], ["quality", "f32"], ["probe", "bool"]]]],
	],
	# The ship's open request chips (strand G, ChipsSection; NetChips on the server): the
	# chip's index in content/chips/chips.tres, its argument (mount index or contact id, -1
	# for none), the sending and receiving station (index in CREW) and the sim ticks it was
	# sent and expires at. A crew view lists the chips it sends or receives.
	Section.CHIPS:
	[
		[
			"chips",
			[
				"rows",
				[
					["id", "u16"],
					["chip", "u8"],
					["arg", "s16"],
					["from", "u8"],
					["to", "u8"],
					["sent", "u32"],
					["expires", "u32"],
				],
			],
		],
	],
}

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


## The claim item or ship-wide control a command acts on ("mount:1", "flight",
## "pips:2"), or "" for a command with neither.
static func item_of(command: SimCommand) -> String:
	var spec: Array = COMMAND_ITEMS.get(command.kind(), [])
	if spec.is_empty():
		return ""
	if spec[1] == "":
		return spec[0]
	return "%s:%d" % [spec[0], int(command.get(spec[1]))]


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


## The claimable items of a ship by station: flight and shield facing (Helm), one per
## weapon mount (Weapons), one per repair crew (Engineering), the scan (Science).
static func claim_items(world: SimWorld, ship: int) -> Dictionary:
	var ship_def: ShipDef = world.defs[ship]
	var mounts: Array[String] = []
	for i: int in ship_def.mounts.size():
		mounts.append("%s:%d" % [CLAIM_MOUNT, i])
	var crews: Array[String] = []
	for i: int in ship_def.repair_crews:
		crews.append("%s:%d" % [CLAIM_CREW, i])
	var helm: Array[String] = [CLAIM_FLIGHT, CLAIM_SHIELD_FACING]
	return {
		"helm": helm,
		"weapons": mounts,
		"engineering": crews,
		"science": [CLAIM_SCAN],
		"relay": [CLAIM_PROBE],
	}


## Whether a sim event of this kind reaches a session holding entry (faction and ship
## checks are ServerSession.event_audience()'s).
static func sees_event(entry: String, kind: StringName, toggles: String = DEFAULT_TOGGLES) -> bool:
	if not EVENT_STATIONS.has(kind):
		return true
	var shortcut: Array = EVENT_SHORTCUTS.get(kind, [])
	var filter: ViewFilter = null
	for station: String in stations_of(entry):
		if not (EVENT_STATIONS[kind] as Array).has(station):
			continue
		if shortcut.is_empty() or station == shortcut[1]:
			return true
		if filter == null:
			filter = ViewFilter.of(entry, toggles)
		if filter != null and filter.grants(shortcut[0]):
			return true
	return false


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
	d.sections.assign(seen.keys())
	d.sections.sort()
	for kind: int in d.sections:
		if BLOCKS.has(kind):
			d.fields[kind] = (BLOCKS[kind] as Array).map(func(f: Array) -> String: return f[0])
	return d


## The block section's fields for a ship, read from a (copied) world, encoded.
static func block_bytes(
	kind: int, world: SimWorld, ship: int, filter: ViewFilter = null
) -> PackedByteArray:
	var values: Dictionary = _block_values(kind, world, ship)
	if filter != null:
		filter.apply(kind, values, world, ship)
	return NetBlock.encode(BLOCKS[kind], values)


static func _block_values(kind: int, world: SimWorld, ship: int) -> Dictionary:
	match kind:
		Section.STATUS:
			return _status(world, ship)
		Section.HELM:
			return _helm(world, ship)
		Section.ENGINEERING:
			return _engineering(world, ship)
		Section.SCIENCE:
			return ScienceView.block(world, ship)
		Section.RELAY:
			return _relay(world, ship)
		Section.CAPTAIN:
			return _captain(world, ship)
		Section.FEEDS:
			return FeedsView.block(world, ship)
	return _mounts(world, ship)


static func _status(world: SimWorld, ship: int) -> Dictionary:
	var hull_row: int = world.damage.rows_of(ship)[0]
	var pips: int = 0
	for r: int in world.damage.rows_of(ship):
		pips += world.damage.pips[r]
	return {
		"alive": world.kin.is_alive(ship),
		"status": world.run.status[ship],
		"outcome": world.run.outcome[ship],
		"hull": world.damage.health[hull_row],
		"shields": world.shields.strength[ship],
		"pips_used": pips,
		"propellant": world.kin.propellant[ship],
		"decoupled": world.helm.decoupled[ship] == 1,
	}


static func _helm(world: SimWorld, ship: int) -> Dictionary:
	var h: HelmTable = world.helm
	return {
		"decoupled": h.decoupled[ship] == 1,
		"throttle_setpoint": h.throttle_setpoint[ship],
		"face": h.face_held[ship] == 1,
		"approach": h.approach_held[ship] == 1,
		"all_stop": h.all_stop[ship] == 1,
		"align": h.align[ship],
		"target_kind": h.target_kind[ship],
		"target_ship": h.target_ship[ship],
		"shield_focus": world.shields.focus[ship],
		"shield_track": world.shields.track_id[ship],
		"shield_tightness": world.shields.tightness[ship],
		"shield_power": ShieldSystem.power(world, ship),
		"thrust_scale": world.kin.thrust_scale[ship],
		"torque_scale": world.kin.torque_scale[ship],
	}


static func _engineering(world: SimWorld, ship: int) -> Dictionary:
	var d: DamageTable = world.damage
	var rows: PackedInt32Array = d.rows_of(ship)
	var subsystems: Array = []
	for i: int in range(1, rows.size()):
		var r: int = rows[i]
		(
			subsystems
			. append(
				{
					"health": d.health[r],
					"pips": d.pips[r],
					"heat": d.heat[r],
					"crews": d.crews[r],
					"fault_armed": d.fault_armed[r] == 1,
					"fault": d.fault_cause[r] != &"",
					"fault_cause":
					_cause_index(world, ship, i - 1, d.fault_cause[r], d.fault_known[r]),
					"fault_pick": _cause_index(world, ship, i - 1, d.fault_pick[r], 1),
					"hardened": mini(d.hardened_ticks[r], 65535),
				}
			)
		)
	return {
		"boost_ticks": world.power.boost_ticks[ship],
		"weapon_energy": world.power.weapon_energy[ship],
		"hull": d.health[rows[0]],
		"spare_parts": d.spare_parts[rows[0]],
		"shield_strength": world.shields.strength[ship],
		"shield_tightness": world.shields.tightness[ship],
		"shield_focus": world.shields.focus[ship],
		"subsystems": subsystems,
	}


## Relay's block: at most the newest RELAY_PROBE_ROWS probes (a row count is one byte).
static func _relay(world: SimWorld, ship: int) -> Dictionary:
	var r: RelayTable = world.relay
	var t: ProbeTable = world.probes
	var rows: PackedInt32Array = t.rows_of(ship)
	var probes: Array = []
	for i: int in range(maxi(0, rows.size() - RELAY_PROBE_ROWS), rows.size()):
		var p: int = rows[i]
		(
			probes
			. append(
				{
					"serial": t.serial[p],
					"deployed": t.deployed[p] == 1,
					"pos": Vector3(t.at_x[p], t.at_y[p], t.at_z[p]),
					"range": world.defs[ship].probe_range,
				}
			)
		)
	return {
		"stock": r.stock[ship],
		"fab_left": r.fab_left[ship],
		"lanes": r.lanes_flagged[ship] == 1,
		"probes": probes,
		"hazards": HazardView.rows(world, ship),
	}


## The status view's block: subsystem health and open objectives.
static func _captain(world: SimWorld, ship: int) -> Dictionary:
	var rows: PackedInt32Array = world.damage.rows_of(ship)
	var subsystems: Array = []
	for i: int in range(1, rows.size()):
		subsystems.append({"health": world.damage.health[rows[i]]})
	return {"subsystems": subsystems, "objectives": Objectives.of_ship(world, ship)}


## Index of the cause in the subsystem's fault_causes plus 1 when known, else 0.
static func _cause_index(
	world: SimWorld, ship: int, sub: int, cause: StringName, known: int
) -> int:
	if cause == &"" or known == 0:
		return 0
	return (world.defs[ship].subsystems[sub].fault_causes.find(cause) + 1) & 0xff


static func _mounts(world: SimWorld, ship: int) -> Dictionary:
	var m: MountTable = world.mounts
	var mounts: Array = []
	for r: int in m.rows_of(ship):
		(
			mounts
			. append(
				{
					"barrel": m.barrel[r],
					"cooldown": m.cooldown[r],
					"ammo": m.ammo[r],
					"heat": m.heat[r],
					"aim_set": m.aim_set[r] == 1,
					"ammo_type": m.ammo_type[r],
					"locked": m.locked[r] == 1,
				}
			)
		)
	return {"mounts": mounts}
