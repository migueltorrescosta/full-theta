class_name CardView
extends RefCounted
## A value copy of one card on a ship's Comms board (FT-ARC-016, FT-DAT-009, FT-COM-001).

## The card states, the same numbers as StoryTable.State (scenarios name this, not the table).
enum State { OPEN, ACCEPTED, DECLINED, DONE, FAILED, EXPIRED }

var id: int = -1
## CardSpec.Kind value.
var kind: int = 0
## Card state: 0 open, 1 accepted, 2 declined, 3 done, 4 failed, 5 expired.
var state: int = 0
var npc_id: StringName = &""
var title_key: String = ""
var expires_tick: int = -1
var reward: int = 0
## Contact ship the card is about, or -1.
var target: int = -1
