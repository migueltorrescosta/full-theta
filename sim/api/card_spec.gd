class_name CardSpec
extends RefCounted
## What a scenario offers a ship (ScenarioApi.offer, FT-COM-001, FT-COM-008): an input
## copy the API turns into a card on the ship's Comms board. Holds plain values only.

enum Kind { MISSION, CONTRACT, OFFER, HAIL }

var kind: Kind = Kind.MISSION
var npc_id: StringName = &""
var title_key: StringName = &""
var detail_key: StringName = &""
var conversation_id: StringName = &""
var reward_credits: int = 0
## RepDistDef id drawn when the card is done, or &"".
var rep_interaction: StringName = &""
## Contact ship the card is about, or -1.
var target: int = -1
## Contact flag set on its target when accepted (FT-MIS-042): 0 none, 1 disable, 2 protect.
var target_flag: int = 0
## Seconds until the card lapses (0: never).
var expires_s: float = 0.0
var requires_docked: bool = false
## Every ship of the ship's faction sees the card (D82).
var faction_wide: bool = false
## The faction reputation draws are with, or -1 for the target's faction.
var rep_faction: int = -1
## The site the card is tied to (a market), or -1.
var site: int = -1
## A clearance (P5): the approach lane opens this long after the card is accepted (s) and
## stays open lane_s (s); 0 for a card that isn't a clearance.
var lane_open_s: float = 0.0
var lane_s: float = 0.0
## Terms the ship may not meet (P12): this subsystem must supply this many pips.
var needs_subsystem: StringName = &""
var needs_pips: int = 0
