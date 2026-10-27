# gdlint: disable=max-public-methods
class_name ScenarioApi
extends RefCounted
## The Scenario API (FT-ARC-016, FT-DAT-009, FT-DAT-007, D64, D103): the only part of
## sim/ that the director and scenarios may name. Every query returns an id, a number, a
## string, a Vector3, a packed array or a value copy (ShipView, SiteView, EncounterView,
## CardView, ApiEvent): never a table, the world or a resource. Every write builds one
## SimCommand with source SERVER and queues it with SimWorld.submit(), so it applies at
## the next tick and lands in the command log: a replay needs neither the director nor
## the scenarios (FT-ARC-008). A write that creates a ship, card, encounter or site returns
## an ApiHandle, which resolves to the real id once the command has applied (Q24); the API
## predicts no id.

## Ticks per second, for scenarios and the director to turn seconds into ticks.
const HZ: int = SimWorld.HZ

var _world: SimWorld


func _init(world: SimWorld) -> void:
	_world = world


# --- queries (value copies) ---


func tick() -> int:
	return _world.tick


## Crewable ships in play: not AI-flown and not out of the run.
func crew_ships() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in _world.ship_count():
		if not _world.ai.is_enabled(id) and _world.run.status[id] == RunTable.Status.IN_PLAY:
			out.append(id)
	return out


## Crewable ships in play of one faction: a fleet's ships for its director (#11, M4-Q1).
func crew_ships_of(faction: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in crew_ships():
		if _world.faction_of(id) == faction:
			out.append(id)
	return out


## The session's mode, a SessionRules.Mode value (#11): the director keys on it.
func session_mode() -> int:
	return _world.rules.mode


## A ship's side (SimWorld.team_of, #11).
func team_of(id: int) -> int:
	if id < 0 or id >= _world.ship_count():
		return -1
	return _world.team_of(id)


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
	v.in_play = v.status == RunTable.Status.IN_PLAY
	v.outcome = _world.run.outcome[id]
	v.docked_site = _helm(&"docked_site", id, -1) as int
	v.jumping = (_helm(&"jump_left", id, 0.0) as float) > 0.0
	return v


func sites() -> Array[SiteView]:
	var out: Array[SiteView] = []
	for id: int in _world.sites.size():
		out.append(_site(id))
	return out


func _site(id: int) -> SiteView:
	var v: SiteView = SiteView.new()
	var t: SiteTable = _world.sites
	if id < 0 or id >= t.size():
		return v
	v.id = id
	v.key = t.key_of(id)
	v.name_key = t.name_key_of(id)
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
	# Keys an open_site queued this tick has claimed are not offered again.
	var out: PackedStringArray = PackedStringArray()
	var taken: Array[StringName] = []
	for c: SimCommand in _world.queued_commands():
		if c is OpenSiteCommand:
			taken.append((c as OpenSiteCommand).site_key)
	for key: String in _world.sites.closed_keys():
		if not taken.has(StringName(key)):
			out.append(key)
	return out


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


## The fewest and the most encounters a ship goes through, as (min, max): the RunDef's.
func encounter_limits() -> Vector2i:
	if _world.run_def == null:
		return Vector2i(1, 1)
	return Vector2i(_world.run_def.min_encounters, _world.run_def.max_encounters)


## The cards on the ship's Comms board, including its faction's (D82).
func cards_of(ship_id: int) -> Array[CardView]:
	var out: Array[CardView] = []
	var story: StoryTable = _world.story
	if ship_id < 0 or ship_id >= _world.ship_count():
		return out
	var faction: int = _world.faction_of(ship_id)
	for row: int in story.size():
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
	return _world.story_flags.get_flag(name)


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


## Straight-line distance between two ships (m), by the minimum image across the cube's seams.
func distance(a: int, b: int) -> float:
	if a < 0 or b < 0 or a >= _world.ship_count() or b >= _world.ship_count():
		return INF
	return _world.kin.relative(a, b).length()


## The map's travel legs that debris may sit on (MapDef.legs), as value copies: {from, to}
## site ids, {debris} the enemy key and {count}; legs with an end not open yet are left out.
func legs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _world.run_def == null or _world.run_def.map == null:
		return out
	for leg: Dictionary in _world.run_def.map.legs:
		var a: int = _world.sites.id_of(StringName(leg["from"]))
		var b: int = _world.sites.id_of(StringName(leg["to"]))
		if a >= 0 and b >= 0:
			out.append(
				{
					"from": a,
					"to": b,
					"debris": StringName(leg["debris"]),
					"count": int(leg["count"])
				}
			)
	return out


## A draw in [0, 1) from the stream of the scenarios' own generator. It is not part of the
## state hash: the scenarios do not run on replay, and what they decide is in the log.
func rand(stream: StringName) -> float:
	return _world.script_rng.stream(stream).randf()


# --- writes (each one queued SERVER command) ---


## Spawns an enemy `range_m` from ship `near`, at a ship-frame clock position (1 to 12, 12
## the bow) and height (0 level, 1 high, -1 low, 2 overhead, -2 under), facing it.
## Returns a handle on the new ship's id.
func spawn_at_range(
	enemy_key: StringName, faction: int, near: int, range_m: float, clock: int, height: int
) -> ApiHandle:
	var world_dir: Vector3 = _world.kin.to_world(near, _local_direction(clock, height))
	var point: PackedFloat64Array = _world.kin.point_at(near, world_dir * range_m)
	return _spawn(enemy_key, faction, point, _facing(-world_dir))


## Spawns an enemy `offset` (world axes, m) from ship `near`, at rest and unrotated: for a
## scenario that places a ship by the course of another, such as off an arriving ship's track.
## Returns a handle on the new ship's id.
func spawn_at_offset(enemy_key: StringName, faction: int, near: int, offset: Vector3) -> ApiHandle:
	return _spawn(enemy_key, faction, _world.kin.point_at(near, offset), Quaternion.IDENTITY)


## Spawns an enemy (debris) on the leg between two sites, a share `t` (0 to 1) of the way
## and `lateral_m` off the line (D234). Returns a handle on the new ship's id.
func spawn_on_leg(
	enemy_key: StringName, faction: int, from_site: int, to_site: int, t: float, lateral_m: float
) -> ApiHandle:
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


## Opens a site of the map's pool; returns a handle on its site id (resolved at once to the
## existing one when the site is already open, with nothing queued).
func open_site(site_key: StringName) -> ApiHandle:
	if _world.sites.has_key(site_key):
		return ApiHandle.new(null, _world.sites.id_of(site_key))
	var cmd: OpenSiteCommand = OpenSiteCommand.new()
	cmd.site_key = site_key
	_world.submit(cmd)
	return ApiHandle.new(cmd)


## Posts a card on the ship's Comms board; returns a handle on the card id. A crew hail
## applied in the same tick may add a card first, so only the handle knows the id.
func offer(ship_id: int, card: CardSpec) -> ApiHandle:
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
	cmd.faction_wide = card.faction_wide
	cmd.rep_faction = card.rep_faction
	cmd.site = card.site
	cmd.lane_open_s = card.lane_open_s
	cmd.lane_s = card.lane_s
	cmd.needs_subsystem = card.needs_subsystem
	cmd.needs_pips = card.needs_pips
	_world.submit(cmd)
	return ApiHandle.new(cmd)


## Settles an accepted card (FT-MIS-021, FT-MIS-019): success pays its reward and draws its
## reputation change, failure draws the "<interaction>.fail" change if there is one. The
## command is the card's own ship's; nothing is queued for a card that doesn't exist.
func settle_card(card: int, success: bool) -> void:
	if card < 0 or card >= _world.story.size():
		return
	var cmd: CardResultCommand = CardResultCommand.new()
	cmd.source = SimCommand.Source.SERVER
	cmd.ship_id = Story.audience_ship(_world, card)
	cmd.card = card
	cmd.success = success
	_world.submit(cmd)


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
			# a coarse kind also reports what it did, as kind:detail.
			for detail: String in _details(c):
				var d: ApiEvent = ApiEvent.new()
				d.tick = v.tick
				d.kind = v.kind
				d.ship_id = ship_id
				d.tag = StringName("%s:%s" % [c.kind(), detail])
				out.append(d)
	return out


## Sets the relation between two factions (a SimWorld.Relation value).
func set_relation(a: int, b: int, relation_value: int) -> void:
	var cmd: SetRelationCommand = SetRelationCommand.new()
	cmd.a = a
	cmd.b = b
	cmd.relation = relation_value
	_world.submit(cmd)


## Opens an encounter for crewed ships at a site (-1: none) charging `cost` threat points;
## returns a handle on its id (rejected when a ship is already in an encounter).
func begin_encounter(
	scenario_id: StringName, site_id: int, ship_ids: PackedInt32Array, cost: int
) -> ApiHandle:
	var cmd: BeginEncounterCommand = BeginEncounterCommand.new()
	cmd.scenario_id = scenario_id
	cmd.site = site_id
	cmd.ships = ship_ids.duplicate()
	cmd.cost = cost
	_world.submit(cmd)
	return ApiHandle.new(cmd)


## Ends an open encounter with a Scenario.Result.
func end_encounter(id: int, result: int) -> void:
	var cmd: EndEncounterCommand = EndEncounterCommand.new()
	cmd.encounter = id
	cmd.result = result
	_world.submit(cmd)


## Closes the crewed ship's run (Q4): it wins once it is in no encounter. Rejected below
## RunDef.min_encounters.
func close_run(ship_id: int) -> void:
	var cmd: CloseRunCommand = CloseRunCommand.new()
	cmd.ship = ship_id
	_world.submit(cmd)


# --- helpers ---


## What a helm_input does, for the Shakedown's steps: face, approach and each axis that is
## not at rest (throttle, strafe, lift, pitch, yaw, roll). Other commands have no detail.
static func _details(c: SimCommand) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if c.kind() != &"helm_input":
		return out
	var rotation: Vector3 = c.get("rotation")
	for pair: Array in [
		["face", c.get("face")],
		["approach", c.get("approach")],
		["throttle", c.get("throttle") != 0.0],
		["strafe", c.get("strafe") != 0.0],
		["lift", c.get("lift") != 0.0],
		["pitch", rotation.x != 0.0],
		["yaw", rotation.y != 0.0],
		["roll", rotation.z != 0.0],
	]:
		if pair[1]:
			out.append(pair[0])
	return out


func _spawn(
	enemy_key: StringName, faction: int, point: PackedFloat64Array, rot: Quaternion
) -> ApiHandle:
	var cmd: SpawnShipCommand = SpawnShipCommand.new()
	cmd.enemy_key = enemy_key
	cmd.faction = faction
	cmd.x = point[0]
	cmd.y = point[1]
	cmd.z = point[2]
	cmd.rot = rot
	_world.submit(cmd)
	return ApiHandle.new(cmd)


## Unit vector in the ship frame (-Z bow, +X starboard, +Y up) for a clock and height.
static func _local_direction(clock: int, height: int) -> Vector3:
	var bearing: float = deg_to_rad(30.0 * (clock % 12))
	var elevation: float = deg_to_rad([-75.0, -35.0, 0.0, 35.0, 75.0][clampi(height, -2, 2) + 2])
	return Vector3(sin(bearing) * cos(elevation), sin(elevation), -cos(bearing) * cos(elevation))


## A rotation whose bow (-Z) points along `dir`.
static func _facing(dir: Vector3) -> Quaternion:
	var up: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(dir.normalized(), up).get_rotation_quaternion()


## A HelmTable column value for the ship, or `fallback` while the column does not exist.
func _helm(column: StringName, id: int, fallback: Variant) -> Variant:
	var col: Variant = _world.helm.get(column)
	return col[id] if col != null else fallback
