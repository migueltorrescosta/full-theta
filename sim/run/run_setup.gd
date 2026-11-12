class_name RunSetup
extends M1Encounter
## The Milestone 3 run setup (E07, FT-MIS-001, FT-MIS-025): replaces M1Encounter on the
## server. It keeps its inputs (seed, build id and the already-loaded definitions; the sim
## never loads, FT-ARC-020) so the run reset is build() again: a fresh world with nothing
## carried over (FT-GEN-010, FT-MIS-017). The world holds the crewed ships at Kestrel Yard
## and no enemy: the director places encounters through the Scenario API. It extends
## M1Encounter only so NetServer takes it unchanged, as LoadEncounter does; M1Encounter
## itself stays for the golden, load and pair tests.

## Gap between the crewed ships at the start (m), so they do not overlap at the yard.
const CREW_SPACING: float = 100.0

## The run: map, numbers and scenario list.
var run_def: RunDef
## NPCs SpawnShipCommand may spawn, by key (app/ fills it from DefLibrary).
var catalog: Dictionary[StringName, NpcDef] = {}
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
## The run modifiers by id (gp-11); build() applies the one GameRules.modifier_id names.
var modifiers: Dictionary[StringName, RunModifierDef] = {}
## The session built from the multi-ship lobby (#11, FT-GEN-001, M4-Q3): one crewed ship per
## slot, in slot order, of the faction rules.faction_for gives its team (faction_of_slot):
## the sim never sees a team (B5). Empty: `crew_ships` ships of PLAYER_FACTION, as before M4.
var slots: Array[ShipSlot] = []
## The session's rules (mode, team win rule, relaunch policies); build() hands them to the
## world. Defaults to COOP.
var rules: GameRules = GameRules.new()


func _init(
	seed_value: int,
	build: String,
	run: RunDef,
	npcs: Dictionary[StringName, NpcDef] = {},
	crew: int = 1
) -> void:
	super(
		seed_value,
		build,
		run.player_ship,
		null,
		run.map.period if run.map != null else Kinematics.DEFAULT_PERIOD
	)
	run_def = run
	catalog = npcs
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
		errors.append_array(SimWorld.period_errors(map_period, ships))
	if hazards.size() > HazardSystem.MAX_HAZARDS:
		errors.append(
			"%d hazards, at most %d are supported" % [hazards.size(), HazardSystem.MAX_HAZARDS]
		)
	return errors


## A new world at tick 0 holding the crewed ships, or null when validate() reports errors.
func build() -> SimWorld:
	if not validate().is_empty():
		return null
	var world: SimWorld = SimWorld.new(world_seed, build_id, map_period)
	world.science_def = science
	world.hazards = hazards.duplicate()
	world.catalog = catalog
	world.scenario_ids = run_def.scenarios
	world.run_def = run_def
	world.conversations = conversations
	world.module_defs = module_defs
	world.rep_dists = rep_dists
	var modifier: RunModifierDef = modifiers.get(rules.modifier_id, null)
	if modifier != null:
		world.modifier = modifier
	world.markets = _priced(markets, world.modifier.prices)
	world.site_markets = site_markets
	world.hail_conversations = hail_conversations
	if run_def.map != null:
		world.sites.load_map(world, run_def.map)
	world.rules = rules
	# Co-op relaunches are the run's (gp-10, #38 D4 amending D259): once per ship, paid.
	if rules.mode == GameRules.Mode.COOP and run_def.coop_relaunches > 0:
		rules.default_relaunch = RelaunchPolicy.of_lives(run_def.coop_relaunches)
	# Crew factions of different sides are hostile by SimWorld's default (PvP); allies share one.
	var starts: PackedInt32Array = start_sites(world)
	for i: int in crew_count():
		var faction: int = faction_of_slot(i)
		var site: int = starts[i]
		var at: PackedFloat64Array = world.sites.point(site) if site >= 0 else CubePoint.make()
		at = CubePoint.plus(at, Vector3(i * CREW_SPACING, 0.0, 0.0))
		var id: int = world.spawn_ship(run_def.player_ship, faction, at)
		world.ship_starts[id] = at
		world.ship_start_site[id] = site
		if site >= 0:
			world.sites.reveal(site, faction)
		# A ship reset sets credits to 0, so the run's starting purse is set here (FT-MIS-018).
		Economy.add_credits(world, id, run_def.start_credits)
	return world


## The markets with every price and repair times `factor` (the run modifier, gp-11), rounded
## up so nothing becomes free; the same markets when it is 1. Copies: defs stay read-only.
static func _priced(
	by_id: Dictionary[StringName, MarketDef], factor: float
) -> Dictionary[StringName, MarketDef]:
	if is_equal_approx(factor, 1.0):
		return by_id
	var out: Dictionary[StringName, MarketDef] = {}
	for id: StringName in by_id:
		var m: MarketDef = by_id[id].duplicate()
		m.prices = m.prices.duplicate()
		m.repairs = m.repairs.duplicate()
		for item: StringName in m.prices:
			m.prices[item] = ceili(m.prices[item] * factor - 1e-6)
		for sub: StringName in m.repairs:
			m.repairs[sub] = ceili(m.repairs[sub] * factor - 1e-6)
		out[id] = m
	return out


## The faction of the crewed ship of slot `i`: its team mapped by rules.faction_for, the
## one place a lobby team becomes a faction (B5); PLAYER_FACTION without slots.
func faction_of_slot(i: int) -> int:
	return rules.faction_for(i, slots[i].team) if not slots.is_empty() else PLAYER_FACTION


## The site each crewed ship starts at, by slot index (-1 with no sites). Co-op starts every
## ship at Kestrel Yard (site 0, D205). PvP (#11, PROVISIONAL, open for the owner) starts
## each faction at its own site, as far apart as the map allows: the yard for the first faction,
## then for each next faction the site farthest (by minimum image) from the ones taken; with
## more factions than sites, the sites are used again in the same order. The ships of a site
## stand CREW_SPACING apart by slot index, so they never overlap.
func start_sites(world: SimWorld) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var count: int = world.sites.size()
	var by_faction: Dictionary[int, int] = {}
	var taken: PackedInt32Array = PackedInt32Array()
	for i: int in crew_count():
		if count == 0:
			out.append(-1)
			continue
		var faction: int = faction_of_slot(i)
		if not by_faction.has(faction):
			var site: int = _farthest_site(world, taken)
			by_faction[faction] = site
			taken.append(site)
		out.append(by_faction[faction])
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
			gap = minf(gap, kin.delta(a, world.sites.point(t)).length())
		if gap > best_gap:
			best_gap = gap
			best = s
	return best


## Crewed ships build() spawns: one per slot, or `crew_ships` without slots.
func crew_count() -> int:
	return slots.size() if not slots.is_empty() else crew_ships
