class_name ReputationTable
extends SimTable
## Reputation per faction (FT-MIS-018, FT-MIS-019, D34): one row per (rating faction,
## other faction) pair, added the first time a change touches it, in the order changes
## happen. Key columns, as in KnowledgeTable: `factions` holds the faction whose standing
## it is (the crew's) and `ship_ids` the OTHER faction it is with. Faction state, so a
## ship reset leaves it alone. Values are clamped to MIN..MAX by Reputation.apply.

const MIN: float = -100.0
const MAX: float = 100.0

var value: PackedFloat32Array = PackedFloat32Array()

## Derived index, not state: row by faction * 65536 + other faction.
var _rows: Dictionary[int, int] = {}


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Row of the pair, or -1 when it was never touched.
func row_for(faction: int, other: int) -> int:
	return _rows.get(faction * 65536 + other, -1)


## The standing of faction with other (0 when never touched).
func value_of(faction: int, other: int) -> float:
	var r: int = row_for(faction, other)
	return value[r] if r >= 0 else 0.0


## The pair's row, added at 0 when new.
func ensure(faction: int, other: int) -> int:
	var r: int = row_for(faction, other)
	if r < 0:
		r = add_key(other, faction)
		value.append(0.0)
		_rows[faction * 65536 + other] = r
	return r


## The other factions faction has a standing with, in row order.
func others_of(faction: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: int in size():
		if factions[r] == faction:
			out.append(ship_ids[r])
	return out


func columns() -> Array:
	return super() + [["value", value]]


func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass
