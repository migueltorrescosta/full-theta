class_name FleetDirector
extends RefCounted
## The director of a multi-ship session (#11, FT-MIS-023, FT-MIS-013, owner M4-Q1, M4-Q5,
## M4-Q7, 2026-10-28): one Director per crew faction, so allies share one fleet run and
## rivals each get their own, keyed by the session's mode (ScenarioApi.session_mode()):
## - COOP and TEAMS: one Director per faction; its budget is the fleet's, its encounters are
##   scaled to the faction's ship count (strength_for), and the fleet run has one final
##   objective (M4-Q1).
## - RACE: one seeded encounter list (race_plan), the same order and strength for every
##   ship, each ship at its own copy of each site (M4-Q5); no adaptation to a crew.
## - LAST_STANDING: no run; raider waves of growing strength (wave_strength) at every
##   surviving ship (M4-Q7).
## - HOLDOUT: no director encounters (PROVISIONAL, open for the owner).
## Like Director it reads the world only through the Scenario API and queues SERVER commands
## (FT-MIS-005). The server uses it as its driver: before_tick() and decisions(). The
## Directors are made on the first tick, one per crew faction in play, in ship id order.

## SessionRules.Mode values (the director names sim/api only; a test checks they match).
const COOP: int = 0
const RACE: int = 1
const LAST_STANDING: int = 2
const TEAMS: int = 3
const HOLDOUT: int = 4
## A raider wave (M4-Q7): this enemy, of this NPC faction, this far from each ship, this many
## at strength 1 (the preset's strength and wave_strength scale it, at least one).
const RAIDER: StringName = &"m1_raider"
const RAIDER_FACTION: int = 2
const RAIDER_RANGE_M: float = 9000.0
const RAIDERS_PER_WAVE: int = 1

## The session's mode, a SessionRules.Mode value (the director names sim/api only, so an int;
## ScenarioApi.session_mode() gives the same).
var _mode: int = 0
var _def: DirectorDef
var _difficulty: StringName
var _catalogue: Array[Scenario] = []
var _seed: int = 0
## Faction -> its Director, in the order they were made.
var _directors: Dictionary[int, Director] = {}
## RACE: the plan every ship plays, [{scenario, site}].
var _race: Array[Dictionary] = []
## LAST_STANDING: waves sent so far and the wave decisions, oldest first.
var _waves: int = 0
var _wave_log: Array[DirectorDecision] = []


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
		LAST_STANDING:
			_maybe_wave(api)
		HOLDOUT:
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


## The strength multiplier for a faction's encounters with `ships` crewed ships in play,
## on top of the preset's strength (FT-MIS-023, M4-Q1): DirectorDef.fleet_strength_per_ship
## for each ship beyond the first.
func strength_for(ships: int) -> float:
	return Director.fleet_multiplier(_def, ships)


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
		var faction: int = api.ship(id).faction
		if _directors.has(faction):
			continue
		var seed_value: int = _seed if _directors.is_empty() else hash([_seed, faction])
		var d: Director = Director.new(_def, _difficulty, _catalogue, seed_value, faction)
		if _mode == RACE:
			if _race.is_empty():
				var planner: Director = Director.new(_def, _difficulty, _catalogue, _seed)
				_race = planner.plan_race(api.encounter_limits(), _race_site_keys(api))
			d.set_race(_race)
		_directors[faction] = d


## Site keys a race may use: every map site but Kestrel Yard (site 0, D205).
static func _race_site_keys(api: ScenarioApi) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var home: StringName = &""
	for s: SiteView in api.sites():
		if s.id == Director.HOME_SITE:
			home = s.key
	for key: String in api.map_site_keys():
		if StringName(key) != home:
			out.append(key)
	return out


## LAST_STANDING (M4-Q7): every raider_wave_every_s a wave at each crewed ship in play,
## wave_strength(wave) times the preset's strength, from its own bearing, so hiding loses.
func _maybe_wave(api: ScenarioApi) -> void:
	var every: int = ceili(_def.raider_wave_every_s * ScenarioApi.HZ)
	var now: int = api.tick()
	if every <= 0 or now < every * (_waves + 1):
		return
	var preset: StringName = Director.preset_of(String(_difficulty))
	var strength: float = _def.strength_per_preset.get(preset, 1.0) * wave_strength(_waves)
	var count: int = maxi(1, roundi(RAIDERS_PER_WAVE * strength))
	for ship: int in api.crew_ships():
		if _waves == 0:
			api.set_relation(RAIDER_FACTION, api.ship(ship).faction, Scenario.Relation.HOSTILE)
		for k: int in count:
			var clock: int = (floori(api.rand(&"raider_wave") * 12.0) + k * 4) % 12 + 1
			api.spawn_at_range(RAIDER, RAIDER_FACTION, ship, RAIDER_RANGE_M, clock, 0)
		var d: DirectorDecision = DirectorDecision.new()
		d.tick = now
		d.ship = ship
		d.kind = DirectorDecision.Kind.RAIDER_WAVE
		d.reason_key = "director.reason.raider_wave"
		d.reason_args = {"wave": _waves + 1, "count": count}
		_wave_log.append(d)
	_waves += 1
