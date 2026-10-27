class_name ReplyCommand
extends SimCommand
## Comms picks a reply in the open conversation (FT-COM-007, FT-COM-001): a structured
## choice by option id, never free text. The option's effects apply (Story.apply_option:
## intent, contract flag, reputation draw, accept, story flag), then the conversation moves
## to its next node or ends. Refused for no open conversation, an unknown option, or one
## whose requirements fail (event reply_refused, tag the reason).

var card: int = -1
var option: StringName = &""


func kind() -> StringName:
	return &"comms_reply"


func apply(world: SimWorld) -> bool:
	var why: StringName = &""
	var chosen: Dictionary = {}
	if not Story.visible_to(world, card, ship_id) or world.story.node[card] == StoryTable.NO_TEXT:
		why = &"no_conversation"
	elif not Story.is_live(world, card):
		why = &"not_open"
	else:
		for o: Dictionary in Story.node_of(world, card).get("options", []):
			if StringName(o["id"]) == option:
				chosen = o
		if chosen.is_empty():
			why = &"no_option"
		elif not Story.requirement_met(world, card, chosen.get("requires", {}), ship_id):
			why = &"requirement"
	if why != &"":
		world.emit(&"reply_refused", ship_id, card, 0.0, Vector3.ZERO, why)
		return false
	world.emit(&"reply", ship_id, card, 0.0, Vector3.ZERO, option)
	if not Story.apply_option(world, ship_id, card, chosen):
		world.emit(&"reply_refused", ship_id, card, 0.0, Vector3.ZERO, &"effect_refused")
		return false
	# (P14: an option a scan fact unlocked, counted for the debrief once it went through)
	var req: Dictionary = chosen.get("requires", {})
	if req.has("scan_fact"):
		world.emit(&"scan_option", ship_id, card, 0.0, Vector3.ZERO, StringName(req["scan_fact"]))
	return true
