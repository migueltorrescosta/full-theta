class_name HailCommand
extends SimCommand
## Comms hails a contact (FT-COM-002, D53): opens a HAIL card on the ship's board with the
## contact's conversation (SimWorld.hail_conversations, by the contact's ShipDef id) at
## once, since the contact picks up. Refused (event hail_refused, tag the reason) for a
## contact the ship's faction doesn't detect, one with nothing to say, or one it is
## already talking to.

var contact: int = -1


func kind() -> StringName:
	return &"comms_hail"


func apply(world: SimWorld) -> bool:
	var faction: int = world.faction_of(ship_id)
	var why: StringName = &""
	var conv: StringName = &""
	if not world.has_ship(contact) or contact == ship_id:
		why = &"no_target"
	elif (
		not world.kin.is_alive(contact) or not KnowledgeSystem.is_detected(world, faction, contact)
	):
		why = &"not_detected"
	else:
		conv = world.hail_conversations.get(world.defs[contact].id, &"")
		if not world.conversations.has(conv):
			why = &"no_answer"
	var t: StoryTable = world.story
	if why == &"":
		for card: int in t.size():
			if (
				t.kind[card] == StoryTable.Kind.HAIL
				and t.subject[card] == contact
				and Story.visible_to(world, card, ship_id)
				and Story.is_live(world, card)
			):
				why = &"already_talking"
	if why != &"":
		world.emit(&"hail_refused", ship_id, contact, 0.0, Vector3.ZERO, why)
		return false
	var card: int = t.add_card(ship_id, faction, StoryTable.Kind.HAIL)
	t.state[card] = StoryTable.State.ACCEPTED
	t.npc[card] = StringName(world.defs[contact].display_name)
	t.title[card] = "comms.card.hail"
	t.conversation[card] = conv
	t.subject[card] = contact
	t.rep_faction[card] = world.faction_of(contact)
	world.emit(&"card_posted", ship_id, card, StoryTable.Kind.HAIL)
	Story.open_node(world, ship_id, card, world.conversations[conv]["start"])
	return true
