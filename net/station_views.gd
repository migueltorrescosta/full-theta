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
}

## Most probes a RELAY block lists.
const RELAY_PROBE_ROWS: int = 64

## Load tags (FT-STN-015, D126).
const LIGHT: String = "light"
const BUSY: String = "busy"
const INTENSE: String = "intense"
const LOAD_TAGS: Array[String] = [LIGHT, BUSY, INTENSE]

## Difficulty-toggle sets of the view key (D14, D69, D84): the three presets. M1 has
## no data shortcut in its sim (weak points, track feeds, routes come with #8 to #10),
## so no field depends on the set yet; the set is still part of the view key and the
## filter is checked at each (tests/net/test_net_stations_filter.gd).
const TOGGLE_SETS: Array[String] = ["easy", "normal", "hard"]
const DEFAULT_TOGGLES: String = "normal"

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
	],
	"engineering":
	[Section.KIN, Section.STATUS, Section.ENGINEERING, Section.CONTACTS, Section.OWNERSHIP],
	"science": [Section.KIN, Section.STATUS, Section.CONTACTS],
	"relay": [Section.KIN, Section.STATUS, Section.CONTACTS, Section.RELAY, Section.OWNERSHIP],
	"comms": [Section.KIN, Section.STATUS, Section.CONTACTS],
	"captain": [Section.KIN, Section.STATUS, Section.CONTACTS, Section.NEAR, Section.PROJECTILES],
	"viewer": [Section.KIN, Section.STATUS, Section.CONTACTS, Section.NEAR, Section.PROJECTILES],
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
	"weapons": [&"aim_mount", &"fire"],
	"engineering": [&"set_pips", &"boost", &"set_shield", &"dispatch_repair", &"recall_repair"],
	"science": [],
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
## Relay's probe launcher (strand B of #9): a second Relay seat claims it to launch.
const CLAIM_PROBE: String = "probe"
## Station -> claimable item kinds.
const STATION_CLAIMS: Dictionary = {
	"helm": [CLAIM_FLIGHT, CLAIM_SHIELD_FACING],
	"weapons": [CLAIM_MOUNT],
	"engineering": [CLAIM_CREW],
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
	&"dispatch_repair": [CLAIM_CREW, "crew"],
	&"recall_repair": [CLAIM_CREW, "crew"],
	&"helm_select_target": ["target", ""],
	&"set_pips": ["pips", "subsystem_kind"],
	&"set_shield": ["shield", ""],
	&"boost": ["boost", ""],
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
	&"ai_mode": [],
	# Relay's probes and lanes (strand B of #9); fabrication also tells Engineering.
	&"probe_launched": ["relay"],
	&"probe_deployed": ["relay"],
	&"probe_no_stock": ["relay"],
	&"probe_fabricating": ["relay", "engineering"],
	&"probe_fabricated": ["relay", "engineering"],
	&"probe_no_parts": ["engineering"],
	&"lane_warning": ["weapons", "relay"],
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
					["fault_armed", "bool"]
				],
			],
		],
	],
	# Relay's probes: the stock, Engineering's build in progress, the lane switch and
	# the ship's launched probes (site-local position in m, bubble radius in m).
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
					["aim_set", "bool"]
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
## weapon mount (Weapons), one per repair crew (Engineering).
static func claim_items(world: SimWorld, ship: int) -> Dictionary:
	var ship_def: ShipDef = world.defs[ship]
	var mounts: Array[String] = []
	for i: int in ship_def.mounts.size():
		mounts.append("%s:%d" % [CLAIM_MOUNT, i])
	var crews: Array[String] = []
	for i: int in ship_def.repair_crews:
		crews.append("%s:%d" % [CLAIM_CREW, i])
	var helm: Array[String] = [CLAIM_FLIGHT, CLAIM_SHIELD_FACING]
	return {"helm": helm, "weapons": mounts, "engineering": crews, "relay": [CLAIM_PROBE]}


## Whether a sim event of this kind reaches a session holding entry (faction and ship
## checks are ServerSession.event_audience()'s).
static func sees_event(entry: String, kind: StringName) -> bool:
	if not EVENT_STATIONS.has(kind):
		return true
	for station: String in stations_of(entry):
		if (EVENT_STATIONS[kind] as Array).has(station):
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
static func block_bytes(kind: int, world: SimWorld, ship: int) -> PackedByteArray:
	return NetBlock.encode(BLOCKS[kind], _block_values(kind, world, ship))


static func _block_values(kind: int, world: SimWorld, ship: int) -> Dictionary:
	match kind:
		Section.STATUS:
			return _status(world, ship)
		Section.HELM:
			return _helm(world, ship)
		Section.ENGINEERING:
			return _engineering(world, ship)
		Section.RELAY:
			return _relay(world, ship)
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
					"pos": Vector3(t.px[p], t.py[p], t.pz[p]),
					"range": world.defs[ship].probe_range,
				}
			)
		)
	return {
		"stock": r.stock[ship],
		"fab_left": r.fab_left[ship],
		"lanes": r.lanes_flagged[ship] == 1,
		"probes": probes,
	}


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
				}
			)
		)
	return {"mounts": mounts}
