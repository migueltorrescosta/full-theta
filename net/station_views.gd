class_name StationViews
extends RefCounted
## The one data-driven place mapping catalogue entries to what they see and do
## (FT-NET-008, FT-NET-040): the catalogue (functional stations, joint views, Captain,
## Viewer, the dev "all" entry), each station's snapshot sections, the field sets of
## the per-ship block sections, and which station each crew command belongs to.
## PROVISIONAL field sets from docs/spec/05-stations.md; T042 formalises StationDef and
## the per-station, per-difficulty, per-faction filter here (see net/README.md,
## "Adding a field, a section or a station").

## Section kinds (u8 on the wire). KIN, the block sections and NEAR/PROJECTILES are
## per ship; CONTACTS is per faction.
enum Section {
	KIN = 1,
	STATUS = 2,
	HELM = 3,
	ENGINEERING = 4,
	MOUNTS = 5,
	CONTACTS = 6,
	NEAR = 7,
	PROJECTILES = 8
}

const DEFAULT_TOGGLES: String = "normal"
const CREW: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
const CAPTAIN: String = "captain"
const VIEWER: String = "viewer"
## Development entry holding every station (FT-NET-029, D72), offered with
## --dev-all-stations only.
const ALL: String = "all"

## Joint views (spec §3.3, D67, D76): pair id -> [name, station, station].
const JOINT: Dictionary = {
	"p1": ["Drive", "engineering", "helm"],
	"p2": ["Tactical", "helm", "weapons"],
	"p3": ["Survey", "helm", "science"],
	"p4": ["Nav", "helm", "relay"],
	"p5": ["Approach", "helm", "comms"],
	"p6": ["Gunnery", "weapons", "engineering"],
	"p7": ["Targeting", "weapons", "science"],
	"p8": ["Fire Control", "weapons", "relay"],
	"p9": ["Parley", "weapons", "comms"],
	"p10": ["Systems", "engineering", "science"],
	"p11": ["Logistics", "engineering", "relay"],
	"p12": ["Quartermaster", "engineering", "comms"],
	"p13": ["Sensors", "science", "relay"],
	"p14": ["Intel", "science", "comms"],
	"p15": ["Ops", "relay", "comms"],
}

## Sections per station (PROVISIONAL, from S9 and spec §5): every station has the top
## bar (STATUS) and the disc radar (CONTACTS, FT-STN-001, FT-STN-002); the views that
## draw ship models and tracers (Helm cockpit, Weapons turret, Captain and main screen)
## add NEAR and PROJECTILES.
const STATION_SECTIONS: Dictionary = {
	"helm":
	[
		Section.KIN,
		Section.STATUS,
		Section.HELM,
		Section.CONTACTS,
		Section.NEAR,
		Section.PROJECTILES
	],
	"weapons":
	[
		Section.KIN,
		Section.STATUS,
		Section.MOUNTS,
		Section.CONTACTS,
		Section.NEAR,
		Section.PROJECTILES,
	],
	"engineering": [Section.KIN, Section.STATUS, Section.ENGINEERING, Section.CONTACTS],
	"science": [Section.KIN, Section.STATUS, Section.CONTACTS],
	"relay": [Section.KIN, Section.STATUS, Section.CONTACTS],
	"comms": [Section.KIN, Section.STATUS, Section.CONTACTS],
	"captain": [Section.KIN, Section.STATUS, Section.CONTACTS, Section.NEAR, Section.PROJECTILES],
	"viewer": [Section.KIN, Section.STATUS, Section.CONTACTS, Section.NEAR, Section.PROJECTILES],
}

## Crew command kinds (SimCommand.kind()) per station (PROVISIONAL). A command is
## accepted only from a client whose pick covers its station (FT-NET-006). Commands
## missing here (reset_ship) are server-only.
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
	"relay": [],
	"comms": [],
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
	],
	Section.ENGINEERING:
	[
		["boost_ticks", "u16"],
		["weapon_energy", "f32"],
		["hull", "f32"],
		["spare_parts", "u16"],
		["shield_strength", "f32"],
		["shield_tightness", "f32"],
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


## A view key (FT-NET-040): ship, catalogue entry, difficulty-toggle set.
static func key(ship: int, entry: String, toggles: String = DEFAULT_TOGGLES) -> String:
	return "%d|%s|%s" % [ship, entry, toggles]


## [ship, entry, toggles] of a view key.
static func parse_key(view_key: String) -> Array:
	var parts: PackedStringArray = view_key.split("|")
	return [parts[0].to_int(), parts[1], parts[2]]


## Whether entry names a catalogue entry; ALL only with dev_all.
static func is_entry(entry: String, dev_all: bool = false) -> bool:
	return (
		CREW.has(entry)
		or JOINT.has(entry)
		or entry == CAPTAIN
		or entry == VIEWER
		or (dev_all and entry == ALL)
	)


## The stations an entry covers: one for a station, two for a joint view, every crew
## station for ALL, none for Captain and Viewer (they hold no crew commands, D19).
static func stations_of(entry: String) -> Array[String]:
	var out: Array[String] = []
	if CREW.has(entry):
		out.append(entry)
	elif JOINT.has(entry):
		out.append(JOINT[entry][1])
		out.append(JOINT[entry][2])
	elif entry == ALL:
		out.assign(CREW)
	return out


## The sections an entry sees, ascending: the union over its stations (a joint view is
## a layout, so it adds keys but no sections).
static func sections_of(entry: String) -> Array[int]:
	var seen: Dictionary = {}
	var stations: Array[String] = stations_of(entry)
	if entry == CAPTAIN or entry == VIEWER:
		stations.append(entry)
	for s: String in stations:
		for kind: int in STATION_SECTIONS[s]:
			seen[kind] = true
	var out: Array[int] = []
	out.assign(seen.keys())
	out.sort()
	return out


## The station a crew command kind belongs to, or "" (server-only or unknown).
static func station_of_command(kind: StringName) -> String:
	for station: String in STATION_COMMANDS:
		if (STATION_COMMANDS[station] as Array).has(kind):
			return station
	return ""


## The catalogue as sent in Catalogue.entries: [{id, name, stations}], with ALL only
## under dev_all. T043 adds availability (Captain taken, coverage).
static func catalogue(dev_all: bool) -> Array:
	var out: Array = []
	for s: String in CREW:
		out.append({"id": s, "name": s.capitalize(), "stations": [s]})
	for p: String in JOINT:
		out.append({"id": p, "name": JOINT[p][0], "stations": [JOINT[p][1], JOINT[p][2]]})
	out.append({"id": CAPTAIN, "name": "Captain", "stations": []})
	out.append({"id": VIEWER, "name": "Viewer", "stations": []})
	if dev_all:
		out.append({"id": ALL, "name": "All stations (dev)", "stations": CREW.duplicate()})
	return out


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
		"subsystems": subsystems,
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
