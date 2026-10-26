class_name PostCardCommand
extends SimCommand
## STUB until strand C merges (#10): C's sim/story/post_card_command.gd replaces this file.
## Same fields as C's. Delete with tests/stubs/.

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


func _init() -> void:
	source = Source.SERVER


func kind() -> StringName:
	return &"post_card"
