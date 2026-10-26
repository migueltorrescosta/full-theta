class_name HailCommand
extends SimCommand
## Comms hails a contact (FT-COM-002, D53): opens a HAIL card on the ship's board with the
## contact's conversation (SimWorld.hail_conversations, by the contact's ShipDef id) at
## once, since the contact picks up. Refused (event hail_refused, tag the reason) for a
## contact the ship's faction doesn't detect, one with nothing to say, or one it is
## already talking to.

var target: int = -1


func kind() -> StringName:
	return &"comms_hail"


func apply(world: SimWorld) -> bool:
	var faction: int = world.faction_of(ship_id)
	var why: StringName = &""
	var conv: StringName = &""
	if target < 0 or target >= world.ship_count() or target == ship_id:
		why = &"no_target"
	elif not world.kin.is_alive(target) or not KnowledgeSystem.is_detected(world, faction, target):
		why = &"not_detected"
	else:
		conv = world.hail_conversations.get(world.defs[target].id, &"")
		if not world.conversations.has(conv):
			why = &"no_answer"
	var t: StoryTable = world.story
	if why == &"":
		for card: int in t.size():
			if (
				t.kind[card] == StoryTable.Kind.HAIL
				and t.target[card] == target
				and Story.visible_to(world, card, ship_id)
				and Story.is_live(world, card)
			):
				why = &"already_talking"
	if why != &"":
		world.emit(&"hail_refused", ship_id, target, 0.0, Vector3.ZERO, why)
		return false
	var card: int = t.add_card(ship_id, faction, StoryTable.Kind.HAIL)
	t.state[card] = StoryTable.State.ACCEPTED
	t.npc[card] = world.defs[target].id
	t.title[card] = "comms.card.hail"
	t.conversation[card] = conv
	t.target[card] = target
	t.rep_faction[card] = world.faction_of(target)
	world.emit(&"card_posted", ship_id, card, StoryTable.Kind.HAIL)
	Story.open_node(world, ship_id, card, world.conversations[conv]["start"])
	return true
