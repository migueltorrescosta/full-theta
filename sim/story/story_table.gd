class_name StoryTable
extends SimTable
## STORY, the cards on Comms' board (FT-COM-001 to FT-COM-008, FT-PAIR-003). One row per
## card, keyed by the ship it was posted to and that ship's faction; owner_ship is -1 for a
## faction-wide card (D82: every ship of the faction sees it, the first to act on it
## settles it). Rows are added when a card is posted, in post order, and never removed, so
## a card's id is its row. Each ship's dock watch is StoryShipTable's, what a faction learned
## of a contact is KnowledgeTable's, and StoryFlagTable holds the scenarios' own flags.

## INFO: a card that only tells (Q23), nothing to accept.
enum Kind { MISSION, CONTRACT, OFFER, HAIL, INFO }
enum State { OPEN, ACCEPTED, DECLINED, DONE, FAILED, EXPIRED }

## State: &"" means none in the StringName columns.
const NO_TEXT: StringName = &""

var kind: PackedByteArray = PackedByteArray()
var state: PackedByteArray = PackedByteArray()
## The NPC's id (a name the closed set of NPC voices knows).
var npc: Array[StringName] = []
## I18n keys of the card's title and detail text.
var title: Array[String] = []
var detail: Array[String] = []
## The conversation's id (SimWorld.conversations), or none.
var conversation: Array[StringName] = []
## The conversation's current node, or none when it isn't open.
var node: Array[StringName] = []
## Tick the card lapses at, or -1 for never.
var expires_tick: PackedInt32Array = PackedInt32Array()
var reward: PackedInt32Array = PackedInt32Array()
## The RepDistDef id drawn when the card is done, or none.
var rep_interaction: Array[StringName] = []
## The faction the reputation draws are with (-1: none).
var rep_faction: PackedInt32Array = PackedInt32Array()
## The contact ship the card is about (-1: none).
var target: PackedInt32Array = PackedInt32Array()
## KnowledgeTable.Flag the card puts on its target when accepted (0: none).
var target_flag: PackedByteArray = PackedByteArray()
## 1 if the card can be accepted only while docked (FT-MIS-036).
var requires_docked: PackedByteArray = PackedByteArray()
## The site the card is tied to, for a market (-1: none).
var site: PackedInt32Array = PackedInt32Array()
## The scan fact a conversation asked the crew to verify (P14), or none.
var verify: Array[StringName] = []
## The ship that accepted the card, plus one (0: none yet; Story.audience_ship).
var claim: PackedInt32Array = PackedInt32Array()
## A clearance's approach lane (P5, StoryRules.set_lane): the lane opens lane_open ticks
## after the accept and stays open lane_len ticks (0: not a clearance); lane_t0 is the
## accept tick plus one (0: not accepted yet).
var lane_open: PackedInt32Array = PackedInt32Array()
var lane_len: PackedInt32Array = PackedInt32Array()
var lane_t0: PackedInt32Array = PackedInt32Array()
## The offer's terms (P12, StoryRules.set_need): pips of power on a subsystem (0: none).
var need_subsystem: Array[StringName] = []
var need_pips: PackedInt32Array = PackedInt32Array()
## 1 once Relay marked the mission's place (P15).
var marked: PackedByteArray = PackedByteArray()
## The RepDistDef ids already drawn for the card (Story._first_draw; a hail draws per
## contact, in KnowledgeTable.rep_drawn). Replaced whole, never changed in place.
var rep_drawn: Array[PackedStringArray] = []


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Adds a card row with defaults and returns its id (the row).
func add_card(ship: int, faction: int, card_kind: Kind) -> int:
	var row: int = add_key(ship, faction)
	kind.append(card_kind)
	state.append(State.OPEN)
	npc.append(NO_TEXT)
	title.append("")
	detail.append("")
	conversation.append(NO_TEXT)
	node.append(NO_TEXT)
	expires_tick.append(-1)
	reward.append(0)
	rep_interaction.append(NO_TEXT)
	rep_faction.append(-1)
	target.append(-1)
	target_flag.append(0)
	requires_docked.append(0)
	site.append(-1)
	verify.append(NO_TEXT)
	claim.append(0)
	lane_open.append(0)
	lane_len.append(0)
	lane_t0.append(0)
	need_subsystem.append(NO_TEXT)
	need_pips.append(0)
	marked.append(0)
	rep_drawn.append(PackedStringArray())
	return row


## Cards are faction state like knowledge: a ship reset leaves its rows alone.
func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass
