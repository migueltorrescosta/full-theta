class_name ProbeTable
extends SimTable
## Launched probes (E02, FT-RLY-004, D56), one row per probe in launch order, keyed by
## the launching ship and its faction. A probe flies from the ship to its target point
## (ProbeSystem) and stays there: deployed, it covers a bubble around itself for its
## faction (ProbeSystem.coverage_at). Rows are added by launching, so add_ship adds
## none; reset_ship drops the ship's probes.

## Launch serial within the ship, from 0 (what the Relay panel lists).
var serial: PackedInt32Array = PackedInt32Array()
var site: PackedInt32Array = PackedInt32Array()
## Site-local position (m, 64-bit, D104).
var px: PackedFloat64Array = PackedFloat64Array()
var py: PackedFloat64Array = PackedFloat64Array()
var pz: PackedFloat64Array = PackedFloat64Array()
## Target point (m, wrapped).
var tx: PackedFloat64Array = PackedFloat64Array()
var ty: PackedFloat64Array = PackedFloat64Array()
var tz: PackedFloat64Array = PackedFloat64Array()
## 1 once the probe reached its target.
var deployed: PackedByteArray = PackedByteArray()


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Adds a probe at (x, y, z) heading for (tx, ty, tz); returns its row.
func launch(
	ship_id: int, faction: int, serial_no: int, site_id: int, from: Vector3, to: Vector3
) -> int:
	var row: int = add_key(ship_id, faction)
	serial.append(serial_no)
	site.append(site_id)
	px.append(from.x)
	py.append(from.y)
	pz.append(from.z)
	tx.append(to.x)
	ty.append(to.y)
	tz.append(to.z)
	deployed.append(0)
	return row


## Rows of the ship's probes keep their order, so the serials stay ascending.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	var keep: PackedInt32Array = PackedInt32Array()
	for r: int in size():
		if ship_ids[r] != ship_id:
			keep.append(r)
	for col: Array in columns():
		var name: String = col[0]
		var old: Variant = get(name)
		var fresh: Variant = old.duplicate()
		fresh.resize(keep.size())
		for i: int in keep.size():
			fresh[i] = old[keep[i]]
		set(name, fresh)


func columns() -> Array:
	return (
		super()
		+ [
			["serial", serial],
			["site", site],
			["px", px],
			["py", py],
			["pz", pz],
			["tx", tx],
			["ty", ty],
			["tz", tz],
			["deployed", deployed],
		]
	)
