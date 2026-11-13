class_name RunDriver
extends RefCounted
## What drives a run between the server's ticks (F10, R12-15, R14-6): the encounter Director,
## the FleetDirector of a multi-ship game and the Shakedown's TrainingDriver. NetServer holds
## one and calls it through this interface only, through the Scenario API (FT-ARC-016).


## Called before each sim tick, with the Scenario API of the world.
func before_tick(_api: ScenarioApi) -> void:
	pass


## The decisions logged so far, for the debrief (FT-MIS-006); none by default.
func decisions() -> Array[DirectorDecision]:
	return []


## The station a solo lesson's player holds, &"" outside one (D303): NetServer lets the
## lesson's bots act for the other stations first.
func solo_station() -> StringName:
	return &""


## The crew-chosen site offers (E2, w-bzx) of the faction's current quiet gap, in offer order
## (the first is the director's own pick): [{site: int (the site id), name_key: String (the
## site's name key), risk: int (DirectorDef.offer_risk), reward: int (DirectorDef.offer_reward)}];
## empty outside a gap, before a finale, in a race or with DirectorDef.site_offers below 2. With
## one free site or one scenario fitting there is a single offer (no choice to show).
func site_offers(_faction: int) -> Array[Dictionary]:
	return []
