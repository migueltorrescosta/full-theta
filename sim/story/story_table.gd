class_name StoryTable
extends SimTable
## STORY, the cards on Comms' board (FT-COM-001 to FT-COM-008, FT-PAIR-003). One row per
## card, keyed by the ship it was posted to and that ship's faction; ship_ids is -1 for a
## faction-wide card (D82: every ship of the faction sees it, the first to act on it
## settles it). Rows are added when a card is posted, in post order, and never removed, so
## a card's id is its row. Story flags and learned scan facts are StoryFlagTable's.

enum Kind { MISSION, CONTRACT, OFFER, HAIL }
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
	return row


func columns() -> Array:
	return (
		super()
		+ [
			["kind", kind],
			["state", state],
			["npc", npc],
			["title", title],
			["detail", detail],
			["conversation", conversation],
			["node", node],
			["expires_tick", expires_tick],
			["reward", reward],
			["rep_interaction", rep_interaction],
			["rep_faction", rep_faction],
			["target", target],
			["target_flag", target_flag],
			["requires_docked", requires_docked],
			["site", site],
			["verify", verify],
		]
	)


## Cards are faction state like knowledge: a ship reset leaves its rows alone.
func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass
