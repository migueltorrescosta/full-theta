class_name AnswerHailCommand
extends SimCommand
## Comms answers an incoming hail card (FT-COM-002): the card turns ACCEPTED and its
## conversation opens at the start node, where the NPC speaks. On any other card with a
## conversation it opens that conversation the same way (D87: the overlay), leaving the
## card's state alone.

var card: int = -1


func kind() -> StringName:
	return &"comms_answer"


func apply(world: SimWorld) -> bool:
	var t: StoryTable = world.story
	var hail: bool = Story.visible_to(world, card, ship_id) and t.kind[card] == StoryTable.Kind.HAIL
	if (
		not Story.visible_to(world, card, ship_id)
		or not world.conversations.has(t.conversation[card])
		or t.node[card] != StoryTable.NO_TEXT
		or not (t.state[card] == StoryTable.State.OPEN or (not hail and Story.is_live(world, card)))
	):
		world.emit(&"card_refused", ship_id, card, 0.0, Vector3.ZERO, &"not_open")
		return false
	if hail:
		Story.set_state(world, ship_id, card, StoryTable.State.ACCEPTED)
	Story.open_node(world, ship_id, card, world.conversations[t.conversation[card]]["start"])
	return true
