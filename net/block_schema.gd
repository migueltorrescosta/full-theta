class_name BlockSchema
extends RefCounted
## The wire schema of the block sections (F4, R13-8): NetBlock field sets the server's
## builders (StationBlocks, ScienceView, FeedsView, CommsView) fill and the clients decode
## (NetViewState). It names no sim class, so clients may read it (D103).

## Row kind of a hazard plane in a RELAY block's hazards (HazardView builds them).
const HAZARD_PLANE: int = 2

## Section.COMMS (CommsView builds it): the ship's docked site
## and credits, the hull band (Comms' only view of condition, FT-PAIR-010), reputation per
## faction, the cards (kind and state are StoryTable's; rep_lo/rep_hi only where rep_vis;
## claimer the session holding the conversation, -1 for none), the open conversation nodes
## with their replies, what the docked market sells, the modules it offers per slot with
## the trade-in of the module now fitted, and the fitted modules.
const COMMS: Array = [
	["docked", "bool"],
	["site", "s16"],
	["credits", "s32"],
	["hull_band", "u8"],
	["rep", ["rows", [["faction", "u8"], ["value", "f32"]]]],
	[
		"cards",
		[
			"rows",
			[
				["id", "u16"],
				["kind", "u8"],
				["state", "u8"],
				["npc", "str"],
				["title", "str"],
				["detail", "str"],
				["expires", "f32"],
				["reward", "s32"],
				["rep_vis", "bool"],
				["rep_lo", "f32"],
				["rep_hi", "f32"],
				["target", "s16"],
				["claimer", "s16"],
				["conv", "bool"],
				["open", "bool"],
				["requires_docked", "bool"],
				["site", "s16"],
				["marked", "bool"],
			],
		],
	],
	[
		"nodes",
		[
			"rows",
			[
				["card", "u16"],
				["line", "str"],
				[
					"options",
					[
						"rows",
						[["id", "str"], ["text", "str"], ["enabled", "bool"], ["verify", "bool"]],
					],
				],
			],
		],
	],
	[
		"offers",
		[
			"rows",
			[
				["card", "u16"],
				["item", "str"],
				["price", "s32"],
				["sell", "s32"],
				["stock", "s32"],
			],
		],
	],
	[
		"modules",
		[
			"rows",
			[
				["card", "u16"],
				["module", "str"],
				["name", "str"],
				["slot", "u8"],
				["price", "s32"],
				["old", "str"],
				["trade_in", "s32"],
			],
		],
	],
	["fitted", ["rows", [["slot", "u8"], ["type", "str"], ["module", "str"]]]],
]

## Field sets of the block sections: Section -> NetBlock schema. A block is sent whole
## when any field changes, else omitted from the delta. Getters are StationBlocks'.
const BLOCKS: Dictionary = {
	StationViews.Section.STATUS:
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
	StationViews.Section.HELM:
	[
		["decoupled", "bool"],
		["throttle_setpoint", "f32"],
		["face", "bool"],
		["approach", "bool"],
		["all_stop", "bool"],
		["align", "u8"],
		["target_kind", "u8"],
		["target_ship", "s16"],
		# The selected named site (target_kind SITE), the jump spool left in ticks and its
		# target site (-1: a free mark), and the site the ship is docked at (-1: none).
		["target_site", "s16"],
		["jump_left", "u16"],
		["jump_target", "s16"],
		["docked_site", "s16"],
		["shield_focus", "v3n"],
		["shield_track", "s16"],
		# The shield ring shows Engineering's tightness too (FT-HLM-011).
		["shield_tightness", "f32"],
		["shield_power", "f32"],
		# Engineering's thrust and torque envelope scales (FT-HLM-012).
		["thrust_scale", "f32"],
		["torque_scale", "f32"],
	],
	StationViews.Section.ENGINEERING:
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
	# Science (E01): sensors, the noise preview of the selected contact, the
	# scan-position mark, the open minigame session with its puzzle, the contact cards of
	# the faction's knowledge (FT-SCI-001, FT-SCI-002) and the faction's open hack
	# windows (P7). noise_flags: bit 0 active, 1 ping, 2 probe, 3 at the mark.
	StationViews.Section.SCIENCE:
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
	# the ship's launched probes (position in m, bubble radius in m); then the
	# sim hazards the faction knows (HazardView): zone, shell or plane, where now,
	# the radius now, a plane's direction and the forecast seconds to the ship (-1: none).
	StationViews.Section.RELAY:
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
	# The main screen's status view (FT-MSC-006): each subsystem's health in
	# ShipDef.subsystems order and the ship's open objectives (Objectives.Kind, how many
	# are left). The view itself and the open cards are crew state, not sim: the
	# `main_view` event and the ping events.
	StationViews.Section.CAPTAIN:
	[
		["subsystems", ["rows", [["health", "f32"]]]],
		["objectives", ["rows", [["kind", "u8"], ["left", "u16"]]]],
	],
	StationViews.Section.MOUNTS:
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
	# What Weapons gets from other stations when a toggle lets it (FeedsView): the
	# faction's scanned weak points (bit i: subsystem i of the contact) and resistances (P7),
	# the open hack windows (P7) and the track quality of detected contacts (P8, quality is
	# the track quality (GuidanceSystem.track_quality), probe whether a deployed probe covers
	# the contact).
	StationViews.Section.FEEDS:
	[
		# Contract target flags on detected contacts, KnowledgeTable.Flag (P9).
		["flags", ["rows", [["contact", "s16"], ["flag", "u8"]]]],
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
	# The ship's open request chips (ChipsSection; NetChips on the server): the
	# chip's index in content/chips/chips.tres, its argument (mount index or contact id, -1
	# for none), the sending and receiving station (index in CREW) and the sim ticks it was
	# sent and expires at. A crew view lists the chips it sends or receives.
	# Comms' board (CommsView, CommsSection): the ship's docked site and credits,
	# the hull band (Comms' only view of condition, FT-PAIR-010), reputation per faction,
	# the cards (kind and state are StoryTable's; rep_lo/rep_hi only where rep_vis; claimer
	# the session holding the conversation, -1 for none), the open conversation nodes
	# with their replies, what the docked market sells, the modules it offers per slot
	# with the trade-in of the module now fitted, and the fitted modules.
	StationViews.Section.COMMS: COMMS,
	StationViews.Section.CHIPS:
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


## The code a block carries for a definition id (a scan trait, a hack target): a hash of the
## id, the same on server and client (ScienceView builds with it).
static func id_code(id: StringName) -> int:
	return String(id).hash()
