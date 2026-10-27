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
## (FT-MIS-005). The server uses it as its driver: before_tick() and decisions().
##
## CONTRACT STUB (strand A): one Director over every crewed ship, as before M4.

## The session's mode, a SessionRules.Mode value (the director names sim/api only, so an int;
## ScenarioApi.session_mode() gives the same).
var _mode: int = 0
var _def: DirectorDef
## Faction -> its Director (stub: the single Director under key -1).
var _directors: Dictionary[int, Director] = {}


func _init(
	def: DirectorDef, difficulty: StringName, catalogue: Array[Scenario], seed_value: int, mode: int
) -> void:
	_def = def
	_mode = mode
	_directors[-1] = Director.new(def, difficulty, catalogue, seed_value)


## Called by ScenarioHost before every tick: steps each faction's Director.
func before_tick(api: ScenarioApi) -> void:
	for faction: int in _directors:
		_directors[faction].before_tick(api)


## Every Director's decisions, oldest first (the debrief reads them, FT-MIS-006).
func decisions() -> Array[DirectorDecision]:
	var out: Array[DirectorDecision] = []
	for faction: int in _directors:
		out.append_array(_directors[faction].decisions())
	return out


## The Director that plans for a faction's ships, or null.
func director_for(faction: int) -> Director:
	return _directors.get(faction, _directors.get(-1))


## The strength multiplier for a faction's encounters with `ships` crewed ships in play,
## on top of the preset's strength (FT-MIS-023, M4-Q1): DirectorDef.fleet_strength_per_ship
## for each ship beyond the first. Stub: 1.0.
func strength_for(_ships: int) -> float:
	return 1.0


## RACE: the seeded scenario ids every ship plays, in order (M4-Q5). Stub: none.
func race_plan() -> PackedStringArray:
	return PackedStringArray()


## LAST_STANDING: the strength multiplier of the wave-th raider wave (0 first), growing by
## DirectorDef.raider_wave_growth (M4-Q7). Stub: 1.0.
func wave_strength(_wave: int) -> float:
	return 1.0
