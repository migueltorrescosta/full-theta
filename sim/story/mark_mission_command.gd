class_name MarkMissionCommand
extends SimCommand
## Relay marks a mission's place (P15, FT-PAIR-001): the mission card is located, which
## Comms' board shows as the mission mark icon under the mission_icon toggle (a shortcut
## Relay shares). The mark itself is Relay's, a MARK item outside the sim; this records
## that the mission has one. Refused for a card the ship can't see or that isn't live.

var card: int = -1


func kind() -> StringName:
	return &"relay_mark_mission"


func apply(world: SimWorld) -> bool:
	return StoryRules.mark_mission(world, ship_id, card)
