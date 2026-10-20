class_name ShieldTable
extends SimTable
## Shield strength, focus tightness and focus direction, one row per ship in id order
## (T031, FT-SIM-018). Total shield power is the shield subsystem's pips in DamageTable.

## Energy the shield can still absorb (J).
var strength: PackedFloat64Array = PackedFloat64Array()
## Focus tightness, set by Engineering (dimensionless, ShieldDef.tightness_min to max).
var tightness: PackedFloat64Array = PackedFloat64Array()
## Focus direction, set by Helm (unit vector, ship frame; D16, D48).
var focus: PackedVector3Array = PackedVector3Array()
## Ship the focus tracks (FT-HLM-010), or -1 for a fixed direction.
var track_id: PackedInt32Array = PackedInt32Array()
## 1 while the low-shield alert may fire; it re-arms above the alert fraction
## (FT-SIM-031).
var low_armed: PackedByteArray = PackedByteArray()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	add_key(ship_id, faction)
	strength.append(def.shields.max_strength)
	tightness.append(def.shields.tightness_min)
	focus.append(Vector3.FORWARD)
	track_id.append(-1)
	low_armed.append(1)


func columns() -> Array:
	return (
		super()
		+ [
			["strength", strength],
			["tightness", tightness],
			["focus", focus],
			["track_id", track_id],
			["low_armed", low_armed],
		]
	)
