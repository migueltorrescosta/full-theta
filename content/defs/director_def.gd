class_name DirectorDef
extends Resource
## The director's tuning (E07, FT-MIS-005, FT-MIS-028, FT-MIS-029, D35, D81, D92, D230).
## The threat budget is per crewed ship and keyed by the difficulty preset's name, so a
## custom toggle set ("Normal (custom)") keeps its preset's budget. PROVISIONAL (Q4, Q14):
## the budget numbers and the pacing are placeholders for #13 to tune. Read-only at
## runtime (FT-ARC-020). Units are SI (FT-DAT-013).

## The one scenario that costs nothing (the Shakedown, FT-MIS-039).
const TRAINING: StringName = &"shakedown"

@export var id: StringName = &""
## Threat budget per crewed ship by preset name (threat-cost points, FT-MIS-029).
@export var budget_per_ship: Dictionary[StringName, int] = {}
## Time between the director opening a new site (s, 0: never).
@export var spawn_site_every_s: float = 0.0
## Most sites the director keeps open besides the known ones (count).
@export var max_open_sites: int = 0
## Quiet time between one encounter ending and the next being picked (s, D230).
@export var gap_s: float = 0.0
## An opened encounter starts this long after opening even if the crew has not arrived (s, D231).
@export var arrival_timeout_s: float = 0.0
## Scenario id -> threat cost override, for #13's tuning (points).
@export var costs: Dictionary[StringName, int] = {}
## Enemy strength by preset name: the multiplier a hostile scenario applies to its enemy count
## (enemy_wave, rescue), rounded, at least 1 enemy. A preset missing here counts 1.0
## (Q14, owner 2026-10-26; PROVISIONAL numbers for #13).
@export var strength_per_preset: Dictionary[StringName, float] = {}
## A fleet run's encounters grow by this much strength per crewed ship beyond the first
## (multiplier points per ship, #11, FT-MIS-023, M4-Q1; 0: no scaling). PROVISIONAL for #13.
@export var fleet_strength_per_ship: float = 0.0
## LAST_STANDING raider waves (#11, M4-Q7): a wave at every surviving ship this often (s, 0:
## none), each wave's strength this much above the last (multiplier points). PROVISIONAL.
@export var raider_wave_every_s: float = 0.0
@export var raider_wave_growth: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	if budget_per_ship.is_empty():
		errors.append("budget_per_ship needs at least one preset")
	for preset: StringName in budget_per_ship:
		if budget_per_ship[preset] < 1:
			errors.append("budget_per_ship[%s] must be at least 1" % preset)
	DefCheck.non_negative(errors, "spawn_site_every_s", spawn_site_every_s)
	DefCheck.non_negative(errors, "gap_s", gap_s)
	DefCheck.positive(errors, "arrival_timeout_s", arrival_timeout_s)
	if max_open_sites < 0:
		errors.append("max_open_sites must be at least 0, got %d" % max_open_sites)
	for scenario: StringName in costs:
		# Every scenario costs at least 1; only the training scenario is free (Q14).
		var least: int = 0 if scenario == TRAINING else 1
		if costs[scenario] < least:
			errors.append("costs[%s] must be at least %d" % [scenario, least])
	DefCheck.non_negative(errors, "fleet_strength_per_ship", fleet_strength_per_ship)
	DefCheck.non_negative(errors, "raider_wave_every_s", raider_wave_every_s)
	DefCheck.non_negative(errors, "raider_wave_growth", raider_wave_growth)
	for preset: StringName in strength_per_preset:
		if not strength_per_preset[preset] > 0.0:
			errors.append("strength_per_preset[%s] must be > 0" % preset)
	return errors
