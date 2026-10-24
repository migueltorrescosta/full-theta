class_name RelayTable
extends SimTable
## Relay's per-ship state (E02, FT-RLY-004, FT-RLY-011, D56): the probe stock, the
## fabrication in progress, how many probes the ship launched (the next probe's serial)
## and the lane-flag switch with the friendly the last warning named. Probes themselves
## are ProbeTable rows. Marks, routes and the inbox are server crew state outside the
## sim (CrewMarks), not here.

## Probes left to launch.
var stock: PackedInt32Array = PackedInt32Array()
## Seconds until Engineering's probe is built; 0 when none is being built.
var fab_left: PackedFloat64Array = PackedFloat64Array()
## Probes launched so far; the next one gets this serial.
var launched: PackedInt32Array = PackedInt32Array()
## 1 while Relay's lane flagging is on (FlagLanesCommand).
var lanes_flagged: PackedByteArray = PackedByteArray()
## The ship a lane warning last named (-1 none): a warning fires once per crossing.
var lane_warned: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	add_key(ship_id, faction)
	stock.append(def.probes)
	fab_left.append(0.0)
	launched.append(0)
	lanes_flagged.append(0)
	lane_warned.append(-1)


func columns() -> Array:
	return (
		super()
		+ [
			["stock", stock],
			["fab_left", fab_left],
			["launched", launched],
			["lanes_flagged", lanes_flagged],
			["lane_warned", lane_warned],
		]
	)
