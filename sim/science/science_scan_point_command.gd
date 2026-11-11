class_name ScienceScanPointCommand
extends SimCommand
## The server keeps the ship's scan point on its crew-state scan position (D378, 12r-27):
## sent when that position moves or goes (a Relay op), never by a client, so the sim never
## reads crew state (D171). See ScienceSystem.set_scan_point.

var scan_x: float = 0.0
var scan_y: float = 0.0
var scan_z: float = 0.0
## True: the ship has no scan position any more.
var clear: bool = false


func _init() -> void:
	source = Source.SERVER


func kind() -> StringName:
	return &"science_scan_point"


func apply(world: SimWorld) -> bool:
	var at: PackedFloat64Array = PackedFloat64Array()
	if not clear:
		at = PackedFloat64Array([scan_x, scan_y, scan_z])
	return ScienceSystem.set_scan_point(world, ship_id, at)
