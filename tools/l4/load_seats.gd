class_name LoadSeats
extends RefCounted
## The 64-connection seat plan of the load gate (#11, FT-GEN-003, D160): 36 crew (the six
## stations of each of 6 ships), one Captain per ship, and 22 viewers dealt round the
## ships (4, 4, 4, 4, 3, 3). TEST AND DEV ONLY: used by tools/l4/load_client.gd and the L3
## session-cap test; the real multi-ship lobby has no seat plan.

const STATIONS: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
const CONNECTIONS: int = 64


## [ship, entry] of seat i (0 .. 63) with `ships` crewable ships.
static func seat(i: int, ships: int = 6) -> Array:
	var crew: int = ships * STATIONS.size()
	if i < crew:
		return [i / STATIONS.size(), STATIONS[i % STATIONS.size()]]
	if i < crew + ships:
		return [i - crew, StationViews.CAPTAIN]
	return [(i - crew - ships) % ships, StationViews.VIEWER]


## True for the one seat per ship that presses Start (its Helm).
static func starts(i: int, ships: int = 6) -> bool:
	return i < ships * STATIONS.size() and i % STATIONS.size() == 0
