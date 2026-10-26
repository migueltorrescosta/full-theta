# gdlint: disable=max-public-methods
class_name ScenarioApi
extends RefCounted
## The Scenario API (FT-ARC-016, FT-DAT-009, FT-DAT-007, D64, D103): the only part of
## sim/ that the director and scenarios may name. Every query returns an id, a number, a
## string, a Vector3, a packed array or a value copy (ShipView, SiteView, EncounterView,
## CardView, ApiEvent): never a table, the world or a resource. Every write builds one
## SimCommand with source SERVER and queues it with SimWorld.submit(), so it applies at
## the next tick and lands in the command log: a replay needs neither the director nor
## the scenarios (FT-ARC-008). Writes return the id the new thing will get, or nothing.
##
## An instance serves one encounter (encounter_id) or the director (-1).

## Ticks per second, for scenarios and the director to turn seconds into ticks.
const HZ: int = SimWorld.HZ

var _world: SimWorld
var _encounter: int


func _init(world: SimWorld, encounter_id: int = -1) -> void:
	_world = world
	_encounter = encounter_id


## The encounter this view serves, or -1 for the director's.
func encounter_id() -> int:
	return _encounter


## A view of the same world for one encounter's scenario.
func for_encounter(id: int) -> ScenarioApi:
	return ScenarioApi.new(_world, id)


# --- queries (value copies) ---


func tick() -> int:
	return _world.tick


## Every ship id.
func ships() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in _world.ship_count():
		out.append(id)
	return out


## Crewable ships in play: not AI-flown and not out of the run.
func crew_ships() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in _world.ship_count():
		if not _world.ai.is_enabled(id) and _world.run.status[id] == RunTable.Status.IN_PLAY:
			out.append(id)
	return out


func ship(id: int) -> ShipView:
	var v: ShipView = ShipView.new()
	if id < 0 or id >= _world.ship_count():
		return v
	v.id = id
	v.faction = _world.faction_of(id)
	v.pos = _world.kin.point_at(id, Vector3.ZERO)
	v.velocity = _world.kin.vel[id]
	v.nearest_site = SiteTable.nearest(_world, id)
	v.at_site = SiteTable.at_site(_world, id)
	v.hull_frac = DamageSystem.hull_fraction(_world, id)
	v.status = _world.run.status[id]
	v.outcome = _world.run.outcome[id]
	v.docked_site = _helm(&"docked_site", id, -1) as int
	v.jumping = (_helm(&"jump_left", id, 0.0) as float) > 0.0
	return v


func sites() -> Array[SiteView]:
	var out: Array[SiteView] = []
	for id: int in _world.sites.size():
		out.append(site(id))
	return out


func site(id: int) -> SiteView:
	var v: SiteView = SiteView.new()
	var t: SiteTable = _world.sites
	if id < 0 or id >= t.size():
		return v
	v.id = id
	v.key = t.key_of(id)
	v.name_key = _world.site_names.get(id, "")
	v.kind = t.kind_of(id)
	v.pos = t.point(id)
	v.radius_m = t.radius[id]
	v.dockable = t.dockable_of(id)
	for f: int in 32:
		if (t.known_mask[id] >> f) & 1 == 1:
			v.known_by.append(f)
	return v


## Site keys of the map's pool the director has not opened yet.
func spawnable_sites() -> PackedStringArray:
	return _world.sites.closed_keys()


func encounter(id: int) -> EncounterView:
	var v: EncounterView = EncounterView.new()
	var t: EncounterTable = _world.encounters
	if id < 0 or id >= t.size():
		return v
	var ix: int = t.scenario_ix[id]
	v.id = id
	v.scenario_id = StringName(_world.scenario_ids[ix]) if ix < _world.scenario_ids.size() else &""
	v.site = t.site[id]
	for ship_id: int in EncounterTable.MAX_SHIP_BITS:
		if EncounterTable.has_bit(t.ships_mask[id], ship_id):
			v.ships.append(ship_id)
	v.result = t.result[id]
	v.start_tick = t.start_tick[id]
	v.end_tick = t.end_tick[id]
	v.cost = t.cost[id]
	return v


## Encounters opened so far (ids 0 to count - 1).
func encounter_count() -> int:
	return _world.encounters.size()


## The cards on the ship's Comms board, including its faction's (D82). Empty until the STORY
## table exists (strand C).
func cards_of(ship_id: int) -> Array[CardView]:
	var out: Array[CardView] = []
	var story: Variant = _world.get(&"story")
	if story == null or ship_id < 0 or ship_id >= _world.ship_count():
		return out
	var faction: int = _world.faction_of(ship_id)
	for row: int in (story.ship_ids as PackedInt32Array).size():
		var owner: int = story.ship_ids[row]
		if owner != ship_id and not (owner == -1 and story.factions[row] == faction):
			continue
		var v: CardView = CardView.new()
		v.id = row
		v.kind = story.kind[row]
		v.state = story.state[row]
		v.npc_id = story.npc[row]
		v.title_key = story.title[row]
		v.expires_tick = story.expires_tick[row]
		v.reward = story.reward[row]
		v.target = story.target[row]
		out.append(v)
	return out


## The story flag's value, 0 when unset.
func flag(name: StringName) -> int:
	return _world.encounters.get_flag(name)


## How much the faction knows of the contact: 0 never detected, 1 detected, 2 identified,
## 3 scanned.
func knows(faction: int, contact: int) -> int:
	var k: KnowledgeTable = _world.knowledge
	var row: int = k.row_for(faction, contact)
	if row < 0:
		return 0
	if k.scan_conf[row] > 0.0:
		return 3
	if k.identified[row] == 1:
		return 2
	return 1 if k.detected[row] == 1 else 0


## SimWorld.Relation between two factions as an int.
func relation(a: int, b: int) -> int:
	return _world.relation(a, b)


## The events of the latest step, copied.
func events() -> Array[ApiEvent]:
	var out: Array[ApiEvent] = []
	for e: SimEvent in _world.step_events:
		var v: ApiEvent = ApiEvent.new()
		v.tick = e.tick
		v.kind = e.kind
		v.ship_id = e.ship_id
		v.other_id = e.other_id
		v.value = e.value
		v.tag = e.tag
		out.append(v)
	return out


## The id a ship spawned by a command queued now will get (spawns apply in queue order).
func next_ship_id() -> int:
	return _world.ship_count() + _queued(&"spawn_ship")


## A draw in [0, 1) from the stream of the scenarios' own generator. It is not part of the
## state hash: the scenarios do not run on replay, and what they decide is in the log.
func rand(stream: StringName) -> float:
	return _world.script_rng.stream(stream).randf()


# --- writes (each one queued SERVER command) ---


## Spawns an enemy `range_m` from ship `near`, at a ship-frame clock position (1 to 12, 12
## the bow) and height (0 level, 1 high, -1 low, 2 overhead, -2 under), facing it.
## Returns the new ship's id.
func spawn_at_range(
	enemy_key: StringName, faction: int, near: int, range_m: float, clock: int, height: int
) -> int:
	var world_dir: Vector3 = _world.kin.to_world(near, _local_direction(clock, height))
	var point: PackedFloat64Array = _world.kin.point_at(near, world_dir * range_m)
	return _spawn(enemy_key, faction, point, _facing(-world_dir))


## Spawns an enemy at `offset` from a site's point. Returns the new ship's id.
func spawn_at_site(enemy_key: StringName, faction: int, site_id: int, offset: Vector3) -> int:
	var p: PackedFloat64Array = _world.sites.point(site_id)
	return _spawn(
		enemy_key,
		faction,
		PackedFloat64Array([p[0] + offset.x, p[1] + offset.y, p[2] + offset.z]),
		Quaternion.IDENTITY
	)


## Spawns an enemy (debris) on the leg between two sites, a share `t` (0 to 1) of the way
## and `lateral_m` off the line (D233). Returns the new ship's id.
func spawn_on_leg(
	enemy_key: StringName, faction: int, from_site: int, to_site: int, t: float, lateral_m: float
) -> int:
	var a: PackedFloat64Array = _world.sites.point(from_site)
	var b: PackedFloat64Array = _world.sites.point(to_site)
	var kin: Kinematics = _world.kin
	var leg: Vector3 = Vector3(kin.wrap(b[0] - a[0]), kin.wrap(b[1] - a[1]), kin.wrap(b[2] - a[2]))
	var side: Vector3 = leg.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = leg.cross(Vector3.RIGHT)
	var off: Vector3 = leg * t + side.normalized() * lateral_m
	return _spawn(
		enemy_key,
		faction,
		PackedFloat64Array([a[0] + off.x, a[1] + off.y, a[2] + off.z]),
		Quaternion.IDENTITY
	)


## Opens a site of the map's pool; returns its site id (the existing one when already open,
## with nothing queued).
func open_site(site_key: StringName) -> int:
	if _world.sites.has_key(site_key):
		return _world.sites.open(_world, site_key)
	var id: int = _world.sites.size() + _queued(&"open_site")
	var cmd: OpenSiteCommand = OpenSiteCommand.new()
	cmd.site_key = site_key
	_world.submit(cmd)
	return id


## Posts a card on the ship's Comms board; returns the card id it will get.
func offer(ship_id: int, card: CardSpec) -> int:
	var id: int = _card_count() + _queued(&"post_card")
	var cmd: PostCardCommand = PostCardCommand.new()
	cmd.source = SimCommand.Source.SERVER
	cmd.ship_id = ship_id
	cmd.card_kind = card.kind
	cmd.npc_id = card.npc_id
	cmd.title_key = card.title_key
	cmd.detail_key = card.detail_key
	cmd.conversation_id = card.conversation_id
	cmd.reward_credits = card.reward_credits
	cmd.rep_interaction = card.rep_interaction
	cmd.target = card.target
	cmd.target_flag = card.target_flag
	cmd.expires_s = card.expires_s
	cmd.requires_docked = card.requires_docked
	_world.submit(cmd)
	return id


## Says a dialogue line to a ship (an NPC's, or the ship computer's for some stations).
## Nothing is queued when no ship can hear it.
func message(line_id: String, args: Dictionary, to: SayTarget) -> void:
	var ship_id: int = to.ship
	if ship_id < 0:
		var crew: PackedInt32Array = crew_ships()
		if crew.is_empty():
			return
		ship_id = crew[0]
	var cmd: SayCommand = SayCommand.new()
	cmd.ship_id = ship_id
	cmd.line_id = line_id
	cmd.npc_id = String(to.npc_id)
	cmd.stations = Array(to.stations)
	cmd.args = args.duplicate(true)
	_world.submit(cmd)


func set_flag(name: StringName, value: int) -> void:
	var cmd: SetFlagCommand = SetFlagCommand.new()
	cmd.flag_name = name
	cmd.value = value
	_world.submit(cmd)


## The crew commands the ship's stations had accepted in the latest step, as events with
## the command kind as kind and tag (Shakedown steps advance on them).
func commands_this_tick(ship_id: int) -> Array[ApiEvent]:
	var out: Array[ApiEvent] = []
	for c: SimCommand in _world.command_log.slice(_world.step_log_from):
		if c.accepted and c.source == SimCommand.Source.CREW and c.ship_id == ship_id:
			var v: ApiEvent = ApiEvent.new()
			v.tick = c.tick
			v.kind = c.kind()
			v.ship_id = ship_id
			v.tag = c.kind()
			out.append(v)
	return out


## Sets the relation between two factions (a SimWorld.Relation value).
func set_relation(a: int, b: int, relation_value: int) -> void:
	var cmd: SetRelationCommand = SetRelationCommand.new()
	cmd.a = a
	cmd.b = b
	cmd.relation = relation_value
	_world.submit(cmd)


## Puts a contract flag (KnowledgeTable.Flag) on a contact in a faction's knowledge
## (FT-MIS-042). Nothing is queued for a faction with no ship.
func set_contract_flag(faction: int, contact: int, flag_value: int) -> void:
	var holder: int = _first_ship_of(faction)
	if holder < 0:
		return
	var cmd: SetContractFlagCommand = SetContractFlagCommand.new()
	cmd.source = SimCommand.Source.SERVER
	cmd.ship_id = holder
	cmd.faction = faction
	cmd.contact = contact
	cmd.flag = flag_value
	_world.submit(cmd)


## Opens an encounter for crewed ships at a site (-1: none) charging `cost` threat points;
## returns the id it will get.
func begin_encounter(
	scenario_id: StringName, site_id: int, ship_ids: PackedInt32Array, cost: int
) -> int:
	var id: int = _world.encounters.size() + _queued(&"begin_encounter")
	var cmd: BeginEncounterCommand = BeginEncounterCommand.new()
	cmd.scenario_id = scenario_id
	cmd.site = site_id
	cmd.ships = ship_ids.duplicate()
	cmd.cost = cost
	_world.submit(cmd)
	return id


## Ends an open encounter with a Scenario.Result.
func end_encounter(id: int, result: int) -> void:
	var cmd: EndEncounterCommand = EndEncounterCommand.new()
	cmd.encounter = id
	cmd.result = result
	_world.submit(cmd)


# --- helpers ---


func _spawn(enemy_key: StringName, faction: int, point: PackedFloat64Array, rot: Quaternion) -> int:
	var id: int = next_ship_id()
	var cmd: SpawnShipCommand = SpawnShipCommand.new()
	cmd.enemy_key = enemy_key
	cmd.faction = faction
	cmd.x = point[0]
	cmd.y = point[1]
	cmd.z = point[2]
	cmd.rot = rot
	_world.submit(cmd)
	return id


## Unit vector in the ship frame (-Z bow, +X starboard, +Y up) for a clock and height.
static func _local_direction(clock: int, height: int) -> Vector3:
	var bearing: float = deg_to_rad(30.0 * (clock % 12))
	var elevation: float = deg_to_rad([-75.0, -35.0, 0.0, 35.0, 75.0][clampi(height, -2, 2) + 2])
	return Vector3(sin(bearing) * cos(elevation), sin(elevation), -cos(bearing) * cos(elevation))


## A rotation whose bow (-Z) points along `dir`.
static func _facing(dir: Vector3) -> Quaternion:
	var up: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(dir.normalized(), up).get_rotation_quaternion()


func _queued(kind: StringName) -> int:
	var n: int = 0
	for c: SimCommand in _world.queued_commands():
		if c.kind() == kind:
			n += 1
	return n


func _card_count() -> int:
	var story: Variant = _world.get(&"story")
	return (story.size() as int) if story != null else 0


func _first_ship_of(faction: int) -> int:
	for id: int in _world.ship_count():
		if _world.faction_of(id) == faction:
			return id
	return -1


## A HelmTable column value for the ship, or `fallback` while the column does not exist
## (strand B adds docked_site and jump_left).
func _helm(column: StringName, id: int, fallback: Variant) -> Variant:
	var col: Variant = _world.helm.get(column)
	return col[id] if col != null else fallback
