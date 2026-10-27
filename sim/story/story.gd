class_name Story
extends RefCounted
## Helpers over the cards, conversations and story flags (FT-COM-001 to FT-COM-008,
## FT-MIS-036, FT-MIS-042): what the Comms commands share. Conversations are plain data
## parsed from content/conversations/*.json by app/ into SimWorld.conversations (the sim
## never reads JSON): {id, npc_role, start, nodes: {node: {line, options: [{id, text,
## requires, effects, next}]}}}. A node's `line` is a dialogue line id.

const DISABLE: StringName = &"disable"
const PROTECT: StringName = &"protect"
const INTENTS: Dictionary[StringName, int] = {
	&"unknown": KnowledgeTable.Intent.UNKNOWN,
	&"hostile": KnowledgeTable.Intent.HOSTILE,
	&"neutral": KnowledgeTable.Intent.NEUTRAL,
	&"surrendering": KnowledgeTable.Intent.SURRENDERING,
	&"bluffing": KnowledgeTable.Intent.BLUFFING,
}
const FLAGS: Dictionary[StringName, int] = {
	&"none": KnowledgeTable.Flag.NONE,
	&"disable": KnowledgeTable.Flag.DISABLE,
	&"protect": KnowledgeTable.Flag.PROTECT,
}


## The site the ship is docked at, or -1 (D86): HelmTable.docked_site (DockCommand).
static func docked_site(world: SimWorld, ship: int) -> int:
	if ship < 0 or ship >= world.helm.size():
		return -1
	return world.helm.docked_site[ship]


# --- cards ---


## Whether the card exists and is the ship's: posted to it, or faction-wide for its faction.
static func visible_to(world: SimWorld, card: int, ship: int) -> bool:
	var t: StoryTable = world.story
	if card < 0 or card >= t.size():
		return false
	return (
		t.ship_ids[card] == ship
		or (t.ship_ids[card] == -1 and t.factions[card] == world.faction_of(ship))
	)


## Id the next posted card will get.
static func next_card_id(world: SimWorld) -> int:
	return world.story.size()


## Whether the card can still be acted on (OPEN or ACCEPTED).
static func is_live(world: SimWorld, card: int) -> bool:
	var s: int = world.story.state[card]
	return s == StoryTable.State.OPEN or s == StoryTable.State.ACCEPTED


## Sets the card's state and tells the ship's Comms (event card_state: other_id the card,
## value the state). A card that is no longer live closes its conversation.
static func set_state(world: SimWorld, ship: int, card: int, state: StoryTable.State) -> void:
	world.story.state[card] = state
	if state != StoryTable.State.OPEN and state != StoryTable.State.ACCEPTED:
		world.story.node[card] = StoryTable.NO_TEXT
	world.emit(&"card_state", ship, card, state)


## A ship of the card's faction to address its events to: the card's own, or the first of a
## faction-wide card's faction.
static func audience_ship(world: SimWorld, card: int) -> int:
	var s: int = world.story.ship_ids[card]
	if s >= 0:
		return s
	return world.kin.factions.find(world.story.factions[card])


## Accepts a card for the ship (FT-COM-003): only an OPEN mission, contract or offer, not
## before docking if it needs it. The contract's target flag goes into the faction's KNOW
## (FT-MIS-042). Emits card_refused (tag the reason) when it can't.
static func accept(world: SimWorld, ship: int, card: int) -> bool:
	var t: StoryTable = world.story
	var why: StringName = &""
	if not visible_to(world, card, ship):
		why = &"no_card"
	elif t.state[card] != StoryTable.State.OPEN or t.kind[card] == StoryTable.Kind.HAIL:
		why = &"not_open"
	elif t.requires_docked[card] == 1 and not _docked_for(world, ship, card):
		why = &"requires_docked"
	if why != &"":
		world.emit(&"card_refused", ship, card, 0.0, Vector3.ZERO, why)
		return false
	set_state(world, ship, card, StoryTable.State.ACCEPTED)
	StoryRules.on_accept(world, card)  # P5: a clearance starts its clock
	if t.target_flag[card] != 0 and t.target[card] >= 0:
		world.knowledge.flag[world.knowledge.ensure_contact(t.factions[card], t.target[card])] = (
			t.target_flag[card]
		)
	return true


## Declines an OPEN card, or ends an answered hail (a live HAIL card becomes DONE, so
## the contact can be hailed again).
static func decline(world: SimWorld, ship: int, card: int) -> bool:
	var t: StoryTable = world.story
	var seen: bool = visible_to(world, card, ship)
	if seen and t.kind[card] == StoryTable.Kind.HAIL and is_live(world, card):
		set_state(world, ship, card, StoryTable.State.DONE)
		return true
	if not seen or t.state[card] != StoryTable.State.OPEN:
		world.emit(&"card_refused", ship, card, 0.0, Vector3.ZERO, &"not_open")
		return false
	set_state(world, ship, card, StoryTable.State.DECLINED)
	return true


static func _docked_for(world: SimWorld, ship: int, card: int) -> bool:
	var d: int = docked_site(world, ship)
	return d >= 0 and (world.story.site[card] < 0 or world.story.site[card] == d)


# --- conversations ---


## The card's conversation data, or {}.
static func conversation(world: SimWorld, card: int) -> Dictionary:
	return world.conversations.get(world.story.conversation[card], {})


## The card's open node data, or {} when no conversation is open.
static func node_of(world: SimWorld, card: int) -> Dictionary:
	var nodes: Dictionary = conversation(world, card).get("nodes", {})
	return nodes.get(String(world.story.node[card]), {})


## Opens a node: the NPC says its line (event say: tag the dialogue line id, other_id the
## card's contact ship or -1; the audience is the claimer, routed by net/voice).
static func open_node(world: SimWorld, ship: int, card: int, node_id: String) -> void:
	world.story.node[card] = StringName(node_id)
	var node: Dictionary = node_of(world, card)
	if not node.is_empty():
		say(world, ship, card, node["line"])


## The card's NPC says a dialogue line: event say, tag the line id, other_id the contact
## ship or -1, args["npc_id"] the speaker, args["card"] the card (ServerVoice routes it to that
## card's conversation claimer, or as a subtitle to Comms while nobody holds it; G1).
static func say(world: SimWorld, ship: int, card: int, line_id: String) -> void:
	var e: SimEvent = world.emit(
		&"say", ship, world.story.target[card], 0.0, Vector3.ZERO, StringName(line_id)
	)
	e.args = {"npc_id": String(world.story.npc[card]), "stations": [], "card": card}


## The names of every NPC on the board: they join the voice closed set at Start (FT-AUD-018).
static func npc_names(world: SimWorld) -> Array[String]:
	var out: Array[String] = []
	for n: StringName in world.story.npc:
		if n != &"" and not out.has(String(n)):
			out.append(String(n))
	for def: ShipDef in world.defs:
		if world.hail_conversations.has(def.id) and not out.has(def.display_name):
			out.append(def.display_name)
	return out


## The options of the card's open node as {id, text, enabled, verify} for the replying ship:
## `enabled` when its requirements hold, `verify` when it needs a scan fact (Science's icon, P14).
static func options(world: SimWorld, card: int, ship: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for option: Dictionary in node_of(world, card).get("options", []):
		var req: Dictionary = option.get("requires", {})
		(
			out
			. append(
				{
					"id": StringName(option["id"]),
					"text": String(option["text"]),
					"enabled": requirement_met(world, card, req, ship),
					"verify": req.has("scan_fact"),
				}
			)
		)
	return out


## Whether an option's `requires` holds: scan_fact (the faction learned the fact about
## the card's contact), flag (a story flag at least `min`, default 1), docked (the replying
## ship's own state, not the card's ship: a faction-wide card has none).
static func requirement_met(world: SimWorld, card: int, req: Dictionary, ship: int) -> bool:
	var t: StoryTable = world.story
	if (
		req.has("scan_fact")
		and not knows_fact(world, t.factions[card], t.target[card], req["scan_fact"])
	):
		return false
	if (
		req.has("flag")
		and world.story_flags.get_flag(StringName(req["flag"])) < int(req.get("min", 1))
	):
		return false
	if req.has("docked") and bool(req["docked"]) != (docked_site(world, ship) >= 0):
		return false
	return true


## Applies one option's effects in order, then follows `next` or ends the conversation.
## Effects (one key each): accept, decline, intent (unknown|hostile|neutral|surrendering|bluffing),
## contract_flag (none|disable|protect), flag (story flag name, with value), rep (a
## RepDistDef id), say (a dialogue line id), verify (a scan fact to check, P14), surrender
## ({base, per_damage, cap}: StoryRules.roll_surrender, P9). A refused accept or decline
## stops the option there (nothing is drawn, the node stays open) and returns false. A
## rep draw happens once per card, or once per contact on a hail (a new hail of the same
## contact doesn't repeat it).
static func apply_option(world: SimWorld, ship: int, card: int, option: Dictionary) -> bool:
	var t: StoryTable = world.story
	for effect: Dictionary in option.get("effects", []):
		if effect.has("accept") and not accept(world, ship, card):
			return false
		if effect.has("decline") and not decline(world, ship, card):
			return false
		if effect.has("intent") and t.target[card] >= 0:
			var row: int = world.knowledge.ensure_contact(t.factions[card], t.target[card])
			world.knowledge.intent[row] = INTENTS.get(
				StringName(effect["intent"]), KnowledgeTable.Intent.UNKNOWN
			)
		if effect.has("contract_flag") and t.target[card] >= 0:
			var frow: int = world.knowledge.ensure_contact(t.factions[card], t.target[card])
			world.knowledge.flag[frow] = FLAGS.get(StringName(effect["contract_flag"]), 0)
		if effect.has("flag"):
			world.story_flags.set_flag(StringName(effect["flag"]), int(effect.get("value", 1)))
		if (
			effect.has("rep")
			and t.rep_faction[card] >= 0
			and _first_draw(world, card, effect["rep"])
		):
			Reputation.change(
				world, ship, t.factions[card], t.rep_faction[card], StringName(effect["rep"])
			)
		if effect.has("say"):
			say(world, ship, card, effect["say"])
		if effect.has("verify"):
			t.verify[card] = StringName(effect["verify"])
		# (P9: ask the contact to surrender)
		if effect.has("surrender") and t.target[card] >= 0:
			StoryRules.roll_surrender(world, ship, card, effect["surrender"])
	if not is_live(world, card):
		return true
	var nodes: Dictionary = conversation(world, card).get("nodes", {})
	if option.has("next") and nodes.has(option["next"]):
		open_node(world, ship, card, option["next"])
	else:
		t.node[card] = StoryTable.NO_TEXT
		if t.kind[card] == StoryTable.Kind.HAIL:
			set_state(world, ship, card, StoryTable.State.DONE)
	return true


## Whether this reputation draw has not been made yet for the card (a hail: for its
## contact), and marks it made.
static func _first_draw(world: SimWorld, card: int, dist: String) -> bool:
	var t: StoryTable = world.story
	var who: String = "c%d" % card
	if t.kind[card] == StoryTable.Kind.HAIL and t.target[card] >= 0:
		who = "t%d.%d" % [t.factions[card], t.target[card]]
	var flag: StringName = StringName("repdraw.%s.%s" % [who, dist])
	if world.story_flags.get_flag(flag) == 1:
		return false
	world.story_flags.set_flag(flag, 1)
	return true


# --- scan facts (P14) ---


static func _fact_flag(faction: int, contact: int, fact: String) -> StringName:
	return StringName("fact.%d.%d.%s" % [faction, contact, fact])


## Records that the faction learned a fact about a contact (Science's scan, F's rule).
static func learn_fact(world: SimWorld, faction: int, contact: int, fact: String) -> void:
	world.story_flags.set_flag(_fact_flag(faction, contact, fact), 1)


static func knows_fact(world: SimWorld, faction: int, contact: int, fact: String) -> bool:
	return world.story_flags.get_flag(_fact_flag(faction, contact, fact)) == 1
