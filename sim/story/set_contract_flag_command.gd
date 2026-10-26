class_name SetContractFlagCommand
extends SimCommand
## Server: sets a contract target flag on a contact in a faction's KNOW (the Scenario API's
## set_contract_flag(); FT-MIS-042, D82). ship_id is any ship of the faction.

var faction: int = -1
var contact: int = -1
## KnowledgeTable.Flag value.
var flag: int = 0


func kind() -> StringName:
	return &"set_contract_flag"


func apply(world: SimWorld) -> bool:
	if (
		faction < 0
		or contact < 0
		or contact >= world.ship_count()
		or flag < KnowledgeTable.Flag.NONE
		or flag > KnowledgeTable.Flag.PROTECT
		or world.faction_of(contact) == faction
	):
		return false
	world.knowledge.flag[world.knowledge.ensure_contact(faction, contact)] = flag
	return true
