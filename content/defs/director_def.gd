class_name DirectorDef
extends Resource
## The director's tuning (E07, FT-MIS-005, FT-MIS-028, FT-MIS-029, D35, D81, D92, D230).
## The threat budget is per crewed ship and keyed by the difficulty preset's name, so a
## custom toggle set ("Normal (custom)") keeps its preset's budget. PROVISIONAL (Q4, Q14):
## the budget numbers and the pacing are placeholders for #13 to tune. Read-only at
## runtime (FT-ARC-020). Units are SI (FT-DAT-013).

@export var id: StringName = &""
## Threat budget per crewed ship by preset name (threat-cost points, FT-MIS-029).
@export var budget_per_ship: Dictionary[StringName, int] = {}
## Time between the director opening a new site (s, 0: never).
@export var spawn_site_every: float = 0.0
## Most sites the director keeps open besides the known ones (count).
@export var max_open_sites: int = 0
## Quiet time between one encounter ending and the next being picked (s, D230).
@export var gap: float = 0.0
## An opened encounter starts this long after opening even if the crew has not arrived (s, D231).
@export var arrival_timeout: float = 0.0
## Enemy strength by preset name: the multiplier a hostile scenario applies to its enemy count
## (enemy_wave, rescue), rounded, at least 1 enemy. A preset missing here counts 1.0
## (Q14, owner 2026-10-26; PROVISIONAL numbers for #13).
@export var strength_per_preset: Dictionary[StringName, float] = {}
## A fleet run's encounters grow by this much strength per crewed ship beyond the first
## (dimensionless multiplier points per ship, #11, FT-MIS-023, M4-Q1; 0: no scaling).
## PROVISIONAL for #13.
@export var fleet_strength_per_ship: float = 0.0
## LAST_STANDING raider waves (#11, M4-Q7): a wave at every surviving ship this often (s, 0:
## none). PROVISIONAL.
@export var raider_wave_every: float = 0.0
## Each raider wave's strength above the last (dimensionless multiplier points). PROVISIONAL.
@export var raider_wave_growth: float = 0.0
## The strength ramp over a run (gp-05, D3): an encounter's strength is the preset's times this
## ramp, linear from ramp_start at the first encounter to ramp_end at the run's last regular
## one (encounter index max_encounters - 2 with a finale, - 1 without), clamped
## (dimensionless multipliers; 1 and 1: no ramp). PROVISIONAL for the balance pass.
@export var ramp_start: float = 1.0
## The ramp at the run's last regular encounter and the finale (dimensionless multiplier).
@export var ramp_end: float = 1.0
## The finale (gp-06, D3): the scenario id the run ends with, played once the regular picks are
## over, its budget ignored, at strength preset x ramp_end (&"": no finale, the run closes as
## before). Winning it closes the run; a fled or timed-out one is offered again after the gap,
## at most finale_tries times in all, after which the run closes with the ship surviving
## rather than winning (w-a89).
@export var finale_scenario: StringName = &""
## The map site the finale is placed at when it is open and free (else any free site).
@export var finale_site: StringName = &""
## Finale attempts before the run closes anyway (count).
@export var finale_tries: int = 1
## Raider escorts of the heavy raider at strength 1 (count), scaled like a wave and rounded
## (at least one); a fraction tunes between presets (1.15: 1 on Normal, 2 on Hard;
## none on Easy, finale_escorts_from).
@export var finale_escorts: float = 0.0
## The finale's strength under which the heavy raider comes alone (dimensionless, the strength
## the finale is played at: preset x ramp_end x fleet; 0: always escorts). w-4cm: no escorts on
## Easy.
@export var finale_escorts_from: float = 0.0
## The finale's time limit (s): past it the encounter ends PARTIAL.
@export var finale_time_limit: float = 300.0
## Crew-chosen sites (E2, w-bzx): at the start of each quiet gap before a regular encounter the
## director offers up to this many picks, each a different scenario at a different free site
## (count; 0 or 1: no choice, the director picks as before). The Captain, or Comms when no
## Captain is seated, picks one; with no pick the director picks when the gap ends, as before
## (the first offer, its own pick, was judged at the gap's start).
@export var site_offers: int = 0
## Each offer's risk tag by scenario id: 0 low, 1 some, 2 high (a scenario not listed: 2 when
## tagged hostile, else 0).
@export var offer_risk: Dictionary[StringName, int] = {}
## Each offer's pay tag by scenario id: 0 low, 1 fair, 2 high (a scenario not listed: 1).
@export var offer_reward: Dictionary[StringName, int] = {}


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if budget_per_ship.is_empty():
		errors.append("budget_per_ship needs at least one preset")
	for preset: StringName in budget_per_ship:
		if budget_per_ship[preset] < 1:
			errors.append("budget_per_ship[%s] must be at least 1" % preset)
	DefCheck.non_negative(errors, "spawn_site_every", spawn_site_every)
	DefCheck.non_negative(errors, "gap", gap)
	DefCheck.positive(errors, "arrival_timeout", arrival_timeout)
	if max_open_sites < 0:
		errors.append("max_open_sites must be at least 0, got %d" % max_open_sites)
	DefCheck.non_negative(errors, "fleet_strength_per_ship", fleet_strength_per_ship)
	DefCheck.non_negative(errors, "raider_wave_every", raider_wave_every)
	DefCheck.non_negative(errors, "raider_wave_growth", raider_wave_growth)
	DefCheck.positive(errors, "ramp_start", ramp_start)
	DefCheck.positive(errors, "ramp_end", ramp_end)
	if finale_tries < 1:
		errors.append("finale_tries must be at least 1, got %d" % finale_tries)
	if finale_escorts < 0.0:
		errors.append("finale_escorts must be at least 0, got %s" % finale_escorts)
	DefCheck.non_negative(errors, "finale_escorts_from", finale_escorts_from)
	DefCheck.positive(errors, "finale_time_limit", finale_time_limit)
	if site_offers < 0:
		errors.append("site_offers must be at least 0, got %d" % site_offers)
	for tags: Dictionary[StringName, int] in [offer_risk, offer_reward]:
		for k: StringName in tags:
			if tags[k] < 0 or tags[k] > 2:
				errors.append("offer tag %s must be 0, 1 or 2, got %d" % [k, tags[k]])
	for preset: StringName in strength_per_preset:
		if not strength_per_preset[preset] > 0.0:
			errors.append("strength_per_preset[%s] must be > 0" % preset)
	return errors
