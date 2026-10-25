extends GdUnitTestSuite
## L3 schema tests of the per-station snapshot filter (T042): real snapshots from a
## server over loopback, decoded section by section, hold nothing outside the
## receiver's StationDef, at every difficulty-toggle set, and nothing of another
## faction's knowledge.

const PLAYER: int = NetHarness.PLAYER
const ENEMY: int = NetHarness.ENEMY

const S = StationViews.Section

## Sections each entry must and must not receive, by hand from docs/spec/05-stations.md
## (not from StationViews): entry -> [required, forbidden].
const SPEC_05: Dictionary = {
	# Cockpit with HUD and shield ring, claims flight and shield facing (FT-HLM-001,
	# FT-HLM-008, FT-NET-022); no mounts or Engineering's tables.
	"helm":
	[
		[S.KIN, S.STATUS, S.CONTACTS, S.HELM, S.NEAR, S.PROJECTILES, S.OWNERSHIP],
		[S.ENGINEERING, S.MOUNTS],
	],
	# Turret camera, every mount with its state and claimer (FT-WPN-001, FT-WPN-004).
	"weapons":
	[
		[S.KIN, S.STATUS, S.CONTACTS, S.MOUNTS, S.NEAR, S.PROJECTILES, S.OWNERSHIP],
		[S.HELM, S.ENGINEERING],
	],
	# Cutaway, pips, repairs; no threat positions beyond the radar (FT-ENG-001 to
	# FT-ENG-007).
	"engineering":
	[
		[S.KIN, S.STATUS, S.CONTACTS, S.ENGINEERING, S.RELAY, S.OWNERSHIP],
		[S.HELM, S.MOUNTS, S.NEAR, S.PROJECTILES],
	],
	# M1 has only their definitions: top bar and disc radar (FT-STN-001, FT-STN-002).
	"science":
	[
		[S.KIN, S.STATUS, S.CONTACTS, S.SCIENCE, S.RELAY, S.OWNERSHIP],
		[S.HELM, S.MOUNTS, S.ENGINEERING]
	],
	# Probes, coverage, lanes and the probe-launcher claim (FT-RLY-004, FT-NET-022).
	"relay":
	[[S.KIN, S.STATUS, S.CONTACTS, S.RELAY, S.OWNERSHIP], [S.HELM, S.MOUNTS, S.ENGINEERING]],
	"comms": [[S.KIN, S.STATUS, S.CONTACTS], [S.HELM, S.MOUNTS, S.ENGINEERING, S.OWNERSHIP]],
	# Main-screen mirror and the read-only main screen: no ship controls (FT-CPT-003,
	# FT-MSC-004).
	"captain":
	[[S.KIN, S.STATUS, S.CONTACTS, S.NEAR, S.PROJECTILES], [S.HELM, S.MOUNTS, S.OWNERSHIP]],
	"viewer":
	[[S.KIN, S.STATUS, S.CONTACTS, S.NEAR, S.PROJECTILES], [S.HELM, S.MOUNTS, S.OWNERSHIP]],
}
## Fields the spec names: [entry, block, fields, rows field, row fields].
const SPEC_05_FIELDS: Array = [
	# Top bar: hull and shields (5.0).
	["comms", S.STATUS, ["hull", "shields"]],
	# Shield ring: Helm's focus, Engineering's tightness (FT-HLM-011); propellant (FT-HLM-012).
	["helm", S.HELM, ["shield_focus", "shield_tightness"]],
	["helm", S.STATUS, ["propellant"]],
	# Subsystem table with health, heat and pips; spare parts; shield power and tightness
	# (FT-ENG-001, FT-ENG-002, FT-ENG-003, FT-ENG-005).
	[
		"engineering",
		S.ENGINEERING,
		["spare_parts", "shield_strength", "shield_tightness", "subsystems"],
		"subsystems",
		["health", "heat", "pips"],
	],
	# Every mount with ready, heat and ammo (FT-WPN-004).
	["weapons", S.MOUNTS, ["mounts"], "mounts", ["cooldown", "heat", "ammo"]],
	# Probe stock, fabrication and the lane switch (FT-RLY-004, FT-RLY-011).
	["relay", S.RELAY, ["stock", "fab_left", "lanes", "probes"]],
]
var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## [kind, payload] of each section of a snapshot message, and its full flag.
static func _sections(data: PackedByteArray) -> Array:
	var out: Array = []
	var n: int = data[SnapshotBuilder.HEADER_BYTES - 1]
	var at: int = SnapshotBuilder.HEADER_BYTES
	for i: int in n:
		var kind: int = data[at]
		var size: int = data.decode_u16(at + 1)
		out.append([kind, data.slice(at + 3, at + 3 + size)])
		at += 3 + size
	return out


## Checks every kept snapshot of a client against its entry's StationDef; returns the
## number checked.
func _check_snapshots(c: NetClient, entry: String) -> int:
	var d: StationDef = StationViews.def(entry)
	var checked: int = 0
	for seq: int in c.raw_snapshots:
		var data: PackedByteArray = c.raw_snapshots[seq]
		var kinds: Array[int] = []
		for part: Array in _sections(data):
			var kind: int = part[0]
			kinds.append(kind)
			(
				assert_array(d.sections)
				. override_failure_message("%s got section %d" % [entry, kind])
				. contains([kind])
			)
			if StationViews.BLOCKS.has(kind):
				var block: Dictionary = NetBlock.decode(StationViews.BLOCKS[kind], part[1])
				assert_array(block.keys()).is_equal(d.fields[kind])
			if kind == StationViews.Section.OWNERSHIP:
				var table: Dictionary = OwnershipSection.read(part[1])
				assert_dict(table).is_not_empty()
				for group: String in ["claims", "writers"]:
					for item: String in table[group]:
						(
							assert_array(d.stations)
							. override_failure_message("%s saw %s" % [entry, item])
							. contains([StationViews.station_of_item(item)])
						)
		if SnapshotBuilder.peek(data)[1]:
			assert_array(kinds).is_equal(d.sections)
		checked += 1
	return checked


# FT: FT-NET-009, FT-PAIR-005, FT-TST-010, FT-NET-008, FT-ARC-014
# One client per catalogue entry (the dev entry included) on a running ship with
# claims, last writers, shots and helm input in play: every full snapshot holds exactly
# the entry's sections, every delta a subset, each block exactly its field set, and the
# OWNERSHIP section only the entry's own stations' items; at each difficulty-toggle set
# (M1 has no toggle-gated field, so the sets share one filter and differ only in the
# view key, which is what this checks for the toggle plumbing).
func test_snapshots_hold_only_their_station_fields() -> void:
	var server: NetServer = h.server(true)
	var ids: Array[String] = StationViews.catalogue_ids(true)
	var clients: Dictionary = {}
	for id: String in ids:
		var c: NetClient = await h.joined(server, id, id)
		assert_bool(c.view.full_count >= 1).is_true()
		clients[id] = c
	server.session.launch(PLAYER)
	var pilot: NetClient = clients["helm"]
	var systems: NetClient = clients["systems"]
	pilot.helm(1.0, Vector3(0.1, 0.0, 0.0))
	systems.set_pips(SubsystemDef.Kind.ENGINES, 2)
	(clients["weapons"] as NetClient).claim("mount:0")
	var wrote: Callable = func() -> bool:
		return server.session.writers.get(PLAYER, {}).has("pips:%d" % SubsystemDef.Kind.ENGINES)
	assert_bool(await h.until(wrote)).is_true()
	for toggles: String in StationViews.TOGGLE_SETS:
		var fulls: Dictionary = {}
		for id: String in ids:
			var c: NetClient = clients[id]
			c.keep_raw = true
			c.raw_snapshots = {}
			fulls[id] = c.view.full_count
			var s: NetSession = h.session_of(server, c)
			s.toggles = toggles
			server.transport.set_view(s.id, s.view_key())
			assert_str(s.view_key()).is_equal(StationViews.key(PLAYER, id, toggles))
		var all_full: Callable = func() -> bool:
			return ids.all(func(id: String) -> bool: return clients[id].view.full_count > fulls[id])
		assert_bool(await h.until(all_full)).is_true()
		(clients["weapons"] as NetClient).fire()
		pilot.helm(0.5)
		await h.wait(500)
		for id: String in ids:
			var c: NetClient = clients[id]
			assert_int(c.view.rejected).is_equal(0)
			assert_int(_check_snapshots(c, id)).is_greater(3)
	# The checks above derive what to expect from the same StationViews tables that
	# build the snapshots, so a wrong table passes them. These are written by hand from
	# docs/spec/05-stations.md instead.
	for id: String in SPEC_05:
		var kinds: Array[int] = clients[id].view.kinds
		var row: Array = SPEC_05[id]
		assert_array(kinds).override_failure_message("%s lacks %s" % [id, row[0]]).contains(row[0])
		(
			assert_array(kinds)
			. override_failure_message("%s got one of %s" % [id, row[1]])
			. not_contains(row[1])
		)
	for want: Array in SPEC_05_FIELDS:
		var block: Dictionary = clients[want[0]].view.blocks[want[1]]
		assert_array(block.keys()).contains(want[2])
		if want.size() > 3:
			var rows: Array = block[want[3]]
			assert_array(rows).is_not_empty()
			assert_array((rows[0] as Dictionary).keys()).contains(want[4])
	assert_dict(clients["viewer"].view.ownership).is_empty()
	# Weapons sees the mount's claimer, Engineering the pips' last writer.
	assert_array(clients["weapons"].view.ownership["claims"]["mount:0"]).is_equal(
		[h.session_of(server, clients["weapons"]).id, "weapons"]
	)
	var pips: String = "pips:%d" % SubsystemDef.Kind.ENGINES
	assert_str(clients["engineering"].view.ownership["writers"][pips][1]).is_equal("systems")
	assert_bool(clients["weapons"].view.ownership["writers"].has(pips)).is_false()


# FT: FT-NET-010, FT-PAIR-005, FT-TST-010
# Two crewed ships of hostile factions: each client's contacts are exactly its own
# faction's knowledge (who it detects, its callsigns, its own-faction flags), and sim
# events reach only the event's faction, and within it only the stations that see the
# kind; an event of no ship reaches nobody.
func test_no_knowledge_of_another_faction() -> void:
	var server: NetServer = h.server()
	var world: SimWorld = server.world
	world.ai.enabled[ENEMY] = 0
	for i: int in 240:
		world.step()
	world.drain_events()
	# Both detect each other by now, so each list is the faction's own view of two ships.
	assert_bool(KnowledgeSystem.is_detected(world, world.faction_of(PLAYER), ENEMY)).is_true()
	var helm: NetClient = await h.joined(server, "a_helm", "helm")
	var eng: NetClient = await h.joined(server, "a_eng", "engineering")
	var viewer: NetClient = await h.joined(server, "a_viewer", "viewer")
	var foe: NetClient = await h.joined(server, "b_helm", "helm", ENEMY)
	assert_bool(foe.view.full_count >= 1).is_true()
	await h.wait(200)
	for pair: Array in [[helm, PLAYER], [foe, ENEMY]]:
		var c: NetClient = pair[0]
		var faction: int = world.faction_of(pair[1])
		var known: Array = Array(ContactsSection.known(world, faction))
		var got: Array = (c.view.contacts["model"] as Dictionary).keys()
		got.sort()
		assert_array(got).is_equal(known)
		for id: int in known:
			assert_str(c.view.callsign(id)).is_equal(KnowledgeSystem.callsign(world, faction, id))
			var own: bool = c.view.contacts["info"][id][0] & ContactsSection.FLAG_OWN != 0
			assert_bool(own).is_equal(world.faction_of(id) == faction)
	var marks: Array = [h.mark(helm), h.mark(eng), h.mark(viewer), h.mark(foe)]
	var made: Array[SimEvent] = [
		_event(world, &"hit", PLAYER, &"a_hit"),
		_event(world, &"repair_started", PLAYER, &"a_repair"),
		_event(world, &"contact_lost", -1, &"nobody"),
		_event(world, &"hit", ENEMY, &"b_hit"),
		_event(world, &"ai_mode", ENEMY, &"ai"),
	]
	server.session.after_ticks(made)
	var expect: Array = [
		[helm, ["a_hit"]], [eng, ["a_hit", "a_repair"]], [viewer, ["a_hit"]], [foe, ["b_hit"]]
	]
	assert_bool(await h.until(func() -> bool: return _tags(foe, marks[3]).size() >= 1)).is_true()
	assert_bool(await h.until(func() -> bool: return _tags(eng, marks[1]).size() >= 2)).is_true()
	await h.wait(300)
	for i: int in expect.size():
		assert_array(_tags(expect[i][0], marks[i])).is_equal(expect[i][1])


func _event(world: SimWorld, kind: StringName, ship: int, tag: StringName) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.tick = world.tick
	e.kind = kind
	e.ship_id = ship
	e.faction = world.faction_of(ship) if ship >= 0 else -1
	e.tag = tag
	return e


## Tags of the sim events (payload with a tag) the client got since index from.
func _tags(c: NetClient, from: int) -> Array:
	var out: Array = []
	var seen: Array = h.events[c]
	for i: int in range(from, seen.size()):
		var payload: Dictionary = seen[i]["payload"]
		if payload.has("tag") and payload.has("faction"):
			out.append(payload["tag"])
	return out
