class_name FleetDirector
extends RunDriver
## The director of a multi-ship game (#11, FT-MIS-023, FT-MIS-013, owner M4-Q1, M4-Q5,
## M4-Q7, 2026-10-28): one Director per crew faction, so allies share one fleet run and
## rivals each get their own, keyed by the game's mode (ScenarioApi.game_mode()):
## - COOP and TEAMS: one Director per faction; its budget is the fleet's, its encounters are
##   scaled to the faction's ship count (Director.fleet_multiplier), and the fleet run has one final
##   objective (M4-Q1).
## - RACE: one seeded encounter list (race_plan), the same order and strength for every
##   ship, each ship at its own copy of each site (M4-Q5); no adaptation to a crew.
## - LAST_STANDING: no run; raider waves of growing strength (wave_strength) at every
##   surviving ship (M4-Q7).
## - HOLDOUT: no director encounters (PROVISIONAL, open for the owner).
## Like Director it reads the world only through the Scenario API and queues SERVER commands
## (FT-MIS-005). The server uses it as its driver: before_tick() and decisions(). The
## Directors are made on the first tick, one per crew faction in play, in ship id order.

## A raider wave (M4-Q7): this enemy, of this NPC faction, this far from each ship, this many
## at strength 1 (the preset's strength and wave_strength scale it, at least one).
const RAIDERS_PER_WAVE: int = 1
## At most this many raiders of the waves alive at once per ship: a wave only fills up to it
## (D264, A11), so the sim carries a bounded number of AI ships however long the game lasts.
const MAX_ALIVE_PER_SHIP: int = 6

## The session's mode, a GameRules.Mode value (the director names sim/api only, so an int;
## ScenarioApi.game_mode() gives the same).
var _mode: int = 0
var _def: DirectorDef
var _difficulty: StringName
var _catalogue: Array[Scenario] = []
var _seed: int = 0
## Faction -> its Director, in the order they were made.
var _directors: Dictionary[int, Director] = {}
## Sites with an encounter of any Director: rival teams never share a site (A10).
var _taken_sites: Dictionary[int, bool] = {}
## RACE: the plan every ship plays, [{scenario, site}].
var _race: Array[Dictionary] = []
## LAST_STANDING: waves sent so far and the wave decisions, oldest first.
var _waves: int = 0
var _wave_log: Array[DirectorDecision] = []
## LAST_STANDING: the raiders sent at each ship, to count the ones still alive.
var _sent: Dictionary[int, Array] = {}


func _init(
	def: DirectorDef, difficulty: StringName, catalogue: Array[Scenario], seed_value: int, mode: int
) -> void:
	_def = def
	_difficulty = difficulty
	_catalogue = catalogue
	_seed = seed_value
	_mode = mode


## Called by ScenarioHost before every tick: steps each faction's Director, or sends the
## raider waves.
func before_tick(api: ScenarioApi) -> void:
	match _mode:
		ScenarioApi.MODE_LAST_STANDING:
			_maybe_wave(api)
		ScenarioApi.MODE_HOLDOUT:
			pass
		_:
			_add_directors(api)
			for faction: int in _directors:
				_directors[faction].before_tick(api)


## Every Director's decisions and the waves', oldest first (the debrief reads them,
## FT-MIS-006).
func decisions() -> Array[DirectorDecision]:
	var out: Array[DirectorDecision] = []
	for faction: int in _directors:
		out.append_array(_directors[faction].decisions())
	out.append_array(_wave_log)
	if _directors.size() > 1:
		out.sort_custom(
			func(a: DirectorDecision, b: DirectorDecision) -> bool: return a.tick < b.tick
		)
	return out


## The Director that plans for a faction's ships, or null (none yet, or none in this mode).
func director_for(faction: int) -> Director:
	return _directors.get(faction)


## The faction's Director's current site offers (E2, w-bzx), as RunDriver.site_offers; none
## without one.
func site_offers(faction: int) -> Array[Dictionary]:
	var d: Director = director_for(faction)
	if d == null:
		return []
	return d.site_offers(faction)


## RACE: the seeded scenario ids every ship plays, in order (M4-Q5); empty before the first
## tick and in other modes.
func race_plan() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry: Dictionary in _race:
		out.append(String(entry["scenario"]))
	return out


## RACE: the site key of each race_plan() entry (each ship plays it at its own copy).
func race_sites() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry: Dictionary in _race:
		out.append(String(entry["site"]))
	return out


## LAST_STANDING: the strength multiplier of the wave-th raider wave (0 first), growing by
## DirectorDef.raider_wave_growth (M4-Q7).
func wave_strength(wave: int) -> float:
	return 1.0 + _def.raider_wave_growth * maxi(wave, 0)


## Makes a Director for each crew faction in play that has none. The first gets the session
## seed, so a single-ship co-op run plans as M3's Director did; in a race the plan is drawn
## once, with the session seed, and every Director plays it.
func _add_directors(api: ScenarioApi) -> void:
	for id: int in api.crew_ships():
		var faction: int = api.faction_of(id)
		if _directors.has(faction):
			continue
		var seed_value: int = _seed if _directors.is_empty() else hash([_seed, faction])
		var d: Director = Director.new(_def, _difficulty, _catalogue, seed_value, faction)
		d.share_sites(_taken_sites)
		if _mode == ScenarioApi.MODE_RACE:
			if _race.is_empty():
				var planner: Director = Director.new(_def, _difficulty, _catalogue, _seed, faction)
				_race = planner.plan_race(api.encounter_limits(), _race_site_keys(api))
			d.set_race(_race)
		_directors[faction] = d


## Site keys a race may use: every map site but Kestrel Yard (site 0, D205).
static func _race_site_keys(api: ScenarioApi) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var home: StringName = &""
	for s: SiteInfo in api.sites():
		if s.id == Director.HOME_SITE:
			home = s.key
	for key: String in api.map_site_keys():
		if StringName(key) != home:
			out.append(key)
	return out


## LAST_STANDING (M4-Q7): every raider_wave_every a wave at each crewed ship in play,
## wave_strength(wave) times the preset's strength, from its own bearing, so hiding loses.
func _maybe_wave(api: ScenarioApi) -> void:
	var every: int = SimRate.ticks(_def.raider_wave_every)
	var now: int = api.tick()
	if every <= 0 or now < every * (_waves + 1):
		return
	var strength: float = Director.strength_for(
		_def, _difficulty, wave_strength(_waves) * api.modifier_strength()
	)
	var wanted: int = Scenario.count_for(RAIDERS_PER_WAVE, strength)
	for ship: int in api.crew_ships():
		if _waves == 0:
			api.set_relation(Factions.RAIDER, api.faction_of(ship), Scenario.Relation.HOSTILE)
		var count: int = mini(wanted, MAX_ALIVE_PER_SHIP - _alive_sent(api, ship))
		if count < 1:
			continue
		var handles: Array = _sent.get(ship, [])
		for k: int in count:
			var clock: int = Scenario.clock_slot(floori(api.rand(&"raider_wave") * 12.0) + k * 4)
			handles.append(
				api.spawn_at_range(
					Factions.RAIDER_KEY, Factions.RAIDER, ship, Factions.RAIDER_REACH, clock, 0
				)
			)
		_sent[ship] = handles
		_wave_log.append(
			DirectorDecision.make(
				now,
				ship,
				DirectorDecision.Kind.RAIDER_WAVE,
				{"reason": "raider_wave", "args": {"wave": _waves + 1, "count": count}}
			)
		)
	_waves += 1


## The raiders sent at the ship that are still in play (a spawn not applied yet counts); the
## gone ones are forgotten.
func _alive_sent(api: ScenarioApi, ship: int) -> int:
	var alive: Array = []
	for handle: ApiHandle in _sent.get(ship, []):
		if handle.pending() or (not handle.rejected() and api.ship(handle.id()).in_play):
			alive.append(handle)
	_sent[ship] = alive
	return alive.size()
