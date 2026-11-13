class_name StandInDef
extends Resource
## The stand-in crew (gp-01, gp-03; #40 D1, D2): the novice bots that hold a dropped player's
## stations after the grace and the light stations nobody took when the host fills them
## (StandInCrew). Numbers follow tools/bots/profiles.gd's novice. PROVISIONAL: #13 tunes them.
## Read-only at runtime (FT-ARC-020).

@export var id: StringName = &""
## Seconds between two looks of one bot at its station (each bot a seeded phase apart).
@export var look_every: float = 2.0
## Seconds a new target must have stood before Weapons fires at it.
@export var reaction_time: float = 8.0
## Seconds between two aim updates, and between two due shots.
@export var aim_every: float = 0.2
@export var fire_every: float = 0.6
## Aim error (rad, a random direction); 0 is a perfect lead.
@export var aim_error: float = 0.001
## Share of due shots Weapons does not fire (0..1).
@export var fire_skip: float = 0.1
## How far Helm and Weapons look for a hostile, and how far Weapons shoots (m).
@export var sight_reach: float = 12000.0
@export var shoot_reach: float = 5800.0
## Helm's speed while it faces a hostile (m/s): full throttle below it, none above.
@export var cruise_ms: float = 120.0
## Helm jumps once the bow is within this share of the ship's jump tolerance (0..1].
@export var jump_aim_share: float = 0.8
## Players a ship needs when the host fills light stations with bots (gp-03).
@export var fill_min_players: int = 2


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	for field: String in [
		"look_every", "aim_every", "fire_every", "sight_reach", "shoot_reach", "cruise_ms"
	]:
		DefCheck.positive(errors, field, get(field))
	DefCheck.non_negative(errors, "reaction_time", reaction_time)
	DefCheck.non_negative(errors, "aim_error", aim_error)
	DefCheck.in_range(errors, "fire_skip", fire_skip, 0.0, 1.0)
	DefCheck.in_range_open_low(errors, "jump_aim_share", jump_aim_share, 0.0, 1.0)
	DefCheck.in_range(errors, "fill_min_players", fill_min_players, 1, 6)
	return errors
