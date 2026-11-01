class_name RunSetup
extends M1Encounter
## The Milestone 3 run setup (E07, FT-MIS-001, FT-MIS-025): replaces M1Encounter on the
## server. It keeps its inputs (seed, build id and the already-loaded definitions; the sim
## never loads, FT-ARC-020) so the run reset is build() again: a fresh world with nothing
## carried over (FT-GEN-010, FT-MIS-017). The world holds the crewed ships at Kestrel Yard
## and no enemy: the director places encounters through the Scenario API. It extends
## M1Encounter only so NetServer takes it unchanged, as LoadEncounter does; M1Encounter
## itself stays for the golden, load and pair tests.

## The run: map, numbers and scenario list.
var run_def: RunDef
## Enemies SpawnShipCommand may spawn, by key (app/ fills it from DefLibrary).
var catalog: Dictionary[StringName, EnemyDef] = {}
## Crewable ships to spawn.
var crew_ships: int = 1
## Read-only scenario data the world carries like defs (SimWorld): parsed conversations,
## the module catalogue, reputation distributions, markets and the market of each site.
var conversations: Dictionary[StringName, Dictionary] = {}
var module_defs: Array[ModuleDef] = []
var rep_dists: Dictionary[StringName, RepDistDef] = {}
var markets: Dictionary[StringName, MarketDef] = {}
var site_markets: Dictionary[int, StringName] = {}
var hail_conversations: Dictionary[StringName, StringName] = {}
## Gap between the crewed ships at the start (m), so they do not overlap at the yard.
var crew_spacing_m: float = 100.0
## The session built from the multi-ship lobby (#11, FT-GEN-001, M4-Q3): one crewed ship per
## slot, in slot order, with the slot's faction and team. Empty: `crew_ships` ships of
## PLAYER_FACTION, as before M4.
var slots: Array[ShipSlot] = []
## The session's rules (mode, team win rule, relaunch policies); build() hands them to the
## world. Defaults to COOP.
var rules: SessionRules = SessionRules.new()


func _init(
	seed_value: int,
	build: String,
	run: RunDef,
	enemies: Dictionary[StringName, EnemyDef] = {},
	crew: int = 1
) -> void:
	super(
		seed_value,
		build,
		run.player_ship,
		null,
		run.map.period_m if run.map != null else Kinematics.DEFAULT_PERIOD
	)
	run_def = run
	catalog = enemies
	crew_ships = crew


## Why the run can't be built, or []: the RunDef's own errors, the crew size and the map
## against the longest sensor range of any ship that can be in it (its period and the
## spacing of its sites, D229).
func validate() -> Array[String]:
	var errors: Array[String] = run_def.validate()
	if crew_ships < 1:
		errors.append("crew_ships must be at least 1, got %d" % crew_ships)
	if not slots.is_empty():
		errors.append_array(rules.slot_errors(slots))
	if run_def.player_ship == null:
		return errors
	var ships: Array[ShipDef] = [run_def.player_ship]
	for key: StringName in catalog:
		ships.append(catalog[key].ship)
	if run_def.map != null:
		errors.append_array(run_def.map.errors(ships))  # period and the D229 site spacing
	else:
		errors.append_array(SimWorld.period_errors(site_period, ships))
	if hazards.size() > HazardSystem.MAX_HAZARDS:
		errors.append(
			"%d hazards, at most %d are supported" % [hazards.size(), HazardSystem.MAX_HAZARDS]
		)
	return errors


## A new world at tick 0 holding the crewed ships, or null when validate() reports errors.
func build() -> SimWorld:
	if not validate().is_empty():
		return null
	var world: SimWorld = SimWorld.new(world_seed, build_id, site_period)
	world.science_def = science
	world.hazards = hazards.duplicate()
	world.catalog = catalog
	world.scenario_ids = run_def.scenarios
	world.run_def = run_def
	world.conversations = conversations
	world.module_defs = module_defs
	world.rep_dists = rep_dists
	world.markets = markets
	world.site_markets = site_markets
	world.hail_conversations = hail_conversations
	if run_def.map != null:
		world.sites.load_map(world, run_def.map)
	world.rules = rules
	# Crew factions of different sides are hostile by SimWorld's default (PvP); allies share one.
	var starts: PackedInt32Array = start_sites(world)
	for i: int in crew_count():
		var faction: int = slots[i].faction if not slots.is_empty() else PLAYER_FACTION
		var site: int = starts[i]
		var at: Vector3 = world.sites.point3(site) if site >= 0 else Vector3.ZERO
		var offset: Vector3 = at + Vector3(i * crew_spacing_m, 0.0, 0.0)
		var id: int = world.spawn_ship(run_def.player_ship, faction, offset)
		if not slots.is_empty():
			world.ship_teams[id] = slots[i].team
		world.ship_starts[id] = offset
		world.ship_start_site[id] = site
		if site >= 0:
			world.sites.reveal(site, faction)
		# A ship reset sets credits to 0, so the run's starting purse is set here (FT-MIS-018).
		Economy.add_credits(world, id, run_def.start_credits)
	return world


## The site each crewed ship starts at, by slot index (-1 with no sites). Co-op starts every
## ship at Kestrel Yard (site 0, D205). PvP (#11, PROVISIONAL, open for the owner) starts
## each side at its own site, as far apart as the map allows: the yard for the first side,
## then for each next side the site farthest (by minimum image) from the ones taken; with
## more sides than sites, the sites are used again in the same order. The ships of a site
## stand crew_spacing_m apart by slot index, so they never overlap.
func start_sites(world: SimWorld) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var count: int = world.sites.size()
	var by_side: Dictionary[int, int] = {}
	var taken: PackedInt32Array = PackedInt32Array()
	for i: int in crew_count():
		if count == 0:
			out.append(-1)
			continue
		var side: int = slots[i].team if not slots.is_empty() and rules.is_pvp() else 0
		if not by_side.has(side):
			var site: int = _farthest_site(world, taken)
			by_side[side] = site
			taken.append(site)
		out.append(by_side[side])
	return out


## The site farthest from every taken one (the smallest gap to any, made as large as it can
## be; the lowest id on a tie); site 0 when none is taken; the taken ones again, in order,
## once every site is taken.
static func _farthest_site(world: SimWorld, taken: PackedInt32Array) -> int:
	var count: int = world.sites.size()
	if taken.is_empty():
		return 0
	if taken.size() >= count:
		return taken[taken.size() % count]
	var kin: Kinematics = world.kin
	var best: int = -1
	var best_gap: float = -1.0
	for s: int in count:
		if taken.has(s):
			continue
		var a: PackedFloat64Array = world.sites.point(s)
		var gap: float = INF
		for t: int in taken:
			var b: PackedFloat64Array = world.sites.point(t)
			var d: Vector3 = Vector3(
				kin.wrap(a[0] - b[0]), kin.wrap(a[1] - b[1]), kin.wrap(a[2] - b[2])
			)
			gap = minf(gap, d.length())
		if gap > best_gap:
			best_gap = gap
			best = s
	return best


## Crewed ships build() spawns: one per slot, or `crew_ships` without slots.
func crew_count() -> int:
	return slots.size() if not slots.is_empty() else crew_ships
