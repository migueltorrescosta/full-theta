class_name CardResultCommand
extends SimCommand
## Server: settles an accepted card (FT-MIS-021, FT-MIS-019). Success pays the card's reward
## to ship_id and draws the card's reputation change; failure draws the change named
## "<rep_interaction>.fail" if there is one (FT-COM-005). Scenarios submit it when the
## mission's objective is met or lost.

var card: int = -1
var success: bool = true


func kind() -> StringName:
	return &"card_result"


func apply(world: SimWorld) -> bool:
	var t: StoryTable = world.story
	if not Story.visible_to(world, card, ship_id) or not Story.is_live(world, card):
		return false
	Story.set_state(
		world, ship_id, card, StoryTable.State.DONE if success else StoryTable.State.FAILED
	)
	var dist: StringName = t.rep_interaction[card]
	if success:
		Economy.add_credits(world, ship_id, t.reward[card])
	elif dist != &"":
		dist = StringName(String(dist) + ".fail")
	if dist != &"" and t.rep_faction[card] >= 0:
		Reputation.change(world, ship_id, t.factions[card], t.rep_faction[card], dist)
	return true
