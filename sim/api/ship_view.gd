class_name ShipView
extends RefCounted
## A value copy of one ship (FT-ARC-016, FT-DAT-009), built fresh on each ScenarioApi call.
## Holds only plain values, so a scenario cannot reach the world through it.

var id: int = -1
var faction: int = -1
## Cube offset (m, 64-bit values: x, y, z).
var pos: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var velocity: Vector3 = Vector3.ZERO
## Site id nearest the ship, or -1 with no site.
var nearest_site: int = -1
## Site id whose radius holds the ship, or -1 outside every radius.
var at_site: int = -1
var hull_frac: float = 0.0
## RunTable.Status and RunTable.Outcome values.
var status: int = 0
## Alive and still in the run (status IN_PLAY): a scenario's "is it still out there".
var in_play: bool = false
var outcome: int = 0
## Site id the ship is docked at, or -1.
var docked_site: int = -1
var jumping: bool = false
