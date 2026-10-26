class_name PostCardCommand
extends SimCommand
## Server: puts a card on a ship's Comms board (the Scenario API's offer(); FT-COM-001,
## FT-COM-008). The fields are CardSpec's, plus faction_wide (every ship of the faction
## sees the card, D82) and rep_faction (the faction reputation draws are with; -1: the
## target's faction, if the card has a target). `kind` is a StoryTable.Kind. The card
## lapses expires_s after posting (0: never). Rejected for an unknown conversation.

var card_kind: int = 0
var npc_id: StringName = &""
var title_key: StringName = &""
var detail_key: StringName = &""
var conversation_id: StringName = &""
var reward_credits: int = 0
var rep_interaction: StringName = &""
var rep_faction: int = -1
var target: int = -1
var target_flag: int = 0
var expires_s: float = 0.0
var requires_docked: bool = false
var site: int = -1
var faction_wide: bool = false
# --- strand F ---
## A clearance (P5): the approach lane opens this long after the card is accepted (s) and
## stays open lane_s (s); 0 for a card that isn't a clearance.
var lane_open_s: float = 0.0
var lane_s: float = 0.0
## Terms the ship may not meet (P12): this subsystem must supply this many pips.
var needs_subsystem: StringName = &""
var needs_pips: int = 0
# --- end strand F ---


func kind() -> StringName:
	return &"post_card"


func apply(world: SimWorld) -> bool:
	if card_kind < 0 or card_kind > StoryTable.Kind.HAIL:
		return false
	if conversation_id != &"" and not world.conversations.has(conversation_id):
		return false
	if target_flag < 0 or target_flag > KnowledgeTable.Flag.PROTECT:
		return false
	if not _terms_valid():
		return false
	var t: StoryTable = world.story
	if t.size() == 0:
		StoryRules.sync_docks(world)
	var faction: int = world.faction_of(ship_id)
	var card: int = t.add_card(
		-1 if faction_wide else ship_id, faction, card_kind as StoryTable.Kind
	)
	t.npc[card] = npc_id
	t.title[card] = String(title_key)
	t.detail[card] = String(detail_key)
	t.conversation[card] = conversation_id
	t.expires_tick[card] = world.tick + ceili(expires_s * SimWorld.HZ) if expires_s > 0.0 else -1
	t.reward[card] = reward_credits
	t.rep_interaction[card] = rep_interaction
	t.target[card] = target
	t.rep_faction[card] = (
		rep_faction if rep_faction >= 0 else (world.faction_of(target) if target >= 0 else -1)
	)
	t.target_flag[card] = target_flag
	t.requires_docked[card] = 1 if requires_docked else 0
	t.site[card] = site
	StoryRules.set_lane(world, card, lane_open_s, lane_s)  # --- strand F ---
	StoryRules.set_need(world, card, needs_subsystem, needs_pips)
	world.emit(&"card_posted", ship_id, card, card_kind)
	return true


## The power terms (P12) are both set or both unset, with positive pips. The subsystem may
## be one the ship lacks: that is a term it cannot meet.
func _terms_valid() -> bool:
	return (needs_subsystem == &"") == (needs_pips == 0) and needs_pips >= 0
