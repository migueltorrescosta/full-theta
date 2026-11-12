class_name StationBlocks
extends RefCounted
## The server's side of the station views (F4, R13-8): the block builders that read a
## (copied) world, the claimable items of a ship and the item a command acts on. The clients
## never name it; StationCatalogue is the station model and BlockSchema the wire schema.


## The claimable items of a ship by station: flight and shield facing (Helm), one per
## weapon mount (Weapons), one per repair crew (Engineering), the scan (Science).
static func claim_items(world: SimWorld, ship: int) -> Dictionary:
	var ship_def: ShipDef = world.defs[ship]
	var mounts: Array[String] = []
	for i: int in ship_def.mounts.size():
		mounts.append("%s:%d" % [StationCatalogue.CLAIM_MOUNT, i])
	var crews: Array[String] = []
	for i: int in ship_def.repair_crews:
		crews.append("%s:%d" % [StationCatalogue.CLAIM_CREW, i])
	var helm: Array[String] = [StationCatalogue.CLAIM_FLIGHT, StationCatalogue.CLAIM_SHIELD_FACING]
	return {
		"comms": CommsSection.npc_items(world, ship),
		"helm": helm,
		"weapons": mounts,
		"engineering": crews,
		"science": [StationCatalogue.CLAIM_SCAN],
		"relay": [StationCatalogue.CLAIM_PROBE],
	}


## The claim item or ship-wide control a command acts on ("mount:1", "flight",
## "pips:2"), or "" for a command with neither.
static func item_of(command: SimCommand) -> String:
	var spec: Array = StationCatalogue.COMMAND_ITEMS.get(command.kind(), [])
	if spec.is_empty():
		return ""
	if spec[1] == "":
		return spec[0]
	return "%s:%d" % [spec[0], int(command.get(spec[1]))]


## The block section's fields for a ship, read from a (copied) world, encoded.
static func block_bytes(
	kind: int, world: SimWorld, ship: int, filter: ShortcutFilter = null
) -> PackedByteArray:
	var values: Dictionary = _block_values(kind, world, ship, filter)
	if filter != null:
		filter.apply(kind, values, world.defs[ship])
	return NetBlock.encode(BlockSchema.BLOCKS[kind], values)


## `filter` lets a block skip the lists it would blank (ShortcutFilter.apply fixes the rest).
static func _block_values(
	kind: int, world: SimWorld, ship: int, filter: ShortcutFilter = null
) -> Dictionary:
	match kind:
		StationCatalogue.Section.STATUS:
			return _status(world, ship)
		StationCatalogue.Section.HELM:
			return _helm(world, ship)
		StationCatalogue.Section.ENGINEERING:
			return _engineering(world, ship)
		StationCatalogue.Section.SCIENCE:
			return ScienceSection.block(world, ship)
		StationCatalogue.Section.RELAY:
			return _relay(world, ship, filter)
		StationCatalogue.Section.CAPTAIN:
			return _captain(world, ship)
		StationCatalogue.Section.FEEDS:
			return FeedsSection.block(world, ship, filter)
		StationCatalogue.Section.COMMS:
			return CommsSection.block(world, ship)  # (the builder adds claims, filter)
	return _mounts(world, ship)


static func _status(world: SimWorld, ship: int) -> Dictionary:
	var hull_row: int = world.damage.rows_of(ship)[0]
	var pips: int = 0
	for r: int in world.damage.rows_of(ship):
		pips += world.damage.pips[r]
	return {
		"alive": world.kin.is_alive(ship),
		"status": world.ships.status[ship],
		"outcome": world.ships.ship_outcome[ship],
		"hull": world.damage.health[hull_row],
		"shields": world.shields.strength[ship],
		"pips_used": pips,
		"pip_cap": PowerSystem.pip_cap(world, ship),
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
		"sel_kind": h.sel_kind[ship],
		"sel_contact": h.sel_contact[ship],
		"sel_site": h.sel_site[ship],
		"jump_left": mini(h.jump_left[ship], 65535),
		"jump_target": h.jump_target[ship],
		"docked_site": h.docked_site[ship],
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
static func _relay(world: SimWorld, ship: int, filter: ShortcutFilter = null) -> Dictionary:
	var r: RelayTable = world.relay
	var t: ProbeTable = world.probes
	var rows: PackedInt32Array = t.rows_of(ship)
	var probes: Array = []
	for i: int in range(maxi(0, rows.size() - StationCatalogue.RELAY_PROBE_ROWS), rows.size()):
		var p: int = rows[i]
		(
			probes
			. append(
				{
					"serial": t.serial[p],
					"deployed": t.deployed[p] == 1,
					"pos": Vector3(t.pos_x[p], t.pos_y[p], t.pos_z[p]),
					"range": world.defs[ship].probe_range,
				}
			)
		)
	return {
		"stock": r.stock[ship],
		"fab_left": r.fab_left[ship],
		"lanes": r.lanes_flagged[ship] == 1,
		"probes": probes,
		"hazards":
		HazardRows.rows(world, ship) if filter == null or filter.hazards_visible() else [],
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
