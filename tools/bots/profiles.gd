class_name BotProfiles
extends RefCounted
## The scripted crews of the bot batch (FT-TST-022, FT-MIS-009, FT-MIS-037): numbers only,
## BotCrew reads them. "average" is a competent crew; "novice" is a first-time crew on Easy:
## slower to react, loose aim, fires less, flies by impulse half the time and picks cards at
## random. Everything is a plain number so #13 can tune a profile without touching BotCrew.

const NAMES: PackedStringArray = ["average", "novice"]


class Profile:
	extends RefCounted
	var name: String = ""
	## Seconds a new situation (a hostile in range, a card) must have stood before the crew acts.
	var reaction_s: float = 3.0
	## Ticks between two looks at the world (60 Hz).
	var think_ticks: int = 3
	## Ticks between two aim updates and two shots.
	var aim_every: int = 6
	var fire_every: int = 30
	## Aim error (rad, a random direction); 0 is a perfect lead.
	var aim_error: float = 0.0
	## Share of due shots the crew does not fire (0..1).
	var fire_skip: float = 0.0
	## Hull fraction below which the crew jumps away from a fight.
	var flee_hull: float = 0.25
	## Share of trips made with the jump drive; the rest are flown by impulse (approach).
	var jump_share: float = 1.0
	## Whether Engineering puts the spare pips on the weapons.
	var sets_pips: bool = true
	## Whether Engineering sends repair crews to damaged subsystems, and how often it looks (ticks).
	var repairs: bool = true
	var repair_every: int = 90
	## Whether Weapons shoots unarmed hostile debris on the route.
	var shoots_debris: bool = true
	## Seconds before Comms acts on a card, and which cards: "escort" takes the escort and the
	## lane run, "random" takes each card with probability accept_chance, "none" takes none.
	var comms_s: float = 6.0
	var accept: String = "escort"
	var accept_chance: float = 0.5
	## Whether Comms demands the surrender of a hailing raider.
	var demands_surrender: bool = true


static func named(profile_name: String) -> Profile:
	match profile_name:
		"novice":
			return novice()
	return average()


static func average() -> Profile:
	var p: Profile = Profile.new()
	p.name = "average"
	return p


static func novice() -> Profile:
	var p: Profile = Profile.new()
	p.name = "novice"
	p.reaction_s = 8.0
	p.aim_every = 12
	p.fire_every = 36
	p.aim_error = 0.001
	p.fire_skip = 0.1
	p.flee_hull = 0.2
	p.jump_share = 0.5
	p.repair_every = 180
	p.shoots_debris = false
	p.comms_s = 25.0
	p.accept = "random"
	p.demands_surrender = false
	return p
