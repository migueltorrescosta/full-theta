class_name ProbeTable
extends SimTable
## Launched probes (E02, FT-RLY-004, D56), one row per probe in launch order, keyed by
## the launching ship and its faction. A probe flies from the ship to its target point
## (ProbeSystem) and stays there: deployed, it covers a bubble around itself for its
## faction (ProbeSystem.coverage_at). Rows are added by launching, so add_ship adds
## none; reset_ship drops the ship's probes.

## Launch serial within the ship, from 0 (what the Relay panel lists).
var serial: PackedInt32Array = PackedInt32Array()
## Position in the cube (m, 64-bit, D104).
var pos_x: PackedFloat64Array = PackedFloat64Array()
var pos_y: PackedFloat64Array = PackedFloat64Array()
var pos_z: PackedFloat64Array = PackedFloat64Array()
## Destination point (m, wrapped).
var dest_x: PackedFloat64Array = PackedFloat64Array()
var dest_y: PackedFloat64Array = PackedFloat64Array()
var dest_z: PackedFloat64Array = PackedFloat64Array()
## 1 once the probe reached its target.
var deployed: PackedByteArray = PackedByteArray()


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Adds a probe at point `from` heading for point `to` (m); returns its row.
func launch(
	ship_id: int, faction: int, serial_no: int, from: PackedFloat64Array, to: PackedFloat64Array
) -> int:
	var row: int = add_key(ship_id, faction)
	serial.append(serial_no)
	CubePoint.append(pos_x, pos_y, pos_z, from)
	CubePoint.append(dest_x, dest_y, dest_z, to)
	deployed.append(0)
	return row


## Rows of the ship's probes keep their order, so the serials stay ascending.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	var keep: PackedInt32Array = PackedInt32Array()
	for r: int in size():
		if owner_ship[r] != ship_id:
			keep.append(r)
	for col: Array in columns():
		var name: String = col[0]
		var old: Variant = get(name)
		var fresh: Variant = old.duplicate()
		fresh.resize(keep.size())
		for i: int in keep.size():
			fresh[i] = old[keep[i]]
		set(name, fresh)
