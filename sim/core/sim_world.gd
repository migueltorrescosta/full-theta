class_name SimWorld
extends RefCounted
## The authoritative simulation (FT-ARC-004): steps at a fixed 60 Hz from its own
## accumulator (FT-ARC-006), iterates ships in id order (FT-ARC-009) and draws every
## random number from per-subsystem seeded streams (FT-ARC-008). All per-ship state
## lives in SimTable containers keyed by ship id and faction (FT-ARC-012); ship ids are
## dense and equal the row of every per-ship table. Definitions arrive already loaded
## and are only read (FT-ARC-020). Pure: no Node, SceneTree, I/O or loading.

enum Relation { FRIENDLY, NEUTRAL, HOSTILE }

const HZ: int = 60
const DT: float = 1.0 / HZ
## The cube's period must be at least this many times the longest sensor range
## (FT-SIM-035, D124, D229).
const PERIOD_PER_SENSOR_RANGE: int = PeriodRules.PERIOD_PER_SENSOR_RANGE
## Most broadphase cells per axis (2^20), so CollisionSystem's int cell keys
## stay below 2^60: a period of at most 2^20 * CollisionSystem.CELL (262 144 km).
const MAX_CELLS_PER_AXIS: int = PeriodRules.MAX_CELLS_PER_AXIS
## Most ticks one advance() runs; a longer stall drops time instead of spiralling.
const MAX_TICKS_PER_ADVANCE: int = 8

## Ticks completed; commands and events of the tick being stepped carry this number.
var tick: int = 0
var seed_value: int = 0
var build_id: String = ""
var rng: SimRng
## Definitions by ship id, read-only (FT-ARC-020).
var defs: Array[ShipDef] = []

var kin: Kinematics = Kinematics.new()
var helm: HelmTable = HelmTable.new()
var power: PowerTable = PowerTable.new()
var shields: ShieldTable = ShieldTable.new()
var mounts: MountTable = MountTable.new()
var projectiles: ProjectileTable = ProjectileTable.new()
var damage: DamageTable = DamageTable.new()
var knowledge: KnowledgeTable = KnowledgeTable.new()
## Enemy AI state (T035); rows of ships spawned with spawn_enemy are enabled.
var ai: AiTable = AiTable.new()
## Run state: each ship's status and the encounter outcome (T036, FT-MIS-017).
var run: RunTable = RunTable.new()
## Science state and open hack windows (E01).
var science: ScienceTable = ScienceTable.new()
var hacks: HackTable = HackTable.new()
## Science tuning, read-only (FT-ARC-020); null disables the Science commands. The
## encounter passes it in (M1Encounter.science).
var science_def: ScienceDef
# --- Relay's stock, launched probes and lane flags (#9). ---
var relay: RelayTable = RelayTable.new()
var probes: ProbeTable = ProbeTable.new()
## The world's hazards, read-only like defs (FT-ARC-020, D208), and which fronts have
## crossed each ship. Empty: none. At most HazardSystem.MAX_HAZARDS (checked by the encounter).
var hazards: Array[HazardDef] = []
var hazard_state: HazardTable = HazardTable.new()
## STORY and the economy (#10, FT-COM-001 to FT-COM-009, FT-MIS-018 to FT-MIS-022).
var story: StoryTable = StoryTable.new()
var story_flags: StoryFlagTable = StoryFlagTable.new()
var economy: EconomyTable = EconomyTable.new()
var reputation: ReputationTable = ReputationTable.new()
var modules: ModuleTable = ModuleTable.new()
## Each ship's definition before any module (defs[id] is the one with them fitted).
var base_defs: Array[ShipDef] = []
## Read-only scenario data like defs, filled by app/: conversations by id (parsed
## content/conversations/*.json), the conversation each ShipDef id answers a hail with,
## markets by id and the market each site id trades with, the module catalogue (the
## index into it is ModuleTable.module_ix) and the reputation distributions by id.
var conversations: Dictionary[StringName, Dictionary] = {}
var hail_conversations: Dictionary[StringName, StringName] = {}
var markets: Dictionary[StringName, MarketDef] = {}
var site_markets: Dictionary[int, StringName] = {}
var module_defs: Array[ModuleDef] = []
var rep_dists: Dictionary[StringName, RepDistDef] = {}
## The run's encounters and story flags (E07, FT-MIS-025).
var encounters: EncounterTable = EncounterTable.new()
## Read-only run data like defs (FT-ARC-020), filled by RunSetup: the enemies SpawnShipCommand
## can spawn by key, the scenario ids an encounter's scenario_ix indexes, and the run's
## numbers. null run_def: not a director run (the M1 encounter, tests).
var catalog: Dictionary[StringName, EnemyDef] = {}
var scenario_ids: PackedStringArray = PackedStringArray()
var run_def: RunDef
## The events and the first command-log entry of the latest step(), kept for the Scenario
## API (events(), commands_this_tick()) whichever way the caller drains the world.
var step_events: Array[SimEvent] = []
var step_log_from: int = 0
## Draws for scenarios and the director (ScenarioApi.rand): a stream of its own, not in the
## state hash, because the scenarios do not run on replay; what they decide is in the log.
var script_rng: SimRng
## The named sites, points in the one cube (D229); add_site() fills it from a MapDef.
var sites: SiteTable = SiteTable.new()

## Crew and server commands in application order, each stamped with its tick and
## whether it was accepted (FT-ARC-008, D122); rejected ones stay so replays reproduce
## their events. AI commands are regenerated by the sim on replay, so not logged.
var command_log: Array[SimCommand] = []
## Events since the last drain_events(), in emission order (FT-SIM-030).
var events: Array[SimEvent] = []
## Hits of the current tick, resolved by HitResolver.
var hits: Array[SimHit] = []

var _queue: Array[SimCommand] = []
## Ships reset during this tick's command phase: their later commands of the tick are
## rejected (cleared when the next command phase starts).
var _reset_this_tick: Dictionary[int, bool] = {}
var _relations: Dictionary[int, int] = {}
var _accumulator: float = 0.0


## site_period is the side of the scenario's wrapping cube (m, FT-SIM-035, D229); check it
## with period_errors() when the ships are known (M1Encounter.validate does).
func _init(
	world_seed: int = 0, build: String = "", site_period: float = Kinematics.DEFAULT_PERIOD
) -> void:
	seed_value = world_seed
	build_id = build
	rng = SimRng.new(world_seed)
	script_rng = SimRng.new(world_seed ^ 0x5CE7A210)
	kin.period = site_period


## Why a period (m) doesn't suit a scenario's ships, or [] if it does (PeriodRules.errors,
## FT-SIM-035, D124).
static func period_errors(site_period: float, ships: Array[ShipDef]) -> Array[String]:
	var longest: float = 0.0
	for def: ShipDef in ships:
		longest = maxf(longest, def.sensor_range)
	return PeriodRules.errors(site_period, longest)


## Every state container, in hash order (FT-ARC-012: each is keyed by ship and faction).
func tables() -> Array[SimTable]:
	return [
		kin,
		helm,
		power,
		shields,
		mounts,
		projectiles,
		damage,
		knowledge,
		ai,
		run,
		science,
		hacks,
		relay,
		probes,
		hazard_state,
		story,
		story_flags,
		economy,
		reputation,
		modules,
		encounters,
		sites,
	]


## Adds a ship from its definition at an offset in the cube (wrapped onto it) and returns
## its id.
func spawn_ship(
	def: ShipDef,
	faction: int,
	offset: Vector3 = Vector3.ZERO,
	rotation: Quaternion = Quaternion.IDENTITY,
	velocity: Vector3 = Vector3.ZERO
) -> int:
	var id: int = defs.size()
	defs.append(def)
	base_defs.append(def)
	for t: SimTable in tables():
		t.add_ship(id, faction, def)
	kin.place(id, offset.x, offset.y, offset.z)
	kin.rot[id] = rotation.normalized()
	kin.vel[id] = velocity
	return id


## Spawns an enemy's ship like spawn_ship and hands it to the enemy AI with the
## EnemyDef's behaviour numbers (T035, FT-SIM-027).
func spawn_enemy(
	enemy: EnemyDef,
	faction: int,
	offset: Vector3 = Vector3.ZERO,
	rotation: Quaternion = Quaternion.IDENTITY,
	velocity: Vector3 = Vector3.ZERO
) -> int:
	var id: int = spawn_ship(enemy.ship, faction, offset, rotation, velocity)
	ai.enable(id, enemy)
	return id


## Restores one ship's state from its definition and places it at an offset
## (m, 64-bit, D104, wrapped onto the cube), dropping its queued commands; other
## ships are untouched (FT-MIS-017: a destroyed ship's run state resets on its own). Runs
## submit a ResetShipCommand instead, which calls this at tick start and is logged for
## replay (FT-ARC-008); a direct call is not logged. Commands for the ship later in the
## same tick's batch are rejected (_apply_commands), so none lands on the fresh ship.
func reset_ship(
	ship_id: int,
	x: float = 0.0,
	y: float = 0.0,
	z: float = 0.0,
	rotation: Quaternion = Quaternion.IDENTITY
) -> void:
	# The commands dropped here are reported as rejected, for the API handles waiting on them.
	for c: SimCommand in _queue:
		if c.ship_id == ship_id:
			c.tick = tick
			c.accepted = false
	_queue.assign(_queue.filter(func(c: SimCommand) -> bool: return c.ship_id != ship_id))
	_reset_this_tick[ship_id] = true
	defs[ship_id] = base_defs[ship_id]  # fitted modules are run progress (FT-MIS-011)
	for t: SimTable in tables():
		t.reset_ship(ship_id, defs[ship_id])
	kin.place(ship_id, x, y, z)
	kin.rot[ship_id] = rotation.normalized()


## Opens a named site at `def`'s point (wrapped onto the cube), known to the factions in
## `known` (SiteTable bits), and returns its site id (D229).
func add_site(def: SiteDef, known: int = SiteTable.ALL_FACTIONS) -> int:
	return sites.add_site(def, kin.period, known, tick)


func ship_count() -> int:
	return defs.size()


func faction_of(ship_id: int) -> int:
	return kin.factions[ship_id]


func set_relation(a: int, b: int, relation: Relation) -> void:
	_relations[_pair(a, b)] = relation
	_relations[_pair(b, a)] = relation


## Same faction is friendly; others are hostile unless set otherwise.
func relation(a: int, b: int) -> Relation:
	if a == b:
		return Relation.FRIENDLY
	return _relations.get(_pair(a, b), Relation.HOSTILE) as Relation


## Queues a command for the next tick.
func submit(command: SimCommand) -> void:
	_queue.append(command)


## The commands queued for the next tick, in submission order (a copy of the list).
func queued_commands() -> Array[SimCommand]:
	return _queue.duplicate()


## Adds frame time and steps as many whole ticks as it covers (FT-ARC-006). before_step,
## when valid, is called without arguments right before each step (ScenarioHost runs the
## director there, so it sees the world between ticks).
func advance(frame_delta: float, before_step: Callable = Callable()) -> int:
	_accumulator += frame_delta
	var n: int = floori(_accumulator / DT)
	_accumulator -= n * DT
	if n > MAX_TICKS_PER_ADVANCE:
		n = MAX_TICKS_PER_ADVANCE
		_accumulator = 0.0
	for i: int in n:
		if before_step.is_valid():
			before_step.call()
		step()
	return n


## Advances one fixed tick. The phase order is part of the determinism contract.
func step() -> void:
	var events_from: int = events.size()
	step_log_from = command_log.size()
	_apply_commands()
	# Science first: its clocks and hack windows feed this tick's sensors and power.
	ScienceSystem.step(self)
	KnowledgeSystem.step(self)
	# The AI decides on this tick's knowledge; its commands apply next tick (FT-SIM-028).
	EnemyAi.step(self)
	PowerSystem.step(self)
	AssistSystem.step(self)
	JumpSystem.step(self)
	ProbeSystem.step(self)
	HazardSystem.step(self)
	Integrator.step_all(kin, DT)
	WeaponSystem.step(self)
	GuidanceSystem.step(self)
	CollisionSystem.step(self)
	HitResolver.resolve(self)
	ShieldSystem.step(self)
	DamageSystem.step(self)
	StorySystem.step(self)
	EncounterSystem.step(self)
	# Last: statuses and outcomes see this tick's destructions and knowledge (T036).
	OutcomeSystem.step(self)
	step_events = events.slice(events_from)
	tick += 1


func emit(
	kind: StringName,
	ship_id: int,
	other_id: int = -1,
	value: float = 0.0,
	vector: Vector3 = Vector3.ZERO,
	tag: StringName = &""
) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.tick = tick
	e.kind = kind
	e.ship_id = ship_id
	e.faction = faction_of(ship_id) if ship_id >= 0 and ship_id < defs.size() else -1
	e.other_id = other_id
	e.value = value
	e.vector = vector
	e.tag = tag
	events.append(e)
	return e


## The logged crew and server commands that were accepted, in order.
func accepted_commands() -> Array[SimCommand]:
	return command_log.filter(func(c: SimCommand) -> bool: return c.accepted)


## Returns and clears the events so far.
func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = events
	events = []
	return out


## SHA-256 over every table's columns, the tick, the RNG states, the relations, the
## period and the queued commands, in a fixed order (FT-ARC-008, D125). Events and the
## command log are outputs, not state.
func state_hash() -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var pending: Array = _queue.map(func(c: SimCommand) -> Array: return [c.to_dict(), c.source])
	ctx.update(var_to_bytes([tick, rng.states(), _relation_list(), pending, kin.period]))
	for t: SimTable in tables():
		for column: Array in t.columns():
			ctx.update(var_to_bytes(column))
	return ctx.finish().hex_encode()


func _apply_commands() -> void:
	var queue: Array[SimCommand] = _queue
	_queue = []
	_reset_this_tick.clear()
	# Sizes and liveness are read per command: an earlier command of the batch may spawn a ship.
	for c: SimCommand in queue:
		var id: int = c.ship_id
		if id < 0 and c is ServerCommand:
			# a run-wide server command names no ship.
			c.tick = tick
			c.accepted = c.apply(self)
			command_log.append(c)
			continue
		if id < 0 or id >= defs.size() or not (kin.alive[id] == 1 or c.applies_to_destroyed()):
			# Dropped, not logged: marked rejected so an API handle waiting on it ends.
			c.tick = tick
			c.accepted = false
			continue
		c.tick = tick
		# A ship reset earlier this tick rejects its later commands of the tick (logged
		# as rejected, so a replay rejects them too).
		c.accepted = not _reset_this_tick.has(id) and c.apply(self)
		if c.source != SimCommand.Source.AI:
			command_log.append(c)


func _relation_list() -> Array:
	var keys: Array[int] = _relations.keys()
	keys.sort()
	return keys.map(func(k: int) -> int: return k * 4 + _relations[k])


static func _pair(a: int, b: int) -> int:
	return a * 65536 + b
