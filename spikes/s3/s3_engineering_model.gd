class_name S3EngineeringModel
extends RefCounted
## Toy Engineering state for one ship: power pips per system within a reactor
## cap, and heat that rises above the nominal pip count and cools below it
## (FT-ENG-002 in spirit; the real model is T033). Pure: no nodes, no I/O.

const SYSTEMS: Array[String] = ["ENG", "WPN", "SHD", "SNS", "MAN"]
const MAX_PIPS: int = 4
const NOMINAL_PIPS: int = 2
const REACTOR_CAP: int = 12
## Heat change per second per pip above (or below) nominal, as a share of 1.0.
const HEAT_RATE: float = 0.05

var pips: PackedInt32Array = PackedInt32Array()
var heat: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	pips.resize(SYSTEMS.size())
	pips.fill(NOMINAL_PIPS)
	heat.resize(SYSTEMS.size())
	heat.fill(0.2)


func used() -> int:
	var total: int = 0
	for p: int in pips:
		total += p
	return total


## Sets a system's pips, clamped to 0..MAX_PIPS and to what the cap leaves.
## Returns the value applied.
func set_pips(system: int, value: int) -> int:
	if system < 0 or system >= pips.size():
		return -1
	var others: int = used() - pips[system]
	var applied: int = clampi(value, 0, mini(MAX_PIPS, REACTOR_CAP - others))
	pips[system] = applied
	return applied


func step(dt: float) -> void:
	for i: int in range(pips.size()):
		var rate: float = HEAT_RATE * (pips[i] - NOMINAL_PIPS) - 0.01
		heat[i] = clampf(heat[i] + rate * dt, 0.0, 1.0)
