class_name SetContractFlagCommand
extends SimCommand
## STUB until strand C merges (#10): C's sim/story/set_contract_flag_command.gd replaces
## this file. Same fields as C's. Delete with tests/stubs/.

var faction: int = -1
var contact: int = -1
var flag: int = 0


func _init() -> void:
	source = Source.SERVER


func kind() -> StringName:
	return &"set_contract_flag"
