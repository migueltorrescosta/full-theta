class_name StoryFlagTable
extends SimTable
## Story flags (FT-PAIR-003): named integers scenarios set and read, and the scan facts
## the crew learned (Story.learn_fact stores them as flags named fact.<faction>.<contact>.
## <fact>). One row per name in the order first set; keys are -1 (world state).

var names: Array[StringName] = []
var values: PackedInt32Array = PackedInt32Array()


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## The flag's value, 0 when never set.
func get_flag(name: StringName) -> int:
	var r: int = names.find(name)
	return values[r] if r >= 0 else 0


func set_flag(name: StringName, value: int) -> void:
	var r: int = names.find(name)
	if r < 0:
		add_key(-1, -1)
		names.append(name)
		values.append(value)
	else:
		values[r] = value


func columns() -> Array:
	return super() + [["names", names], ["values", values]]


func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass
