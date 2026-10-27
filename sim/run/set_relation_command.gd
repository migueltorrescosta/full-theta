class_name SetRelationCommand
extends ServerCommand
## Sets the relation between two factions (E07, FT-MIS-016): the Scenario API's
## set_relation(). The relation is a SimWorld.Relation value.

var a: int = -1
var b: int = -1
var relation: int = SimWorld.Relation.HOSTILE


func kind() -> StringName:
	return &"set_relation"


func apply(world: SimWorld) -> bool:
	if a < 0 or b < 0 or a == b:
		return false
	if relation < SimWorld.Relation.FRIENDLY or relation > SimWorld.Relation.HOSTILE:
		return false
	world.set_relation(a, b, relation as SimWorld.Relation)
	return true
