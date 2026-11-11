class_name ScienceTable
extends SimTable
## Science state, one row per ship keyed by ship id and faction (E01, FT-SCI-003,
## FT-SCI-004 to FT-SCI-011): the sensor mode and active ping, the selected contact, the
## scan point (the sim's copy of the crew-state scan position, FT-SCI-010), the one open
## minigame session and the own-ship scan. What each faction has learned of a contact is
## in KnowledgeTable.scan_conf; hack windows on the target are in HackTable. A session
## stores only its puzzle_seed and numbers: the puzzle is regenerated from them (ScanPuzzle,
## HackPuzzle), so state stays small and replays reproduce it.

## What the ship's open session is.
enum Session { NONE, SCAN, HACK, SELF }

## scan_x while the ship has no scan point.
const NO_POINT: float = INF

## 1 while the sensors are in active mode (FT-SCI-003).
var active: PackedByteArray = PackedByteArray()
## Seconds left of the active ping's low-noise window.
var ping_left: PackedFloat64Array = PackedFloat64Array()
## Seconds until the next ping may start.
var ping_cool: PackedFloat64Array = PackedFloat64Array()
## Contact the Science panel has selected (noise preview), or -1.
var selected: PackedInt32Array = PackedInt32Array()
## The scan point (m, 64-bit like Kinematics; scan_x NO_POINT for none): where the ship's
## scans get mark_factor (P3). ScienceMarkCommand sets it, and the server keeps it on the
## crew-state scan position with ScienceScanPointCommand (D378, 12r-27; the sim never
## reads crew state, D171).
var scan_x: PackedFloat64Array = PackedFloat64Array()
var scan_y: PackedFloat64Array = PackedFloat64Array()
var scan_z: PackedFloat64Array = PackedFloat64Array()
## Session kind (enum Session).
var kind: PackedByteArray = PackedByteArray()
## Ship id of the session's contact (or -1).
var target: PackedInt32Array = PackedInt32Array()
## Seed the session's puzzle is generated from.
var puzzle_seed: PackedInt64Array = PackedInt64Array()
## Scan noise at the start of the session (0..1).
var noise: PackedFloat64Array = PackedFloat64Array()
## Tick the session started on.
var start_tick: PackedInt32Array = PackedInt32Array()
## Hack: index of the chosen subsystem in the contact's ShipDef.subsystems.
var subsystem: PackedInt32Array = PackedInt32Array()
## Scan: bit a set for each rotation axis the player must set (x, y, z).
var axes: PackedByteArray = PackedByteArray()
## Hack: trace bar, 0..1; the hack fails at 1.
var trace: PackedFloat64Array = PackedFloat64Array()
## Hack: the node the route is at.
var node: PackedInt32Array = PackedInt32Array()
## Hack: bit n set for each node the player may see (revealed or visited).
var known: PackedInt64Array = PackedInt64Array()
## 1 when the contact was in probe coverage at the start (P13).
var probe: PackedByteArray = PackedByteArray()
## Tick the last own-ship scan finished on, or -1 (FT-SCI-009, P10).
var self_scanned: PackedInt32Array = PackedInt32Array()

## Derived cache, not state: ScienceSystem.noise_parts of the selected contact, written
## every tick for ships that have one (the net thread's copy cannot ask the probes).
var preview: Array[Dictionary] = []


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	active.append(0)
	ping_left.append(0.0)
	ping_cool.append(0.0)
	selected.append(-1)
	scan_x.append(NO_POINT)
	scan_y.append(0.0)
	scan_z.append(0.0)
	kind.append(Session.NONE)
	target.append(-1)
	puzzle_seed.append(0)
	noise.append(0.0)
	start_tick.append(0)
	subsystem.append(-1)
	axes.append(0)
	trace.append(0.0)
	node.append(-1)
	known.append(0)
	probe.append(0)
	self_scanned.append(-1)
	preview.append({})


## Whether the ship has a scan point.
func has_scan_point(ship: int) -> bool:
	return is_finite(scan_x[ship])


## Sets the ship's scan point (m), or clears it when `at` is empty.
func set_scan_point(ship: int, at: PackedFloat64Array) -> void:
	var none: bool = at.size() != 3
	scan_x[ship] = NO_POINT if none else at[0]
	scan_y[ship] = 0.0 if none else at[1]
	scan_z[ship] = 0.0 if none else at[2]


## Closes the ship's session.
func clear_session(ship: int) -> void:
	kind[ship] = Session.NONE
	target[ship] = -1
	subsystem[ship] = -1
	axes[ship] = 0
	trace[ship] = 0.0
	node[ship] = -1
	known[ship] = 0
	probe[ship] = 0


## The preview cache: derived, not state.
func not_columns() -> Array[StringName]:
	return [&"preview"]
