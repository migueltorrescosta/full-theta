class_name ScienceTable
extends SimTable
## Science state, one row per ship keyed by ship id and faction (E01, FT-SCI-003,
## FT-SCI-004 to FT-SCI-011): the sensor mode and active ping, the selected contact, the
## scan-position mark (kept outside the eight crew marks, FT-SCI-010), the one open
## minigame session and the own-ship scan. What each faction has learned of a contact is
## in KnowledgeTable.scan_conf; hack windows on the target are in HackTable. A session
## stores only its puzzle_seed and numbers: the puzzle is regenerated from them (ScanPuzzle,
## HackPuzzle), so state stays small and replays reproduce it.

## What the ship's open session is.
enum Session { NONE, SCAN, HACK, SELF }

## 1 while the sensors are in active mode (FT-SCI-003).
var active: PackedByteArray = PackedByteArray()
## Seconds left of the active ping's low-noise window.
var ping_left: PackedFloat64Array = PackedFloat64Array()
## Seconds until the next ping may start.
var ping_cool: PackedFloat64Array = PackedFloat64Array()
## Contact the Science panel has selected (noise preview), or -1.
var selected: PackedInt32Array = PackedInt32Array()
## Contact the scan-position mark was placed for, or -1 for none (FT-SCI-010).
var mark_contact: PackedInt32Array = PackedInt32Array()
## Site and site-local position of the mark (m, 64-bit like Kinematics).
var mark_site: PackedInt32Array = PackedInt32Array()
var mark_x: PackedFloat64Array = PackedFloat64Array()
var mark_y: PackedFloat64Array = PackedFloat64Array()
var mark_z: PackedFloat64Array = PackedFloat64Array()
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
	mark_contact.append(-1)
	mark_site.append(0)
	mark_x.append(0.0)
	mark_y.append(0.0)
	mark_z.append(0.0)
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


func columns() -> Array:
	return (
		super()
		+ [
			["active", active],
			["ping_left", ping_left],
			["ping_cool", ping_cool],
			["selected", selected],
			["mark_contact", mark_contact],
			["mark_site", mark_site],
			["mark_x", mark_x],
			["mark_y", mark_y],
			["mark_z", mark_z],
			["kind", kind],
			["target", target],
			["puzzle_seed", puzzle_seed],
			["noise", noise],
			["start_tick", start_tick],
			["subsystem", subsystem],
			["axes", axes],
			["trace", trace],
			["node", node],
			["known", known],
			["probe", probe],
			["self_scanned", self_scanned],
		]
	)


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
